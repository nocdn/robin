import FluidAudio
import Foundation

enum LocalParakeetModelStore {
    static let modelName = "Parakeet TDT v3"
    static let modelVersion: AsrModelVersion = .v3
    static let encoderPrecision: ParakeetEncoderPrecision = .int8

    static var modelDirectory: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Robin", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("parakeet-tdt-0.6b-v3", isDirectory: true)
    }

    static var isDownloaded: Bool {
        AsrModels.modelsExist(
            at: modelDirectory,
            version: modelVersion,
            encoderPrecision: encoderPrecision
        )
    }

    static func download(progress: @escaping @Sendable (Double) -> Void) async throws {
        progress(0)
        _ = try await AsrModels.download(
            to: modelDirectory,
            version: modelVersion,
            encoderPrecision: encoderPrecision,
            progressHandler: { snapshot in
                progress(snapshot.fractionCompleted)
            }
        )
        progress(1)
    }

    static func remove() throws {
        if FileManager.default.fileExists(atPath: modelDirectory.path) {
            try FileManager.default.removeItem(at: modelDirectory)
        }
    }
}

enum LocalParakeetStreamingModelStore {
    static let modelName = "Parakeet Realtime EOU"
    static let chunkSize: StreamingChunkSize = .ms320

    static var modelsRootDirectory: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Robin", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("parakeet-realtime-eou-120m-coreml", isDirectory: true)
    }

    static var modelDirectory: URL {
        modelsRootDirectory
            .appendingPathComponent(Repo.parakeetEou320.folderName, isDirectory: true)
    }

    static var isDownloaded: Bool {
        ModelNames.ParakeetEOU.requiredModels.allSatisfy { modelName in
            FileManager.default.fileExists(
                atPath: modelDirectory.appendingPathComponent(modelName).path
            )
        }
    }

    static func download(progress: @escaping @Sendable (Double) -> Void) async throws {
        progress(0)
        try await DownloadUtils.downloadRepo(
            .parakeetEou320,
            to: modelsRootDirectory,
            progressHandler: { snapshot in
                progress(snapshot.fractionCompleted)
            }
        )
        progress(1)
    }

    static func remove() throws {
        if FileManager.default.fileExists(atPath: modelsRootDirectory.path) {
            try FileManager.default.removeItem(at: modelsRootDirectory)
        }
    }
}
