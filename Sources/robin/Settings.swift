import Foundation

struct AppSettings: Sendable {
    var apiKey: String
    var endpoint: String
    var model: String
    var language: String
    var hotkey: String
    var deliveryMode: TranscriptDeliveryMode
    var historyDirectory: String
    var recordingDirectory: String

    var resolvedHistoryDirectory: URL {
        URL(fileURLWithPath: historyDirectory.expandingTildeInPath, isDirectory: true)
    }

    var resolvedRecordingDirectory: URL {
        URL(fileURLWithPath: recordingDirectory.expandingTildeInPath, isDirectory: true)
    }

    static let defaultConfig = AppSettings(
        apiKey: "",
        endpoint: "https://api.cohere.com/v2/audio/transcriptions",
        model: "cohere-transcribe-03-2026",
        language: "en",
        hotkey: "control+]",
        deliveryMode: .insert,
        historyDirectory: "~/Library/Application Support/Robin/History",
        recordingDirectory: "~/Library/Caches/Robin/Recordings"
    )
}

enum TranscriptDeliveryMode: String, Sendable {
    case insert
    case clipboard
}

final class SettingsManager {
    private let fileManager = FileManager.default

    let supportDirectory: URL
    let configURL: URL

    init() {
        let home = fileManager.homeDirectoryForCurrentUser
        supportDirectory = home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Robin", isDirectory: true)
        configURL = supportDirectory.appendingPathComponent("config.toml", isDirectory: false)
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
        if !fileManager.fileExists(atPath: configURL.path) {
            try ensureApplicationDirectories()
            try defaultTOML.write(to: configURL, atomically: true, encoding: .utf8)
            Logger.shared.info("Created default config: \(configURL.path)")
        }

        var contents = try String(contentsOf: configURL, encoding: .utf8)
        contents = try migrateConfigIfNeeded(contents)
        var values = parseFlatTOML(contents)
        let defaults = AppSettings.defaultConfig
        let configuredDeliveryMode = values.removeValue(forKey: "delivery_mode") ?? defaults.deliveryMode.rawValue

        let settings = AppSettings(
            apiKey: values.removeValue(forKey: "api_key") ?? defaults.apiKey,
            endpoint: values.removeValue(forKey: "endpoint") ?? defaults.endpoint,
            model: values.removeValue(forKey: "model") ?? defaults.model,
            language: values.removeValue(forKey: "language") ?? defaults.language,
            hotkey: values.removeValue(forKey: "hotkey") ?? defaults.hotkey,
            deliveryMode: TranscriptDeliveryMode(rawValue: configuredDeliveryMode.lowercased()) ?? defaults.deliveryMode,
            historyDirectory: values.removeValue(forKey: "history_directory") ?? defaults.historyDirectory,
            recordingDirectory: values.removeValue(forKey: "recording_directory") ?? defaults.recordingDirectory
        )

        try rewriteConfigWithCommentsIfNeeded(contents: contents, settings: settings)
        try fileManager.createDirectory(at: settings.resolvedHistoryDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: settings.resolvedRecordingDirectory, withIntermediateDirectories: true)
        return settings
    }

    func resetToDefaults() throws -> AppSettings {
        try ensureApplicationDirectories()
        try defaultTOML.write(to: configURL, atomically: true, encoding: .utf8)
        return try loadOrCreate()
    }

    private var defaultTOML: String {
        renderTOML(AppSettings.defaultConfig)
    }

    private func migrateConfigIfNeeded(_ contents: String) throws -> String {
        let values = parseFlatTOML(contents)
        guard values["delivery_mode"] == nil else { return contents }

        let separator = contents.hasSuffix("\n") ? "" : "\n"
        let migrated = contents + separator + "\ndelivery_mode = \"insert\" # \"insert\" or \"clipboard\"\n"
        try migrated.write(to: configURL, atomically: true, encoding: .utf8)
        Logger.shared.info("Migrated config with delivery_mode")
        return migrated
    }

    private func rewriteConfigWithCommentsIfNeeded(contents: String, settings: AppSettings) throws {
        let requiredCommentMarkers = [
            "# Your Cohere API key.",
            "# The transcription HTTP endpoint.",
            "# The Cohere transcription model.",
            "# The input audio language.",
            "# The push-to-talk hotkey.",
            "# What Robin does with the completed transcript.",
            "# Where Robin saves completed transcripts.",
            "# Where Robin stores temporary recordings."
        ]

        guard requiredCommentMarkers.contains(where: { !contents.contains($0) }) else {
            return
        }

        try renderTOML(settings).write(to: configURL, atomically: true, encoding: .utf8)
        Logger.shared.info("Rewrote config with explanatory comments")
    }

    private func renderTOML(_ settings: AppSettings) -> String {
        """
        # Robin configuration
        # Settings UI is intentionally omitted. Edit this file and restart Robin after changing values.

        # Your Cohere API key.
        # Options: set this to your Cohere key string, or leave it empty to disable transcription.
        api_key = "\(escaped(settings.apiKey))"

        # The transcription HTTP endpoint.
        # Options: use Cohere's default endpoint, or another compatible multipart transcription endpoint.
        endpoint = "\(escaped(settings.endpoint))"

        # The Cohere transcription model.
        # Options: use "cohere-transcribe-03-2026" unless Cohere documents a newer compatible model.
        model = "\(escaped(settings.model))"

        # The input audio language.
        # Options: ISO-639-1 language codes supported by Cohere Transcribe, such as "en", "de", "fr", "es", "pl", or "ja".
        language = "\(escaped(settings.language))"

        # The push-to-talk hotkey.
        # Options: modifier+key combinations such as "control+]", "command+shift+space", or "option+f12".
        hotkey = "\(escaped(settings.hotkey))"

        # What Robin does with the completed transcript.
        # Options: "insert" writes into the focused text field; "clipboard" copies the text to the clipboard.
        delivery_mode = "\(settings.deliveryMode.rawValue)"

        # Where Robin saves completed transcripts.
        # Options: any writable folder path. "~" expands to your home directory.
        history_directory = "\(escaped(settings.historyDirectory))"

        # Where Robin stores temporary recordings before transcription.
        # Options: any writable folder path. "~" expands to your home directory.
        recording_directory = "\(escaped(settings.recordingDirectory))"
        """
    }

    private func escaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func parseFlatTOML(_ source: String) -> [String: String] {
        var result: [String: String] = [:]

        for rawLine in source.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            guard let equals = line.firstIndex(of: "=") else { continue }

            let key = line[..<equals].trimmingCharacters(in: .whitespacesAndNewlines)
            let valuePart = line[line.index(after: equals)...].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            result[key] = unquote(valuePart)
        }

        return result
    }

    private func unquote(_ value: String) -> String {
        var cleaned = value
        if let hashIndex = cleaned.firstIndex(of: "#") {
            cleaned = String(cleaned[..<hashIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if cleaned.hasPrefix("\""), cleaned.hasSuffix("\""), cleaned.count >= 2 {
            let start = cleaned.index(after: cleaned.startIndex)
            let end = cleaned.index(before: cleaned.endIndex)
            return String(cleaned[start..<end])
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")
        }

        return cleaned
    }
}

extension String {
    var expandingTildeInPath: String {
        NSString(string: self).expandingTildeInPath
    }
}
