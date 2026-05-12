import Foundation

enum RobinError: LocalizedError {
    case missingAPIKey
    case invalidEndpoint(String)
    case invalidHotKey(String)
    case hotKeyPermissionDenied
    case microphonePermissionDenied
    case audioRecordingFailed
    case localModelNotDownloaded(URL)
    case localStreamingModelNotDownloaded(URL)
    case localStreamingRequiresEnglish
    case liveAudioCaptureFailed(String)
    case emptyTranscript
    case textInsertionFailed(String)
    case invalidResponse
    case apiError(status: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "Missing Cohere API key. Add it in Robin Settings."
        case .invalidEndpoint(let endpoint):
            "Invalid Cohere endpoint: \(endpoint)"
        case .invalidHotKey(let hotKey):
            "Invalid hotkey: \(hotKey)"
        case .hotKeyPermissionDenied:
            "Could not create the global hotkey monitor. Enable Robin in System Settings > Privacy & Security > Accessibility and Input Monitoring."
        case .microphonePermissionDenied:
            "Microphone permission was denied. Enable Robin in System Settings > Privacy & Security > Microphone."
        case .audioRecordingFailed:
            "Could not start audio recording."
        case .localModelNotDownloaded(let url):
            "Parakeet model is not downloaded. Download it in Robin Settings. Expected path: \(url.path)"
        case .localStreamingModelNotDownloaded(let url):
            "Parakeet streaming model is not downloaded. Select Parakeet Streaming in Robin Settings and download it. Expected path: \(url.path)"
        case .localStreamingRequiresEnglish:
            "Parakeet streaming currently supports English only. Switch language to English or use Standard local mode."
        case .liveAudioCaptureFailed(let reason):
            "Could not start live audio capture: \(reason)"
        case .emptyTranscript:
            "No transcript was produced."
        case .textInsertionFailed(let reason):
            "Could not insert transcription text: \(reason)"
        case .invalidResponse:
            "Cohere returned an invalid response."
        case .apiError(let status, let body):
            "Cohere transcription failed with HTTP \(status): \(body.prefix(500))"
        }
    }
}
