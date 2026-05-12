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
}

private struct SettingsView: View {
    private enum FocusedField: Hashable {
        case historyDirectory
    }

    private let settingsManager: SettingsManager
    private let onHotKeyChange: () -> Void
    private let onLayoutChange: () -> Void

    @State private var mode: TranscriptionMode = .cohere
    @State private var hotkey: String
    @State private var isListeningForHotkey = false
    @State private var hotkeyError: String?
    @State private var eventMonitor: Any?
    @State private var apiKey: String
    @State private var model: String
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

                Picker("", selection: $mode) {
                    ForEach(TranscriptionMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .labelsHidden()
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
            } else {
                Text("Local model not implemented yet")
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

    private func startHotKeyCapture() {
        stopHotKeyCapture()
        hotkeyError = nil
        isListeningForHotkey = true

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
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
        if modifiers.contains(.function) {
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
}
