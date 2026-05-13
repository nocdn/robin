import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let settingsManager: SettingsManager
    private let onHotKeyChange: () -> Void
    private var window: NSWindow?

    init(settingsManager: SettingsManager, onHotKeyChange: @escaping () -> Void) {
        self.settingsManager = settingsManager
        self.onHotKeyChange = onHotKeyChange
    }

    func show() {
        if let window {
            window.contentViewController = makeHostingController()
            resizeToContent()
            NSApplication.shared.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        window.title = "Robin - Settings"
        window.contentViewController = makeHostingController()
        window.isReleasedWhenClosed = false
        self.window = window

        resizeToContent()
        window.center()
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeHostingController() -> NSHostingController<SettingsView> {
        let view = SettingsView(
            settingsManager: settingsManager,
            onHotKeyChange: onHotKeyChange,
            onLayoutChange: { [weak self] in
                self?.resizeToContent()
            }
        )
        return NSHostingController(rootView: view)
    }

    private func resizeToContent() {
        guard
            let window,
            let hostingController = window.contentViewController as? NSHostingController<SettingsView>
        else {
            return
        }

        let size = hostingController.sizeThatFits(
            in: NSSize(width: 380, height: CGFloat.greatestFiniteMagnitude)
        )
        window.setContentSize(NSSize(width: 380, height: ceil(size.height)))
    }
}

private enum TranscriptionMode: String, CaseIterable, Identifiable {
    case cohere = "Cohere"
    case parakeet = "Parakeet"

    var id: String { rawValue }

    init(backend: TranscriptionBackend) {
        switch backend {
        case .cohere:
            self = .cohere
        case .localParakeet:
            self = .parakeet
        }
    }

    var backend: TranscriptionBackend {
        switch self {
        case .cohere:
            .cohere
        case .parakeet:
            .localParakeet
        }
    }
}

private struct SettingsView: View {
    private enum FocusedField: Hashable {
        case historyDirectory
    }

    private let settingsManager: SettingsManager
    private let onHotKeyChange: () -> Void
    private let onLayoutChange: () -> Void

    @State private var mode: TranscriptionMode = .cohere
    @State private var parakeetMode: LocalParakeetTranscriptionMode = .standard
    @State private var hotkey: String
    @State private var isListeningForHotkey = false
    @State private var hotkeyError: String?
    @State private var eventMonitor: Any?
    @State private var apiKey: String
    @State private var model: String
    @State private var isModelDownloaded = LocalParakeetModelStore.isDownloaded
    @State private var isDownloadingModel = false
    @State private var modelDownloadProgress = 0.0
    @State private var modelDownloadSizeBytes: Int64?
    @State private var modelDownloadError: String?
    @State private var historyDirectory: String
    @State private var savedHistoryDirectory: String
    @State private var deliveryMode: TranscriptDeliveryMode
    @State private var language: String
    @FocusState private var focusedField: FocusedField?

    init(
        settingsManager: SettingsManager,
        onHotKeyChange: @escaping () -> Void,
        onLayoutChange: @escaping () -> Void
    ) {
        self.settingsManager = settingsManager
        self.onHotKeyChange = onHotKeyChange
        self.onLayoutChange = onLayoutChange

        let settings = (try? settingsManager.loadOrCreate()) ?? AppSettings.defaultConfig
        _mode = State(initialValue: TranscriptionMode(backend: settings.transcriptionBackend))
        _parakeetMode = State(initialValue: settings.localParakeetMode)
        _isModelDownloaded = State(initialValue: {
            switch settings.localParakeetMode {
            case .standard:
                LocalParakeetModelStore.isDownloaded
            case .streaming:
                LocalParakeetStreamingModelStore.isDownloaded
            }
        }())
        _hotkey = State(initialValue: settings.hotkey)
        _apiKey = State(initialValue: settings.apiKey)
        _model = State(initialValue: settings.model)
        _historyDirectory = State(initialValue: settings.historyDirectory)
        _savedHistoryDirectory = State(initialValue: settings.historyDirectory)
        _deliveryMode = State(initialValue: settings.deliveryMode)
        _language = State(initialValue: settings.language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Hotkey")

                HStack(spacing: 8) {
                    Button(isListeningForHotkey ? "Listening" : displayHotKey(hotkey)) {
                        startHotKeyCapture()
                    }

                    Button("Reset") {
                        setHotKey(HotKeyParser.defaultValue)
                    }
                    .disabled(isDefaultHotKey)
                }

                if let hotkeyError {
                    Text(hotkeyError)
                        .foregroundColor(.orange)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 0) {
                    Text("Mode ")
                    Text("Cloud or local")
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 8) {
                    Picker("", selection: $mode) {
                        ForEach(TranscriptionMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .onChange(of: mode) { _, _ in
                        saveTranscriptionBackend()
                    }

                    if mode == .parakeet {
                        Picker("", selection: $parakeetMode) {
                            ForEach(LocalParakeetTranscriptionMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .onChange(of: parakeetMode) { _, _ in
                            saveParakeetMode()
                        }
                    }
                }
            }

            if mode == .cohere {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Cohere API Key")

                    HStack(spacing: 8) {
                        TextField("", text: $apiKey)
                            .frame(maxWidth: .infinity)

                        Button("Save") {
                            saveAPIKey()
                        }
                        .fixedSize()
                    }
                    .frame(maxWidth: .infinity)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Model Slug")

                    TextField("", text: $model)
                        .frame(maxWidth: .infinity)
                        .onChange(of: model) { _, _ in
                            saveModel()
                        }
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Button(localModelButtonTitle) {
                            downloadLocalModel()
                        }
                        .disabled(isDownloadingModel || isModelDownloaded)

                        if isDownloadingModel {
                            HStack(spacing: 6) {
                                DownloadProgressRing(progress: modelDownloadProgress)

                                Text(modelDownloadStatusText)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .monospacedDigit()
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(modelDownloadAccessibilityText)
                        }

                        if isModelDownloaded {
                            Button("Remove") {
                                removeLocalModel()
                            }
                            .disabled(isDownloadingModel)
                        }
                    }

                    if let modelDownloadError {
                        Text(modelDownloadError)
                            .foregroundColor(.orange)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 0) {
                    Text("History folder ")
                    Text("Enter to save")
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 8) {
                    TextField("", text: $historyDirectory)
                        .frame(maxWidth: .infinity)
                        .focused($focusedField, equals: .historyDirectory)
                        .onSubmit {
                            saveHistoryDirectory()
                        }

                    Button("Open") {
                        openHistoryDirectory()
                    }
                    .fixedSize()

                    Button("Reset") {
                        historyDirectory = AppSettings.defaultConfig.historyDirectory
                        saveHistoryDirectory()
                    }
                    .fixedSize()
                    .disabled(savedHistoryDirectory == AppSettings.defaultConfig.historyDirectory)
                }
                .frame(maxWidth: .infinity)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Insert mode")

                Picker("", selection: $deliveryMode) {
                    Text("Insert").tag(TranscriptDeliveryMode.insert)
                    Text("Clipboard").tag(TranscriptDeliveryMode.clipboard)
                }
                .labelsHidden()
                .onChange(of: deliveryMode) { _, _ in
                    saveDeliveryMode()
                }
            }

            HStack(spacing: 8) {
                Text("Language:")

                TextField("", text: $language)
                    .frame(width: 80)
                    .onChange(of: language) { _, _ in
                        saveLanguage()
                    }

                Text("ISO 639-1")
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .frame(width: 380, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: mode) { _, _ in
            Task { @MainActor in
                onLayoutChange()
            }
        }
        .onDisappear {
            stopHotKeyCapture()
        }
        .onChange(of: focusedField) { oldValue, newValue in
            if oldValue == .historyDirectory, newValue != .historyDirectory {
                historyDirectory = savedHistoryDirectory
            }
        }
    }

    private var isDefaultHotKey: Bool {
        hotkey == HotKeyParser.defaultValue
    }

    private var localModelButtonTitle: String {
        if isDownloadingModel {
            return "Downloading"
        }
        if isModelDownloaded {
            return "Downloaded"
        }
        return "Download \(selectedLocalModelName)"
    }

    private var selectedLocalModelName: String {
        switch parakeetMode {
        case .standard:
            LocalParakeetModelStore.modelName
        case .streaming:
            LocalParakeetStreamingModelStore.modelName
        }
    }

    private var selectedLocalModelDownloaded: Bool {
        switch parakeetMode {
        case .standard:
            LocalParakeetModelStore.isDownloaded
        case .streaming:
            LocalParakeetStreamingModelStore.isDownloaded
        }
    }

    private var selectedLocalModelFallbackDownloadSizeBytes: Int64 {
        switch parakeetMode {
        case .standard:
            LocalParakeetModelStore.fallbackDownloadSizeBytes
        case .streaming:
            LocalParakeetStreamingModelStore.fallbackDownloadSizeBytes
        }
    }

    private var modelDownloadStatusText: String {
        "\(modelDownloadPercent)% · \(formattedModelDownloadSize)"
    }

    private var modelDownloadAccessibilityText: String {
        "Downloading \(selectedLocalModelName), \(modelDownloadPercent) percent of \(formattedModelDownloadSize)"
    }

    private var modelDownloadPercent: Int {
        Int((clampedDownloadProgress * 100).rounded())
    }

    private var formattedModelDownloadSize: String {
        let bytes = modelDownloadSizeBytes ?? selectedLocalModelFallbackDownloadSizeBytes
        let megabytes = Double(bytes) / 1_000_000

        if megabytes >= 1_000 {
            return String(format: "%.1f GB", megabytes / 1_000)
        }

        return "\(Int(megabytes.rounded())) MB"
    }

    private var clampedDownloadProgress: Double {
        min(max(modelDownloadProgress, 0), 1)
    }

    private func startHotKeyCapture() {
        stopHotKeyCapture()
        hotkeyError = nil
        isListeningForHotkey = true

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if event.type == .flagsChanged, HotKeyParser.keyName(for: event.keyCode) != "fn" {
                return event
            }
            captureHotKey(from: event)
            return nil
        }
    }

    private func stopHotKeyCapture() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        isListeningForHotkey = false
    }

    private func captureHotKey(from event: NSEvent) {
        guard let keyName = HotKeyParser.keyName(for: event.keyCode) else {
            hotkeyError = "Unsupported key"
            stopHotKeyCapture()
            return
        }

        let candidate = normalizedHotKey(modifiers: event.modifierFlags, keyName: keyName)
        if let error = validationError(for: candidate, keyName: keyName, modifiers: event.modifierFlags) {
            hotkeyError = error
            stopHotKeyCapture()
            return
        }

        setHotKey(candidate)
        stopHotKeyCapture()
    }

    private func setHotKey(_ value: String) {
        do {
            _ = try HotKeyParser.parse(value)
            _ = try settingsManager.update { settings in
                settings.hotkey = value
            }
            hotkey = value
            hotkeyError = nil
            onHotKeyChange()
        } catch {
            hotkeyError = "Invalid hotkey"
        }
    }

    private func normalizedHotKey(modifiers: NSEvent.ModifierFlags, keyName: String) -> String {
        var pieces: [String] = []
        if modifiers.contains(.control) {
            pieces.append("control")
        }
        if modifiers.contains(.option) {
            pieces.append("option")
        }
        if modifiers.contains(.shift) {
            pieces.append("shift")
        }
        if modifiers.contains(.command) {
            pieces.append("command")
        }
        if modifiers.contains(.function), keyName != "fn" {
            pieces.append("fn")
        }
        pieces.append(keyName)
        return pieces.joined(separator: "+")
    }

    private func validationError(
        for candidate: String,
        keyName: String,
        modifiers: NSEvent.ModifierFlags
    ) -> String? {
        let hasModifier = modifiers.contains(.control) ||
            modifiers.contains(.option) ||
            modifiers.contains(.shift) ||
            modifiers.contains(.command) ||
            modifiers.contains(.function)
        let typingKeys = Set("abcdefghijklmnopqrstuvwxyz0123456789".map(String.init))
            .union(["[", "]", "\\", ";", "'", ",", ".", "/", "`", "-", "="])
        let reservedPlainKeys: Set<String> = ["space", "tab", "return", "escape", "delete"]
        let reservedCommandShortcuts: Set<String> = ["command+q", "command+w", "command+h", "command+m", "command+space"]

        if !hasModifier, typingKeys.contains(keyName) {
            return "Add a modifier for typing keys"
        }
        if !hasModifier, reservedPlainKeys.contains(keyName) {
            return "Choose a less disruptive key"
        }
        if reservedCommandShortcuts.contains(candidate) {
            return "That shortcut is reserved"
        }

        return nil
    }

    private func displayHotKey(_ value: String) -> String {
        value
            .split(separator: "+")
            .map { displayHotKeyPart(String($0)) }
            .joined(separator: " + ")
    }

    private func displayHotKeyPart(_ value: String) -> String {
        switch value.lowercased() {
        case "control", "ctrl", "^":
            "Control"
        case "command", "cmd", "⌘":
            "Command"
        case "option", "opt", "alt", "⌥":
            "Option"
        case "shift", "⇧":
            "Shift"
        case "fn", "function":
            "Fn"
        case "space":
            "Space"
        case "return":
            "Return"
        case "escape":
            "Esc"
        default:
            value
        }
    }

    private func saveAPIKey() {
        do {
            _ = try settingsManager.update { settings in
                settings.apiKey = apiKey
            }
        } catch {
            presentSaveError(error)
        }
    }

    private func saveTranscriptionBackend() {
        do {
            _ = try settingsManager.update { settings in
                settings.transcriptionBackend = mode.backend
            }
            isModelDownloaded = selectedLocalModelDownloaded
            modelDownloadError = nil
        } catch {
            presentSaveError(error)
        }
    }

    private func saveParakeetMode() {
        do {
            _ = try settingsManager.update { settings in
                settings.localParakeetMode = parakeetMode
            }
            isModelDownloaded = selectedLocalModelDownloaded
            modelDownloadProgress = 0
            modelDownloadSizeBytes = nil
            modelDownloadError = nil
        } catch {
            presentSaveError(error)
        }
    }

    private func saveModel() {
        do {
            _ = try settingsManager.update { settings in
                settings.model = model
            }
        } catch {
            presentSaveError(error)
        }
    }

    private func saveDeliveryMode() {
        do {
            _ = try settingsManager.update { settings in
                settings.deliveryMode = deliveryMode
            }
        } catch {
            presentSaveError(error)
        }
    }

    private func saveHistoryDirectory() {
        do {
            let updatedSettings = try settingsManager.update { settings in
                settings.historyDirectory = historyDirectory
            }
            historyDirectory = updatedSettings.historyDirectory
            savedHistoryDirectory = updatedSettings.historyDirectory
        } catch {
            historyDirectory = savedHistoryDirectory
            presentSaveError(error)
        }
    }

    private func openHistoryDirectory() {
        do {
            let url = URL(fileURLWithPath: savedHistoryDirectory.expandingTildeInPath, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
        } catch {
            presentSaveError(error)
        }
    }

    private func saveLanguage() {
        do {
            _ = try settingsManager.update { settings in
                settings.language = language
            }
        } catch {
            presentSaveError(error)
        }
    }

    private func presentSaveError(_ error: Error) {
        Logger.shared.error("Saving settings failed: \(error.localizedDescription)")

        let alert = NSAlert(error: error)
        alert.messageText = "Could not save settings"
        alert.runModal()
    }

    private func downloadLocalModel() {
        guard !isDownloadingModel, !isModelDownloaded else { return }
        isDownloadingModel = true
        modelDownloadProgress = 0
        modelDownloadSizeBytes = selectedLocalModelFallbackDownloadSizeBytes
        modelDownloadError = nil

        Task {
            let modeToDownload = parakeetMode
            Task {
                await updateDownloadSize(for: modeToDownload)
            }

            do {
                switch modeToDownload {
                case .standard:
                    try await LocalParakeetModelStore.download { progress in
                        Task { @MainActor in
                            modelDownloadProgress = max(modelDownloadProgress, progress)
                        }
                    }
                case .streaming:
                    try await LocalParakeetStreamingModelStore.download { progress in
                        Task { @MainActor in
                            modelDownloadProgress = max(modelDownloadProgress, progress)
                        }
                    }
                }
                await MainActor.run {
                    isModelDownloaded = selectedLocalModelDownloaded
                    isDownloadingModel = false
                    modelDownloadProgress = 1
                }
            } catch {
                Logger.shared.error("Local model download failed: \(error.localizedDescription)")
                await MainActor.run {
                    isModelDownloaded = selectedLocalModelDownloaded
                    isDownloadingModel = false
                    modelDownloadError = error.localizedDescription
                }
            }
        }
    }

    private func removeLocalModel() {
        do {
            switch parakeetMode {
            case .standard:
                try LocalParakeetModelStore.remove()
                Task {
                    await LocalParakeetTranscriptionClient.shared.unload()
                }
            case .streaming:
                try LocalParakeetStreamingModelStore.remove()
                Task {
                    await LocalParakeetStreamingTranscriptionClient.shared.unload()
                }
            }
            isModelDownloaded = selectedLocalModelDownloaded
            modelDownloadProgress = 0
            modelDownloadError = nil
        } catch {
            Logger.shared.error("Local model removal failed: \(error.localizedDescription)")
            modelDownloadError = error.localizedDescription
        }
    }

    private func updateDownloadSize(for modeToDownload: LocalParakeetTranscriptionMode) async {
        let sizeBytes: Int64?
        switch modeToDownload {
        case .standard:
            sizeBytes = try? await LocalParakeetModelStore.downloadSizeBytes()
        case .streaming:
            sizeBytes = try? await LocalParakeetStreamingModelStore.downloadSizeBytes()
        }

        guard let sizeBytes else { return }

        await MainActor.run {
            guard parakeetMode == modeToDownload else { return }
            modelDownloadSizeBytes = sizeBytes
        }
    }
}

private struct DownloadProgressRing: View {
    let progress: Double

    private let lineWidth = 1.5
    private let size = 14.0

    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    Color.secondary.opacity(0.25),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )

            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(
                    Color.accentColor,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }
}
