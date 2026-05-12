import Foundation

enum RobinError: LocalizedError {
    case missingAPIKey
    case invalidEndpoint(String)
    case invalidHotKey(String)
    case hotKeyPermissionDenied
    case microphonePermissionDenied
    case audioRecordingFailed
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
        case .textInsertionFailed(let reason):
            "Could not insert transcription text: \(reason)"
        case .invalidResponse:
            "Cohere returned an invalid response."
        case .apiError(let status, let body):
            "Cohere transcription failed with HTTP \(status): \(body.prefix(500))"
        }
    }
}
