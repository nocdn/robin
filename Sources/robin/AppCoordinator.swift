import AppKit
import Foundation

@MainActor
final class AppCoordinator {
    private let settingsManager = SettingsManager()
    private lazy var settingsWindow = SettingsWindowController(
        settingsManager: settingsManager,
        onHotKeyChange: { [weak self] in
            self?.reloadHotKey()
        }
    )
    private let notifier = Notifier()
    private let recorder = AudioRecorder()
    private let liveAudioCapture = LiveAudioCapture()
    private let textDelivery = TextDelivery()
    private let localParakeetClient = LocalParakeetTranscriptionClient.shared
    private let localParakeetStreamingClient = LocalParakeetStreamingTranscriptionClient.shared
    private var settings: AppSettings?
    private var hotKeyMonitor: GlobalHotKeyMonitor?
    private var workflowState: WorkflowState = .idle
    private var streamingProcessingTask: Task<Void, Error>?
    private var streamingStopRequested = false
    private var streamingReleaseStartedAt: Date?
    private var streamingLiveInsertionEnabled = false
    private var streamingLiveInsertedText = ""
    private var streamingPreviousPartialText = ""
    private var streamingLiveChunkCount = 0

    private enum WorkflowState: Equatable {
        case idle
        case recordingStandard
        case transcribingStandard
        case startingStreaming
        case streaming
        case finalizingStreaming
    }

    func start() async {
        Logger.shared.info("Robin starting")
        do {
            try settingsManager.ensureApplicationDirectories()
            Logger.shared.info("Application support directory ready")
            settings = try settingsManager.loadOrCreate()
            Logger.shared.info("Loaded settings")
            try configureHotKey()
            await notifier.requestAuthorization()
            do {
                try await recorder.requestPermission()
            } catch {
                Logger.shared.error("Microphone permission request failed: \(error.localizedDescription)")
                notifier.error(error)
            }
            Logger.shared.info("Robin startup complete")
        } catch {
            Logger.shared.error("Startup failed: \(error.localizedDescription)")
            notifier.error(error)
        }
    }

    func openSettings() {
        do {
            _ = try settingsManager.loadOrCreate()
            Logger.shared.info("Opening settings window")
            settingsWindow.show()
        } catch {
            Logger.shared.error("Opening settings failed: \(error.localizedDescription)")
            notifier.error(error)
        }
    }

    func showHistory() {
        do {
            let currentSettings = try settingsManager.loadOrCreate()
            try FileManager.default.createDirectory(
                at: currentSettings.resolvedHistoryDirectory,
                withIntermediateDirectories: true
            )
            Logger.shared.info("Opening history: \(currentSettings.resolvedHistoryDirectory.path)")
            NSWorkspace.shared.open(currentSettings.resolvedHistoryDirectory)
        } catch {
            Logger.shared.error("Opening history failed: \(error.localizedDescription)")
            notifier.error(error)
        }
    }

    func showLogs() {
        Logger.shared.info("Opening log file: \(Logger.shared.logURL.path)")
        NSWorkspace.shared.activateFileViewerSelecting([Logger.shared.logURL])
    }

    func resetSettings() {
        do {
            Logger.shared.info("Resetting settings to defaults")
            settings = try settingsManager.resetToDefaults()
            hotKeyMonitor?.stop()
            try configureHotKey()
            settingsWindow.show()
        } catch {
            Logger.shared.error("Reset settings failed: \(error.localizedDescription)")
            notifier.error(error)
        }
    }

    private func configureHotKey() throws {
        let currentSettings = try settingsManager.loadOrCreate()
        settings = currentSettings
        let hotKey = try HotKeyParser.parse(currentSettings.hotkey)
        Logger.shared.info("Configuring hotkey '\(currentSettings.hotkey)' keyCode=\(hotKey.keyCode) modifiers=\(hotKey.modifiers.rawValue)")

        let monitor = GlobalHotKeyMonitor(hotKey: hotKey)
        monitor.onPressed = { [weak self] in
            Task { @MainActor in
                await self?.startRecording()
            }
        }
        monitor.onReleased = { [weak self] in
            Task { @MainActor in
                self?.stopRecordingAndTranscribe()
            }
        }
        try monitor.start()
        hotKeyMonitor = monitor
        Logger.shared.info("Hotkey monitor started")
    }

    private func reloadHotKey() {
        do {
            hotKeyMonitor?.stop()
            try configureHotKey()
        } catch {
            Logger.shared.error("Reload hotkey failed: \(error.localizedDescription)")
            notifier.error(error)
        }
    }

    private func startRecording() async {
        Logger.shared.info("Hotkey pressed")
        guard workflowState == .idle else {
            Logger.shared.info("Ignoring press while workflow state is \(workflowState)")
            return
        }

        do {
            let currentSettings = try settingsManager.loadOrCreate()
            settings = currentSettings
            Logger.shared.info(
                "Settings reloaded before recording; backend=\(currentSettings.transcriptionBackend.rawValue) parakeetMode=\(currentSettings.localParakeetMode.rawValue) insertMode=\(currentSettings.deliveryMode.rawValue)"
            )

            guard currentSettings.transcriptionBackend != .cohere ||
                !currentSettings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                throw RobinError.missingAPIKey
            }

            if currentSettings.transcriptionBackend == .localParakeet,
               currentSettings.localParakeetMode == .streaming {
                try await startStreamingRecording(settings: currentSettings)
            } else {
                try recorder.start(directory: currentSettings.resolvedRecordingDirectory)
                workflowState = .recordingStandard
                Logger.shared.info("Standard batch recording started")
            }
        } catch {
            Logger.shared.error("Start recording failed: \(error.localizedDescription)")
            workflowState = .idle
            notifier.error(error)
        }
    }

    private func stopRecordingAndTranscribe() {
        Logger.shared.info("Hotkey released")
        switch workflowState {
        case .startingStreaming:
            streamingStopRequested = true
            workflowState = .finalizingStreaming
            Logger.shared.info("Streaming release received while startup was in progress")
            return
        case .streaming:
            stopStreamingRecordingAndTranscribe()
            return
        case .idle:
            Logger.shared.info("Release ignored because workflow was idle")
            return
        case .transcribingStandard, .finalizingStreaming:
            Logger.shared.info("Release ignored because workflow state is \(workflowState)")
            return
        case .recordingStandard:
            break
        }

        guard let audioURL = recorder.stop() else {
            Logger.shared.info("Release ignored because recorder was not active")
            workflowState = .idle
            return
        }
        guard let currentSettings = settings else {
            Logger.shared.error("Release ignored because settings were missing")
            workflowState = .idle
            return
        }

        workflowState = .transcribingStandard
        Logger.shared.info("Standard batch recording stopped: \(audioURL.path)")

        Task {
            do {
                let text: String
                switch currentSettings.transcriptionBackend {
                case .cohere:
                    let client = CohereTranscriptionClient(settings: currentSettings)
                    Logger.shared.info("Sending recording to Cohere")
                    clickBeforeBatchInsertionIfNeeded(settings: currentSettings)
                    text = try await client.transcribe(audioURL: audioURL)
                case .localParakeet:
                    Logger.shared.info("Transcribing recording with local Parakeet standard batch")
                    clickBeforeBatchInsertionIfNeeded(settings: currentSettings)
                    text = try await localParakeetClient.transcribe(audioURL: audioURL, settings: currentSettings)
                }
                try completeTranscription(text, settings: currentSettings)
                try? FileManager.default.removeItem(at: audioURL)
            } catch {
                Logger.shared.error("Transcription workflow failed: \(error.localizedDescription)")
                notifier.error(error)
            }

            workflowState = .idle
            Logger.shared.info("Transcription workflow finished")
        }
    }

    private func clickBeforeBatchInsertionIfNeeded(settings currentSettings: AppSettings) {
        guard currentSettings.deliveryMode == .insert,
              currentSettings.clickBeforeInserting
        else {
            return
        }

        do {
            try textDelivery.clickCurrentMouseLocationForInsertion()
        } catch {
            Logger.shared.error("Click before inserting failed: \(error.localizedDescription)")
        }
    }

    private func startStreamingRecording(settings currentSettings: AppSettings) async throws {
        workflowState = .startingStreaming
        streamingStopRequested = false
        streamingReleaseStartedAt = nil
        streamingLiveInsertionEnabled = currentSettings.deliveryMode == .insert
        streamingLiveInsertedText = ""
        streamingPreviousPartialText = ""
        streamingLiveChunkCount = 0
        Logger.shared.info(
            "STREAM_WORKFLOW_PREPARE backend=\(currentSettings.transcriptionBackend.rawValue) parakeetMode=\(currentSettings.localParakeetMode.rawValue) deliveryMode=\(currentSettings.deliveryMode.rawValue) language=\(currentSettings.language)"
        )
        try await localParakeetStreamingClient.startSession(
            settings: currentSettings,
            onPartialTranscript: { [weak self] transcript in
                Task { @MainActor in
                    self?.handleStreamingPartialTranscript(transcript)
                }
            }
        )

        guard !streamingStopRequested, workflowState == .startingStreaming else {
            await localParakeetStreamingClient.cancelSession()
            workflowState = .idle
            streamingStopRequested = false
            Logger.shared.info("Streaming startup cancelled before capture began")
            return
        }

        let stream = try liveAudioCapture.start()
        Logger.shared.info("STREAM_WORKFLOW_PROCESSING_TASK_CREATE")
        streamingProcessingTask = Task {
            do {
                for await buffer in stream {
                    try Task.checkCancellation()
                    try await localParakeetStreamingClient.process(buffer)
                }
            } catch is CancellationError {
                Logger.shared.info("Streaming buffer processing cancelled")
                throw CancellationError()
            } catch {
                Logger.shared.error("Streaming buffer processing failed: \(error.localizedDescription)")
                throw error
            }
        }
        workflowState = .streaming
        Logger.shared.info(
            "STREAM_WORKFLOW_RECORDING_STARTED liveInsertionEnabled=\(streamingLiveInsertionEnabled) finalDeliveryOnRelease=\(!streamingLiveInsertionEnabled)"
        )
    }

    private func stopStreamingRecordingAndTranscribe() {
        guard let currentSettings = settings else {
            Logger.shared.error("Streaming release ignored because settings were missing")
            liveAudioCapture.stop()
            workflowState = .idle
            return
        }

        workflowState = .finalizingStreaming
        streamingReleaseStartedAt = Date()
        Logger.shared.info("STREAM_WORKFLOW_RELEASE_BEGIN stoppingCapture=true")
        liveAudioCapture.stop()
        let processingTask = streamingProcessingTask
        streamingProcessingTask = nil

        Task {
            do {
                try await processingTask?.value
                Logger.shared.info("STREAM_WORKFLOW_PROCESSING_TASK_DRAINED")
                let text = try await localParakeetStreamingClient.finishSession()
                Logger.shared.info("STREAM_WORKFLOW_FINAL_TEXT_READY chars=\(text.count) deliveringNow=true")
                let shouldDeliverFinalTranscript = currentSettings.deliveryMode != .insert || !streamingLiveInsertionEnabled
                if streamingLiveInsertionEnabled {
                    finishStreamingLiveInsertion(finalText: text)
                }
                try completeTranscription(
                    text,
                    settings: currentSettings,
                    deliverFinalTranscript: shouldDeliverFinalTranscript
                )
            } catch {
                await localParakeetStreamingClient.cancelSession()
                Logger.shared.error("Streaming transcription workflow failed: \(error.localizedDescription)")
                notifier.error(error)
            }

            workflowState = .idle
            let elapsedMs = streamingReleaseStartedAt.map { Int(Date().timeIntervalSince($0) * 1000) } ?? -1
            streamingReleaseStartedAt = nil
            streamingLiveInsertionEnabled = false
            streamingLiveInsertedText = ""
            streamingPreviousPartialText = ""
            streamingLiveChunkCount = 0
            Logger.shared.info("STREAM_WORKFLOW_RELEASE_END elapsedMs=\(elapsedMs)")
        }
    }

    private func handleStreamingPartialTranscript(_ partialText: String) {
        guard streamingLiveInsertionEnabled else { return }
        guard workflowState == .streaming || workflowState == .finalizingStreaming else { return }
        guard !partialText.isEmpty else { return }

        let stablePrefix = stableWordBoundaryPrefix(
            in: commonPrefix(streamingPreviousPartialText, partialText)
        )
        streamingPreviousPartialText = partialText

        guard stablePrefix.hasPrefix(streamingLiveInsertedText) else {
            streamingLiveInsertionEnabled = false
            Logger.shared.info(
                "STREAM_LIVE_INSERT_DISABLED reason=partialRevision insertedChars=\(streamingLiveInsertedText.count) stablePrefixChars=\(stablePrefix.count) partialChars=\(partialText.count)"
            )
            return
        }

        let delta = String(stablePrefix.dropFirst(streamingLiveInsertedText.count))
        guard !delta.isEmpty else { return }

        do {
            try textDelivery.insertLiveChunk(delta)
            streamingLiveInsertedText = stablePrefix
            streamingLiveChunkCount += 1
            Logger.shared.info(
                "STREAM_LIVE_INSERT_STABLE_CHUNK index=\(streamingLiveChunkCount) deltaChars=\(delta.count) insertedChars=\(streamingLiveInsertedText.count) partialChars=\(partialText.count)"
            )
        } catch {
            streamingLiveInsertionEnabled = false
            Logger.shared.error("STREAM_LIVE_INSERT_DISABLED error=\(error.localizedDescription)")
            notifier.error(error)
        }
    }

    private func commonPrefix(_ lhs: String, _ rhs: String) -> String {
        var lhsIndex = lhs.startIndex
        var rhsIndex = rhs.startIndex
        var result = ""

        while lhsIndex < lhs.endIndex, rhsIndex < rhs.endIndex, lhs[lhsIndex] == rhs[rhsIndex] {
            result.append(lhs[lhsIndex])
            lhs.formIndex(after: &lhsIndex)
            rhs.formIndex(after: &rhsIndex)
        }

        return result
    }

    private func stableWordBoundaryPrefix(in text: String) -> String {
        var index = text.startIndex
        var lastWordBoundary: String.Index?

        while index < text.endIndex {
            if text[index].isWhitespace {
                lastWordBoundary = index
            }
            text.formIndex(after: &index)
        }

        guard let lastWordBoundary else { return "" }
        return String(text[..<lastWordBoundary])
    }

    private func finishStreamingLiveInsertion(finalText: String) {
        let trimmedFinalText = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFinalText.isEmpty else { return }

        guard trimmedFinalText.hasPrefix(streamingLiveInsertedText) else {
            Logger.shared.info(
                "STREAM_LIVE_FINAL_DELTA_SKIP insertedChars=\(streamingLiveInsertedText.count) finalChars=\(trimmedFinalText.count)"
            )
            return
        }

        let delta = String(trimmedFinalText.dropFirst(streamingLiveInsertedText.count))
        guard !delta.isEmpty else {
            Logger.shared.info("STREAM_LIVE_FINAL_DELTA_EMPTY insertedChars=\(streamingLiveInsertedText.count)")
            return
        }

        do {
            try textDelivery.insertLiveChunk(delta)
            streamingLiveInsertedText = trimmedFinalText
            streamingLiveChunkCount += 1
            Logger.shared.info(
                "STREAM_LIVE_FINAL_DELTA_INSERTED index=\(streamingLiveChunkCount) deltaChars=\(delta.count) insertedChars=\(streamingLiveInsertedText.count)"
            )
        } catch {
            streamingLiveInsertionEnabled = false
            Logger.shared.error("STREAM_LIVE_FINAL_DELTA_FAILED error=\(error.localizedDescription)")
            notifier.error(error)
        }
    }

    private func completeTranscription(
        _ text: String,
        settings currentSettings: AppSettings,
        deliverFinalTranscript: Bool = true
    ) throws {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw RobinError.emptyTranscript
        }

        Logger.shared.info(
            "TRANSCRIPT_COMPLETE backend=\(currentSettings.transcriptionBackend.rawValue) parakeetMode=\(currentSettings.localParakeetMode.rawValue) characters=\(trimmedText.count)"
        )
        let transcriptURL = try TranscriptStore(settings: currentSettings).save(trimmedText)
        Logger.shared.info("Transcript saved: \(transcriptURL.path)")
        if deliverFinalTranscript {
            Logger.shared.info("TRANSCRIPT_DELIVERY_BEGIN mode=\(currentSettings.deliveryMode.rawValue)")
            try textDelivery.deliver(
                trimmedText,
                mode: currentSettings.deliveryMode,
                alwaysCopyTranscription: currentSettings.alwaysCopyTranscription
            )
            Logger.shared.info("TRANSCRIPT_DELIVERY_END mode=\(currentSettings.deliveryMode.rawValue)")
        } else {
            Logger.shared.info("TRANSCRIPT_DELIVERY_SKIPPED reason=alreadyInsertedLive")
            if currentSettings.deliveryMode == .insert, currentSettings.alwaysCopyTranscription {
                textDelivery.copyTranscriptionToClipboard(trimmedText)
            }
        }
        print("Saved transcript: \(transcriptURL.path)")
    }
}
