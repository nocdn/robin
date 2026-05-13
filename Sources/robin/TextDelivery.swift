import ApplicationServices
import AppKit
import Foundation

struct TextDelivery {
    func deliver(_ text: String, mode: TranscriptDeliveryMode, target: AXUIElement? = nil) throws {
        Logger.shared.info("Delivering text mode=\(mode.rawValue) characters=\(text.count)")
        switch mode {
        case .insert:
            do {
                try insert(text, target: target)
            } catch {
                Logger.shared.error("Text insertion failed; copying transcript to clipboard instead: \(error.localizedDescription)")
                copyToClipboard(text)
            }
        case .clipboard:
            copyToClipboard(text)
        }
    }

    func insertLiveChunk(_ text: String, target: AXUIElement? = nil) throws {
        Logger.shared.info("Delivering live text chunk characters=\(text.count)")
        try insert(text, target: target)
    }

    func focusedTextElement() -> AXUIElement? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        let focusedError = AXUIElementCopyAttributeValue(
            systemWideElement,
            "AXFocusedUIElement" as CFString,
            &focusedValue
        )

        guard focusedError == .success, let focusedValue else {
            Logger.shared.info("AX focused element capture unavailable: \(focusedError.rawValue)")
            return nil
        }

        return (focusedValue as! AXUIElement)
    }

    private func insert(_ text: String, target: AXUIElement?) throws {
        guard !text.isEmpty else { return }

        if let target {
            do {
                try insertWithAccessibility(text, target: target)
                Logger.shared.info("Inserted text with captured Accessibility element")
                return
            } catch {
                Logger.shared.error("Captured Accessibility insertion failed: \(error.localizedDescription)")
            }
        }

        guard let focusedElement = focusedTextElement() else {
            throw RobinError.textInsertionFailed("No focused text field was available.")
        }

        try insertWithAccessibility(text, target: focusedElement)
        Logger.shared.info("Inserted text with Accessibility selected-text replacement")
    }

    private func insertWithAccessibility(_ text: String, target focusedElement: AXUIElement) throws {
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
