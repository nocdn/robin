import AppKit
import Foundation

@MainActor
final class AppCoordinator {
    private let settingsManager = SettingsManager()
    private let notifier = Notifier()
    private let recorder = AudioRecorder()
    private let textDelivery = TextDelivery()
    private var settings: AppSettings?
    private var hotKeyMonitor: GlobalHotKeyMonitor?
    private var isTranscribing = false

    func start() async {
        Logger.shared.info("Robin starting")
        do {
            try settingsManager.ensureApplicationDirectories()
            Logger.shared.info("Application support directory ready")
            settings = try settingsManager.loadOrCreate()
            Logger.shared.info("Loaded settings from \(settingsManager.configURL.path)")
            await notifier.requestAuthorization()
            try await recorder.requestPermission()
            try configureHotKey()
            Logger.shared.info("Robin startup complete")
        } catch {
            Logger.shared.error("Startup failed: \(error.localizedDescription)")
            notifier.error(error)
        }
    }

    func openSettings() {
        do {
            _ = try settingsManager.loadOrCreate()
            Logger.shared.info("Opening settings: \(settingsManager.configURL.path)")
            NSWorkspace.shared.open(settingsManager.configURL)
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
            NSWorkspace.shared.open(settingsManager.configURL)
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
                self?.startRecording()
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

    private func startRecording() {
        Logger.shared.info("Hotkey pressed")
        guard !isTranscribing else {
            Logger.shared.info("Ignoring press while transcription is already in progress")
            return
        }

        do {
            let currentSettings = try settingsManager.loadOrCreate()
            settings = currentSettings
            Logger.shared.info("Settings reloaded before recording; delivery_mode=\(currentSettings.deliveryMode.rawValue)")

            guard !currentSettings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw RobinError.missingAPIKey(settingsManager.configURL.path)
            }

            try recorder.start(directory: currentSettings.resolvedRecordingDirectory)
            Logger.shared.info("Recording started")
        } catch {
            Logger.shared.error("Start recording failed: \(error.localizedDescription)")
            notifier.error(error)
        }
    }

    private func stopRecordingAndTranscribe() {
        Logger.shared.info("Hotkey released")
        guard let audioURL = recorder.stop() else {
            Logger.shared.info("Release ignored because recorder was not active")
            return
        }
        guard let currentSettings = settings else {
            Logger.shared.error("Release ignored because settings were missing")
            return
        }

        isTranscribing = true
        Logger.shared.info("Recording stopped: \(audioURL.path)")

        Task {
            do {
                let client = CohereTranscriptionClient(settings: currentSettings)
                Logger.shared.info("Sending recording to Cohere")
                let text = try await client.transcribe(audioURL: audioURL)
                Logger.shared.info("Transcription complete; characters=\(text.count)")
                let transcriptURL = try TranscriptStore(settings: currentSettings).save(text)
                Logger.shared.info("Transcript saved: \(transcriptURL.path)")
                try textDelivery.deliver(text, mode: currentSettings.deliveryMode)
                Logger.shared.info("Transcript delivered via \(currentSettings.deliveryMode.rawValue)")
                try? FileManager.default.removeItem(at: audioURL)
                print("Saved transcript: \(transcriptURL.path)")
            } catch {
                Logger.shared.error("Transcription workflow failed: \(error.localizedDescription)")
                notifier.error(error)
            }

            isTranscribing = false
            Logger.shared.info("Transcription workflow finished")
        }
    }
}
