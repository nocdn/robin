import ApplicationServices
import AppKit
import Foundation

struct TextDelivery {
    func deliver(_ text: String, mode: TranscriptDeliveryMode) throws {
        Logger.shared.info("Delivering text mode=\(mode.rawValue) characters=\(text.count)")
        switch mode {
        case .insert:
            try insert(text)
        case .clipboard:
            copyToClipboard(text)
        }
    }

    private func insert(_ text: String) throws {
        guard !text.isEmpty else { return }

        if try insertWithAccessibility(text) {
            Logger.shared.info("Inserted text with Accessibility selected-text replacement")
            return
        }

        Logger.shared.info("Accessibility insertion did not succeed; falling back to Unicode keyboard events")
        try insertWithUnicodeKeyboardEvents(text)
    }

    private func insertWithAccessibility(_ text: String) throws -> Bool {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        let focusedError = AXUIElementCopyAttributeValue(
            systemWideElement,
            "AXFocusedUIElement" as CFString,
            &focusedValue
        )

        guard focusedError == .success, let focusedValue else {
            Logger.shared.info("AX focused element unavailable: \(focusedError.rawValue)")
            return false
        }

        let focusedElement = focusedValue as! AXUIElement
        let setError = AXUIElementSetAttributeValue(
            focusedElement,
            "AXSelectedText" as CFString,
            text as CFTypeRef
        )

        if setError != .success {
            Logger.shared.info("AX selected text set failed: \(setError.rawValue)")
        }

        return setError == .success
    }

    private func insertWithUnicodeKeyboardEvents(_ text: String) throws {
        let canPostBeforeRequest = CGPreflightPostEventAccess()
        Logger.shared.info("Post Event preflight before request: \(canPostBeforeRequest)")
        if !canPostBeforeRequest {
            let granted = CGRequestPostEventAccess()
            Logger.shared.info("Post Event request returned: \(granted)")
        }
        let canPostAfterRequest = CGPreflightPostEventAccess()
        Logger.shared.info("Post Event preflight after request: \(canPostAfterRequest)")

        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw RobinError.textInsertionFailed("Could not create a keyboard event source.")
        }

        for chunk in text.utf16.chunked(maxLength: 16) {
            var mutableChunk = Array(chunk)
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                throw RobinError.textInsertionFailed("Could not create keyboard events.")
            }

            keyDown.keyboardSetUnicodeString(stringLength: mutableChunk.count, unicodeString: &mutableChunk)
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.01)
        }
        Logger.shared.info("Inserted text with Unicode keyboard events")
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        Logger.shared.info("Copied text to clipboard")
    }
}

private extension String.UTF16View {
    func chunked(maxLength: Int) -> [[UInt16]] {
        var chunks: [[UInt16]] = []
        var current: [UInt16] = []
        current.reserveCapacity(maxLength)

        for codeUnit in self {
            current.append(codeUnit)
            if current.count == maxLength {
                chunks.append(current)
                current.removeAll(keepingCapacity: true)
            }
        }

        if !current.isEmpty {
            chunks.append(current)
        }

        return chunks
    }
}
