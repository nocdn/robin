import AVFoundation
import Foundation

extension AVAudioPCMBuffer: @retroactive @unchecked Sendable {}

final class LiveAudioCapture {
    private let engine = AVAudioEngine()
    private let continuationLock = NSLock()
    private var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    private var isCapturing = false
    private var capturedBufferCount = 0
    private var capturedFrameCount: AVAudioFramePosition = 0
    private var captureStartedAt: Date?

    func start() throws -> AsyncStream<AVAudioPCMBuffer> {
        guard !isCapturing else {
            throw RobinError.liveAudioCaptureFailed("audio capture is already active")
        }

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else {
            throw RobinError.liveAudioCaptureFailed("microphone input format was unavailable")
        }
        resetCounters(startedAt: Date())

        let stream = AsyncStream<AVAudioPCMBuffer> { continuation in
            self.setContinuation(continuation)
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            guard let copiedBuffer = Self.copy(buffer) else {
                Logger.shared.error("Live audio buffer copy failed")
                return
            }
            self.yield(copiedBuffer)
        }

        do {
            engine.prepare()
            try engine.start()
            isCapturing = true
            Logger.shared.info(
                "STREAM_CAPTURE_START sampleRate=\(format.sampleRate) channels=\(format.channelCount) format=\(format.commonFormat.rawValue) interleaved=\(format.isInterleaved) bufferSize=4096"
            )
            return stream
        } catch {
            inputNode.removeTap(onBus: 0)
            finishContinuation()
            resetCounters(startedAt: nil)
            throw RobinError.liveAudioCaptureFailed(error.localizedDescription)
        }
    }

    func stop() {
        guard isCapturing else { return }
        let summary = captureSummary()
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        engine.reset()
        finishContinuation()
        isCapturing = false
        Logger.shared.info("STREAM_CAPTURE_STOP \(summary)")
        resetCounters(startedAt: nil)
    }

    private func setContinuation(_ continuation: AsyncStream<AVAudioPCMBuffer>.Continuation) {
        continuationLock.lock()
        self.continuation = continuation
        continuationLock.unlock()
    }

    private func yield(_ buffer: AVAudioPCMBuffer) {
        continuationLock.lock()
        let continuation = self.continuation
        capturedBufferCount += 1
        capturedFrameCount += AVAudioFramePosition(buffer.frameLength)
        let bufferCount = capturedBufferCount
        let frameCount = capturedFrameCount
        let startedAt = captureStartedAt
        continuationLock.unlock()

        if shouldLogBuffer(bufferCount) {
            let elapsed = startedAt.map { Date().timeIntervalSince($0) } ?? 0
            Logger.shared.info(
                "STREAM_CAPTURE_BUFFER index=\(bufferCount) frames=\(buffer.frameLength) cumulativeFrames=\(frameCount) elapsedMs=\(Int(elapsed * 1000)) sampleRate=\(buffer.format.sampleRate)"
            )
        }
        continuation?.yield(buffer)
    }

    private func finishContinuation() {
        continuationLock.lock()
        let continuation = self.continuation
        self.continuation = nil
        continuationLock.unlock()
        continuation?.finish()
    }

    private func resetCounters(startedAt: Date?) {
        continuationLock.lock()
        capturedBufferCount = 0
        capturedFrameCount = 0
        captureStartedAt = startedAt
        continuationLock.unlock()
    }

    private func captureSummary() -> String {
        continuationLock.lock()
        let bufferCount = capturedBufferCount
        let frameCount = capturedFrameCount
        let startedAt = captureStartedAt
        continuationLock.unlock()
        let elapsed = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        return "buffers=\(bufferCount) frames=\(frameCount) elapsedMs=\(Int(elapsed * 1000))"
    }

    private nonisolated func shouldLogBuffer(_ index: Int) -> Bool {
        index <= 8 || index.isMultiple(of: 20)
    }

    private nonisolated static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let frameLength = buffer.frameLength
        guard let copiedBuffer = AVAudioPCMBuffer(
            pcmFormat: buffer.format,
            frameCapacity: max(frameLength, 1)
        ) else {
            return nil
        }
        copiedBuffer.frameLength = frameLength

        let sourceBuffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        let destinationBuffers = UnsafeMutableAudioBufferListPointer(copiedBuffer.mutableAudioBufferList)
        guard sourceBuffers.count == destinationBuffers.count else {
            return nil
        }

        for index in 0..<sourceBuffers.count {
            guard let sourceData = sourceBuffers[index].mData,
                  let destinationData = destinationBuffers[index].mData
            else {
                continue
            }
            let byteCount = Int(sourceBuffers[index].mDataByteSize)
            memcpy(destinationData, sourceData, byteCount)
            destinationBuffers[index].mDataByteSize = sourceBuffers[index].mDataByteSize
        }

        return copiedBuffer
    }
}
