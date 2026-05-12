import FluidAudio
import Foundation

enum LocalParakeetModelStore {
    static let modelName = "Parakeet TDT v3"
    static let modelVersion: AsrModelVersion = .v3
    static let encoderPrecision: ParakeetEncoderPrecision = .int8
    static let fallbackDownloadSizeBytes: Int64 = 483_290_756

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

    static func downloadSizeBytes() async throws -> Int64 {
        try await HuggingFaceModelSize.fetch(
            repository: "FluidInference/parakeet-tdt-0.6b-v3-coreml",
            treePath: nil,
            shouldInclude: { path in
                [
                    "Preprocessor.mlmodelc",
                    "Encoder.mlmodelc",
                    "Decoder.mlmodelc",
                    "JointDecisionv3.mlmodelc",
                ].contains { path.hasPrefix("\($0)/") }
                    || path.hasSuffix(".json")
                    || path.hasSuffix(".txt")
            }
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
    static let fallbackDownloadSizeBytes: Int64 = 447_774_022

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

    static func downloadSizeBytes() async throws -> Int64 {
        let subPath = chunkSize.modelSubdirectory

        return try await HuggingFaceModelSize.fetch(
            repository: "FluidInference/parakeet-realtime-eou-120m-coreml",
            treePath: subPath,
            shouldInclude: { path in
                guard path.hasPrefix("\(subPath)/") else { return false }

                return [
                    "\(subPath)/streaming_encoder.mlmodelc",
                    "\(subPath)/decoder.mlmodelc",
                    "\(subPath)/joint_decision.mlmodelc",
                ].contains { path.hasPrefix("\($0)/") }
                    || path.hasSuffix(".json")
                    || path.hasSuffix(".model")
                    || path.hasSuffix(".bin")
            }
        )
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

private enum HuggingFaceModelSize {
    private struct TreeItem: Decodable {
        let type: String
        let path: String
        let size: Int64?
    }

    static func fetch(
        repository: String,
        treePath: String?,
        shouldInclude: (String) -> Bool
    ) async throws -> Int64 {
        var endpoint = "https://huggingface.co/api/models/\(repository)/tree/main"
        if let treePath {
            endpoint += "/\(treePath)"
        }
        endpoint += "?recursive=true"

        guard let url = URL(string: endpoint) else {
            throw URLError(.badURL)
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard
            let httpResponse = response as? HTTPURLResponse,
            (200..<300).contains(httpResponse.statusCode)
        else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder()
            .decode([TreeItem].self, from: data)
            .filter { $0.type == "file" && shouldInclude($0.path) }
            .reduce(Int64(0)) { $0 + max(0, $1.size ?? 0) }
    }
}
