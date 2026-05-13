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
                Logger.shared.error("Text insertion failed; pasting transcript via clipboard instead: \(error.localizedDescription)")
                do {
                    try pasteWithClipboard(text)
                } catch {
                    Logger.shared.error("Clipboard paste failed; leaving transcript on clipboard instead: \(error.localizedDescription)")
                    copyToClipboard(text)
                }
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

    private func pasteWithClipboard(_ text: String) throws {
        guard !text.isEmpty else { return }

        let pasteboard = NSPasteboard.general
        let previousClipboard = ClipboardSnapshot.capture(from: pasteboard)
        copyToClipboard(text)
        let transcriptChangeCount = pasteboard.changeCount

        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        else {
            throw RobinError.textInsertionFailed("Could not create paste key events.")
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        Logger.shared.info("Pasted transcript via clipboard")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard pasteboard.changeCount == transcriptChangeCount else {
                Logger.shared.info("Skipping clipboard restore because pasteboard changed")
                return
            }

            previousClipboard.restore(to: pasteboard)
            Logger.shared.info("Restored clipboard after paste fallback")
        }
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        Logger.shared.info("Copied text to clipboard")
    }

    private struct ClipboardSnapshot {
        let items: [Item]

        static func capture(from pasteboard: NSPasteboard) -> ClipboardSnapshot {
            let items = (pasteboard.pasteboardItems ?? []).map { item in
                Item(
                    types: item.types.compactMap { type in
                        item.data(forType: type).map { (type, $0) }
                    }
                )
            }
            return ClipboardSnapshot(items: items)
        }

        func restore(to pasteboard: NSPasteboard) {
            pasteboard.clearContents()
            guard !items.isEmpty else { return }

            let restoredItems = items.map { item in
                let pasteboardItem = NSPasteboardItem()
                for (type, data) in item.types {
                    pasteboardItem.setData(data, forType: type)
                }
                return pasteboardItem
            }
            pasteboard.writeObjects(restoredItems)
        }

        struct Item {
            let types: [(NSPasteboard.PasteboardType, Data)]
        }
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
