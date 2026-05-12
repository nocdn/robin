import Foundation

struct TranscriptStore {
    let settings: AppSettings

    func save(_ text: String) throws -> URL {
        Logger.shared.info("Saving transcript to \(settings.resolvedHistoryDirectory.path)")
        try FileManager.default.createDirectory(
            at: settings.resolvedHistoryDirectory,
            withIntermediateDirectories: true
        )

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "dd-MM-yyyy-HH-mm"

        let baseName = "transcript-\(formatter.string(from: Date()))"
        var url = settings.resolvedHistoryDirectory.appendingPathComponent("\(baseName).txt")

        var suffix = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = settings.resolvedHistoryDirectory.appendingPathComponent("\(baseName)-\(suffix).txt")
            suffix += 1
        }

        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
