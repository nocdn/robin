import Foundation

struct AppSettings: Sendable {
    var transcriptionBackend: TranscriptionBackend
    var localParakeetMode: LocalParakeetTranscriptionMode
    var apiKey: String
    var endpoint: String
    var model: String
    var language: String
    var hotkey: String
    var deliveryMode: TranscriptDeliveryMode
    var alwaysCopyTranscription: Bool
    var startAtLogin: Bool
    var clickBeforeInserting: Bool
    var historyDirectory: String
    var recordingDirectory: String

    var resolvedHistoryDirectory: URL {
        URL(fileURLWithPath: historyDirectory.expandingTildeInPath, isDirectory: true)
    }

    var resolvedRecordingDirectory: URL {
        URL(fileURLWithPath: recordingDirectory.expandingTildeInPath, isDirectory: true)
    }

    static let defaultConfig = AppSettings(
        transcriptionBackend: .cohere,
        localParakeetMode: .standard,
        apiKey: "",
        endpoint: "https://api.cohere.com/v2/audio/transcriptions",
        model: "cohere-transcribe-03-2026",
        language: "en",
        hotkey: HotKeyParser.defaultValue,
        deliveryMode: .insert,
        alwaysCopyTranscription: false,
        startAtLogin: true,
        clickBeforeInserting: false,
        historyDirectory: "~/Library/Application Support/Robin/History",
        recordingDirectory: "~/Library/Caches/Robin/Recordings"
    )
}

enum TranscriptDeliveryMode: String, Sendable {
    case insert
    case clipboard
}

enum TranscriptionBackend: String, Sendable {
    case cohere
    case localParakeet
}

enum LocalParakeetTranscriptionMode: String, CaseIterable, Identifiable, Sendable {
    case standard
    case streaming

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard:
            "Standard"
        case .streaming:
            "Streaming"
        }
    }
}

final class SettingsManager {
    private enum Keys {
        static let transcriptionBackend = "transcriptionBackend"
        static let localParakeetMode = "localParakeetMode"
        static let apiKey = "apiKey"
        static let model = "model"
        static let language = "language"
        static let deliveryMode = "deliveryMode"
        static let alwaysCopyTranscription = "alwaysCopyTranscription"
        static let startAtLogin = "startAtLogin"
        static let clickBeforeInserting = "clickBeforeInserting"
        static let hotkey = "hotkey"
        static let historyDirectory = "historyDirectory"
    }

    private let fileManager = FileManager.default
    private let userDefaults: UserDefaults

    let supportDirectory: URL
    private let legacyConfigURL: URL

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        let home = fileManager.homeDirectoryForCurrentUser
        supportDirectory = home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Robin", isDirectory: true)
        legacyConfigURL = supportDirectory.appendingPathComponent("config.toml", isDirectory: false)
    }

    func ensureApplicationDirectories() throws {
        try fileManager.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        Logger.shared.info("Ensured support directory: \(supportDirectory.path)")
        try fileManager.createDirectory(
            at: AppSettings.defaultConfig.resolvedHistoryDirectory,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: AppSettings.defaultConfig.resolvedRecordingDirectory,
            withIntermediateDirectories: true
        )
    }

    func loadOrCreate() throws -> AppSettings {
        try ensureApplicationDirectories()
        try removeLegacyConfigIfNeeded()

        let defaults = AppSettings.defaultConfig
        let configuredDeliveryMode = userDefaults.string(forKey: Keys.deliveryMode) ?? defaults.deliveryMode.rawValue
        let configuredBackend = userDefaults.string(forKey: Keys.transcriptionBackend) ?? defaults.transcriptionBackend.rawValue
        let configuredParakeetMode = userDefaults.string(forKey: Keys.localParakeetMode) ?? defaults.localParakeetMode.rawValue
        let settings = AppSettings(
            transcriptionBackend: TranscriptionBackend(rawValue: configuredBackend) ?? defaults.transcriptionBackend,
            localParakeetMode: LocalParakeetTranscriptionMode(rawValue: configuredParakeetMode) ?? defaults.localParakeetMode,
            apiKey: userDefaults.string(forKey: Keys.apiKey) ?? defaults.apiKey,
            endpoint: defaults.endpoint,
            model: userDefaults.string(forKey: Keys.model) ?? defaults.model,
            language: userDefaults.string(forKey: Keys.language) ?? defaults.language,
            hotkey: userDefaults.string(forKey: Keys.hotkey) ?? defaults.hotkey,
            deliveryMode: TranscriptDeliveryMode(rawValue: configuredDeliveryMode.lowercased()) ?? defaults.deliveryMode,
            alwaysCopyTranscription: userDefaults.object(forKey: Keys.alwaysCopyTranscription) as? Bool ?? defaults.alwaysCopyTranscription,
            startAtLogin: userDefaults.object(forKey: Keys.startAtLogin) as? Bool ?? defaults.startAtLogin,
            clickBeforeInserting: userDefaults.object(forKey: Keys.clickBeforeInserting) as? Bool ?? defaults.clickBeforeInserting,
            historyDirectory: userDefaults.string(forKey: Keys.historyDirectory) ?? defaults.historyDirectory,
            recordingDirectory: defaults.recordingDirectory
        )

        try fileManager.createDirectory(at: settings.resolvedHistoryDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: settings.resolvedRecordingDirectory, withIntermediateDirectories: true)
        return settings
    }

    func resetToDefaults() throws -> AppSettings {
        try ensureApplicationDirectories()
        userDefaults.removeObject(forKey: Keys.transcriptionBackend)
        userDefaults.removeObject(forKey: Keys.localParakeetMode)
        userDefaults.removeObject(forKey: Keys.apiKey)
        userDefaults.removeObject(forKey: Keys.model)
        userDefaults.removeObject(forKey: Keys.language)
        userDefaults.removeObject(forKey: Keys.deliveryMode)
        userDefaults.removeObject(forKey: Keys.alwaysCopyTranscription)
        userDefaults.removeObject(forKey: Keys.startAtLogin)
        userDefaults.removeObject(forKey: Keys.clickBeforeInserting)
        userDefaults.removeObject(forKey: Keys.hotkey)
        userDefaults.removeObject(forKey: Keys.historyDirectory)
        try removeLegacyConfigIfNeeded()
        Logger.shared.info("Reset settings to defaults")
        return try loadOrCreate()
    }

    func save(_ settings: AppSettings) throws {
        try ensureApplicationDirectories()
        userDefaults.set(settings.transcriptionBackend.rawValue, forKey: Keys.transcriptionBackend)
        userDefaults.set(settings.localParakeetMode.rawValue, forKey: Keys.localParakeetMode)
        userDefaults.set(settings.apiKey, forKey: Keys.apiKey)
        userDefaults.set(settings.model, forKey: Keys.model)
        userDefaults.set(settings.language, forKey: Keys.language)
        userDefaults.set(settings.deliveryMode.rawValue, forKey: Keys.deliveryMode)
        userDefaults.set(settings.alwaysCopyTranscription, forKey: Keys.alwaysCopyTranscription)
        userDefaults.set(settings.startAtLogin, forKey: Keys.startAtLogin)
        userDefaults.set(settings.clickBeforeInserting, forKey: Keys.clickBeforeInserting)
        userDefaults.set(settings.hotkey, forKey: Keys.hotkey)
        userDefaults.set(settings.historyDirectory, forKey: Keys.historyDirectory)
        try fileManager.createDirectory(at: settings.resolvedHistoryDirectory, withIntermediateDirectories: true)
        Logger.shared.info("Saved settings")
    }

    func update(_ transform: (inout AppSettings) -> Void) throws -> AppSettings {
        var settings = try loadOrCreate()
        transform(&settings)
        try save(settings)
        return settings
    }

    private func removeLegacyConfigIfNeeded() throws {
        guard fileManager.fileExists(atPath: legacyConfigURL.path) else { return }
        try fileManager.removeItem(at: legacyConfigURL)
        Logger.shared.info("Removed legacy config file")
    }
}

extension String {
    var expandingTildeInPath: String {
        NSString(string: self).expandingTildeInPath
    }
}
