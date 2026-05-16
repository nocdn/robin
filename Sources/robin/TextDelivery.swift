import AppKit
import CoreGraphics
import Foundation

struct TextDelivery {
    private let pasteDelayMicroseconds: useconds_t = 60_000
    private let pasteReleaseDelayMicroseconds: useconds_t = 100_000
    private let clipboardRestoreDelayMicroseconds: useconds_t = 50_000
    private let commandKeyCode: CGKeyCode = 0x37
    private let vKeyCode: CGKeyCode = 0x09

    func deliver(_ text: String, mode: TranscriptDeliveryMode, alwaysCopyTranscription: Bool = false) throws {
        Logger.shared.info("Delivering text mode=\(mode.rawValue) characters=\(text.count)")
        switch mode {
        case .insert:
            try pasteViaClipboard(text)
            if alwaysCopyTranscription {
                copyTranscriptionToClipboard(text)
            }
        case .clipboard:
            copyTranscriptionToClipboard(text)
        }
    }

    func insertLiveChunk(_ text: String) throws {
        Logger.shared.info("Delivering live text chunk characters=\(text.count)")
        try pasteViaClipboard(text)
    }

    private func pasteViaClipboard(_ text: String) throws {
        guard !text.isEmpty else { return }

        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)

        try writeClipboardText(text)
        usleep(pasteDelayMicroseconds)
        try sendPasteCommand()
        usleep(clipboardRestoreDelayMicroseconds)
        snapshot.restore(to: pasteboard)

        Logger.shared.info("Inserted text with Handy-style clipboard paste")
    }

    private func writeClipboardText(_ text: String) throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        guard pasteboard.setString(text, forType: .string) else {
            throw RobinError.textInsertionFailed("Failed to write transcript to clipboard.")
        }
    }

    private func sendPasteCommand() throws {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw RobinError.textInsertionFailed("Could not create keyboard event source.")
        }
        source.localEventsSuppressionInterval = 0

        guard let commandDown = CGEvent(keyboardEventSource: source, virtualKey: commandKeyCode, keyDown: true),
              let vDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let vUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false),
              let commandUp = CGEvent(keyboardEventSource: source, virtualKey: commandKeyCode, keyDown: false)
        else {
            throw RobinError.textInsertionFailed("Could not create paste keyboard events.")
        }

        commandDown.flags = .maskCommand
        vDown.flags = .maskCommand
        vUp.flags = .maskCommand

        commandDown.post(tap: .cghidEventTap)
        vDown.post(tap: .cghidEventTap)
        vUp.post(tap: .cghidEventTap)
        usleep(pasteReleaseDelayMicroseconds)
        commandUp.post(tap: .cghidEventTap)
    }

    func copyTranscriptionToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        Logger.shared.info("Copied text to clipboard")
    }
}

private struct PasteboardSnapshot {
    private let items: [PasteboardItemSnapshot]

    static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let snapshots = pasteboard.pasteboardItems?.map(PasteboardItemSnapshot.capture) ?? []
        return PasteboardSnapshot(items: snapshots)
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }

        let restoredItems = items.map { snapshot in
            let item = NSPasteboardItem()
            snapshot.values.forEach { value in
                item.setData(value.data, forType: value.type)
            }
            return item
        }

        if !pasteboard.writeObjects(restoredItems) {
            Logger.shared.error("Failed to restore previous clipboard contents after paste")
        }
    }
}

private struct PasteboardItemSnapshot {
    let values: [(type: NSPasteboard.PasteboardType, data: Data)]

    static func capture(_ item: NSPasteboardItem) -> PasteboardItemSnapshot {
        let values = item.types.compactMap { type -> (type: NSPasteboard.PasteboardType, data: Data)? in
            guard let data = item.data(forType: type) else { return nil }
            return (type, data)
        }
        return PasteboardItemSnapshot(values: values)
    }
}
