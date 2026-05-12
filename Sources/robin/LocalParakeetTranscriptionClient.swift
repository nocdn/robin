import FluidAudio
import Foundation

actor LocalParakeetTranscriptionClient {
    static let shared = LocalParakeetTranscriptionClient()

    private var manager: AsrManager?
    private var loadedModelDirectory: URL?

    func transcribe(audioURL: URL, settings: AppSettings) async throws -> String {
        let manager = try await loadManagerIfNeeded()
        var decoderState = try TdtDecoderState()
        let language = Language(rawValue: settings.language.lowercased())
        let result = try await manager.transcribe(audioURL, decoderState: &decoderState, language: language)
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func unload() {
        manager = nil
        loadedModelDirectory = nil
    }

    private func loadManagerIfNeeded() async throws -> AsrManager {
        let modelDirectory = LocalParakeetModelStore.modelDirectory
        if let manager, loadedModelDirectory == modelDirectory {
            return manager
        }

        guard LocalParakeetModelStore.isDownloaded else {
            throw RobinError.localModelNotDownloaded(modelDirectory)
        }

        Logger.shared.info("Loading local Parakeet model from \(modelDirectory.path)")
        let models = try await AsrModels.load(
            from: modelDirectory,
            version: LocalParakeetModelStore.modelVersion,
            encoderPrecision: LocalParakeetModelStore.encoderPrecision
        )
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        self.manager = manager
        loadedModelDirectory = modelDirectory
        Logger.shared.info("Local Parakeet model loaded")
        return manager
    }
}
