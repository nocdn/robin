import AVFoundation
import CoreML
import FluidAudio
import Foundation

actor LocalParakeetStreamingTranscriptionClient {
    static let shared = LocalParakeetStreamingTranscriptionClient()

    private var manager: StreamingEouAsrManager?
    private var loadedModelDirectory: URL?
    private var isSessionActive = false
    private var latestEouTranscript = ""
    private var latestPartialTranscript = ""
    private var sessionID: UUID?
    private var sessionStartedAt: Date?
    private var processedBufferCount = 0
    private var processedFrameCount: AVAudioFramePosition = 0

    func startSession(
        settings: AppSettings,
        onPartialTranscript: (@Sendable (String) -> Void)? = nil
    ) async throws {
        guard settings.language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "en" else {
            throw RobinError.localStreamingRequiresEnglish
        }

        let manager = try await loadManagerIfNeeded()
        await manager.reset()
        let id = UUID()
        sessionID = id
        sessionStartedAt = Date()
        processedBufferCount = 0
        processedFrameCount = 0
        await manager.setEouCallback { transcript in
            let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            Logger.shared.info(
                "STREAM_EOU_CALLBACK session=\(id.uuidString) chars=\(trimmed.count) text=\"\(Self.logSnippet(trimmed))\""
            )
            Task {
                await Self.shared.updateLatestEouTranscript(trimmed)
            }
        }
        await manager.setPartialCallback { transcript in
            let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            Logger.shared.info(
                "STREAM_PARTIAL_CALLBACK session=\(id.uuidString) chars=\(trimmed.count) text=\"\(Self.logSnippet(trimmed))\""
            )
            onPartialTranscript?(trimmed)
            Task {
                await Self.shared.updateLatestPartialTranscript(trimmed)
            }
        }
        latestEouTranscript = ""
        latestPartialTranscript = ""
        isSessionActive = true
        Logger.shared.info(
            "STREAM_SESSION_START session=\(id.uuidString) language=\(settings.language) chunkSize=\(LocalParakeetStreamingModelStore.chunkSize.modelSubdirectory) deliveryDeferredUntilRelease=true"
        )
    }

    func process(_ buffer: AVAudioPCMBuffer) async throws {
        guard isSessionActive else { return }
        let manager = try await loadManagerIfNeeded()
        processedBufferCount += 1
        processedFrameCount += AVAudioFramePosition(buffer.frameLength)
        let bufferIndex = processedBufferCount
        let cumulativeFrames = processedFrameCount
        let session = sessionID?.uuidString ?? "unknown"
        let elapsedBefore = sessionStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        if shouldLogBuffer(bufferIndex) {
            Logger.shared.info(
                "STREAM_PROCESS_BEGIN session=\(session) index=\(bufferIndex) frames=\(buffer.frameLength) cumulativeFrames=\(cumulativeFrames) elapsedMs=\(Int(elapsedBefore * 1000)) sampleRate=\(buffer.format.sampleRate)"
            )
        }
        let startedAt = Date()
        let processResult = try await manager.process(audioBuffer: buffer)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let processingMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        if shouldLogBuffer(bufferIndex) || !processResult.isEmpty {
            Logger.shared.info(
                "STREAM_PROCESS_END session=\(session) index=\(bufferIndex) processingMs=\(processingMs) directResultChars=\(processResult.count) directResult=\"\(Self.logSnippet(processResult))\""
            )
        }
    }

    func finishSession() async throws -> String {
        guard isSessionActive else {
            return ""
        }

        let manager = try await loadManagerIfNeeded()
        let session = sessionID?.uuidString ?? "unknown"
        Logger.shared.info(
            "STREAM_FINISH_BEGIN session=\(session) processedBuffers=\(processedBufferCount) processedFrames=\(processedFrameCount) latestEouChars=\(latestEouTranscript.count) latestPartialChars=\(latestPartialTranscript.count)"
        )
        let finishedTranscript = try await manager.finish()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        await manager.reset()
        isSessionActive = false

        let transcript = finishedTranscript.isEmpty ? latestEouTranscript : finishedTranscript
        let source = finishedTranscript.isEmpty ? "latestEouFallback" : "finish"
        Logger.shared.info(
            "STREAM_FINISH_END session=\(session) finishChars=\(finishedTranscript.count) latestEouChars=\(latestEouTranscript.count) latestPartialChars=\(latestPartialTranscript.count) chosenSource=\(source) chosenChars=\(transcript.count) chosenText=\"\(Self.logSnippet(transcript))\""
        )
        resetSessionDiagnostics()
        return transcript
    }

    func cancelSession() async {
        let session = sessionID?.uuidString ?? "unknown"
        if let manager {
            await manager.reset()
        }
        isSessionActive = false
        latestEouTranscript = ""
        latestPartialTranscript = ""
        Logger.shared.info("STREAM_SESSION_CANCEL session=\(session)")
        resetSessionDiagnostics()
    }

    func unload() async {
        if let manager {
            await manager.cleanup()
        }
        manager = nil
        loadedModelDirectory = nil
        isSessionActive = false
        resetSessionDiagnostics()
    }

    private func updateLatestEouTranscript(_ transcript: String) {
        latestEouTranscript = transcript
    }

    private func updateLatestPartialTranscript(_ transcript: String) {
        latestPartialTranscript = transcript
    }

    private func shouldLogBuffer(_ index: Int) -> Bool {
        index <= 8 || index.isMultiple(of: 10)
    }

    private func resetSessionDiagnostics() {
        sessionID = nil
        sessionStartedAt = nil
        processedBufferCount = 0
        processedFrameCount = 0
    }

    private nonisolated static func logSnippet(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\"", with: "'")
            .prefix(180)
            .description
    }

    private func loadManagerIfNeeded() async throws -> StreamingEouAsrManager {
        let modelDirectory = LocalParakeetStreamingModelStore.modelDirectory
        if let manager, loadedModelDirectory == modelDirectory {
            return manager
        }

        guard LocalParakeetStreamingModelStore.isDownloaded else {
            throw RobinError.localStreamingModelNotDownloaded(modelDirectory)
        }

        Logger.shared.info("Loading local Parakeet streaming model from \(modelDirectory.path)")
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        configuration.allowLowPrecisionAccumulationOnGPU = true
        let manager = StreamingEouAsrManager(
            configuration: configuration,
            chunkSize: LocalParakeetStreamingModelStore.chunkSize,
            eouDebounceMs: 1280
        )
        try await manager.loadModels(from: modelDirectory)
        self.manager = manager
        loadedModelDirectory = modelDirectory
        Logger.shared.info("Local Parakeet streaming model loaded")
        return manager
    }
}
