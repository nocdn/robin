import ApplicationServices
import AppKit
import Foundation

struct TextDelivery {
    func deliver(_ text: String, mode: TranscriptDeliveryMode) throws {
        Logger.shared.info("Delivering text mode=\(mode.rawValue) characters=\(text.count)")
        switch mode {
        case .insert:
            do {
                try insert(text)
            } catch {
                Logger.shared.error("Text insertion failed; copying transcript to clipboard instead: \(error.localizedDescription)")
                copyToClipboard(text)
            }
        case .clipboard:
            copyToClipboard(text)
        }
    }

    func insertLiveChunk(_ text: String) throws {
        Logger.shared.info("Delivering live text chunk characters=\(text.count)")
        try insert(text)
    }

    private func insert(_ text: String) throws {
        guard !text.isEmpty else { return }

        try insertWithAccessibility(text)
        Logger.shared.info("Inserted text with Accessibility selected-text replacement")
    }

    private func insertWithAccessibility(_ text: String) throws {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        let focusedError = AXUIElementCopyAttributeValue(
            systemWideElement,
            "AXFocusedUIElement" as CFString,
            &focusedValue
        )

        guard focusedError == .success, let focusedValue else {
            Logger.shared.error("AX focused element unavailable: \(focusedError.rawValue)")
            throw RobinError.textInsertionFailed("No focused text field was available.")
        }

        let focusedElement = focusedValue as! AXUIElement
        let setError = AXUIElementSetAttributeValue(
            focusedElement,
            "AXSelectedText" as CFString,
            text as CFTypeRef
        )

        if setError != .success {
            Logger.shared.error("AX selected text set failed: \(setError.rawValue)")
            throw RobinError.textInsertionFailed("Focused text field rejected insertion.")
        }
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
