import AVFoundation
import Foundation

@MainActor
final class AudioRecorder {
    private var recorder: AVAudioRecorder?
    private var currentURL: URL?

    func requestPermission() async throws {
        Logger.shared.info("Requesting microphone permission")
        let granted = await AVAudioApplication.requestRecordPermission()
        Logger.shared.info("Microphone permission granted: \(granted)")
        guard granted else {
            throw RobinError.microphonePermissionDenied
        }
    }

    func start(directory: URL) throws {
        guard recorder == nil else {
            Logger.shared.info("Recorder already active; start ignored")
            return
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = directory.appendingPathComponent("recording-\(UUID().uuidString).wav")
        Logger.shared.info("Preparing AVAudioRecorder at \(url.path)")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.prepareToRecord()
        guard recorder.record() else {
            throw RobinError.audioRecordingFailed
        }

        self.recorder = recorder
        currentURL = url
    }

    func stop() -> URL? {
        guard let recorder, let currentURL else {
            Logger.shared.info("Recorder stop requested but recorder/currentURL was nil")
            return nil
        }
        recorder.stop()
        Logger.shared.info("AVAudioRecorder stopped")
        self.recorder = nil
        self.currentURL = nil
        return currentURL
    }
}
