import Foundation

final class Logger: @unchecked Sendable {
    static let shared = Logger()

    let logURL: URL

    private let queue = DispatchQueue(label: "dev.local.robin.logger")
    private let formatter: ISO8601DateFormatter

    private init() {
        let supportDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Robin", isDirectory: true)

        logURL = supportDirectory.appendingPathComponent("Robin.log", isDirectory: false)
        formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        try? FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        write("Logger initialized at \(logURL.path)")
    }

    func info(_ message: String) {
        write("INFO  \(message)")
    }

    func error(_ message: String) {
        write("ERROR \(message)")
    }

    private func write(_ message: String) {
        let line = "\(formatter.string(from: Date())) \(message)\n"
        queue.async { [logURL] in
            guard let data = line.data(using: .utf8) else { return }

            if FileManager.default.fileExists(atPath: logURL.path) {
                do {
                    let handle = try FileHandle(forWritingTo: logURL)
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                    try handle.close()
                } catch {
                    print("Robin log write failed: \(error.localizedDescription)")
                }
            } else {
                do {
                    try data.write(to: logURL, options: .atomic)
                } catch {
                    print("Robin log create failed: \(error.localizedDescription)")
                }
            }
        }
    }
}
