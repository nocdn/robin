import ApplicationServices
import AppKit
import Foundation

struct TextDelivery {
    func deliver(_ text: String, mode: TranscriptDeliveryMode, target: AXUIElement? = nil) throws {
        Logger.shared.info("Delivering text mode=\(mode.rawValue) characters=\(text.count)")
        switch mode {
        case .insert:
            do {
                try insertFinalTranscript(text, target: target)
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
        try insertWithAccessibility(text, target: target)
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

    private func insertFinalTranscript(_ text: String, target: AXUIElement?) throws {
        do {
            try insertWithAccessibility(text, target: target)
        } catch {
            Logger.shared.error("Accessibility insertion failed; simulating Unicode typing instead: \(error.localizedDescription)")
            try typeWithKeyboardEvents(text, target: target)
        }
    }

    private func insertWithAccessibility(_ text: String, target: AXUIElement?) throws {
        guard !text.isEmpty else { return }

        let targets = accessibilityTargets(preferred: target)
        guard !targets.isEmpty else {
            throw RobinError.textInsertionFailed("No focused text field was available.")
        }

        var lastError: Error?
        for target in targets {
            do {
                try insertWithSelectedTextAttribute(text, target: target)
                Logger.shared.info("Inserted text with captured Accessibility element")
                return
            } catch {
                Logger.shared.error("AXSelectedText insertion failed: \(error.localizedDescription)")
                lastError = error
            }
        }

        for target in targets {
            do {
                try insertWithValueAndSelectedRange(text, target: target)
                Logger.shared.info("Inserted text with AXValue selected-range replacement")
                return
            } catch {
                Logger.shared.error("AXValue selected-range insertion failed: \(error.localizedDescription)")
                lastError = error
            }
        }

        throw lastError ?? RobinError.textInsertionFailed("Focused text field rejected insertion.")
    }

    private func insertWithSelectedTextAttribute(_ text: String, target focusedElement: AXUIElement) throws {
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

    private func insertWithValueAndSelectedRange(_ text: String, target focusedElement: AXUIElement) throws {
        guard isAttributeSettable("AXValue", on: focusedElement) else {
            throw RobinError.textInsertionFailed("Focused text field does not allow AXValue updates.")
        }

        var valueRef: CFTypeRef?
        let valueError = AXUIElementCopyAttributeValue(
            focusedElement,
            "AXValue" as CFString,
            &valueRef
        )
        guard valueError == .success, let currentText = valueRef as? String else {
            Logger.shared.error("AX value read failed: \(valueError.rawValue)")
            throw RobinError.textInsertionFailed("Focused text field did not expose text value.")
        }

        let selectedRange = try selectedTextRange(in: focusedElement)
        var updatedText = currentText
        try updatedText.replaceUTF16Range(selectedRange, with: text)

        let setValueError = AXUIElementSetAttributeValue(
            focusedElement,
            "AXValue" as CFString,
            updatedText as CFTypeRef
        )
        guard setValueError == .success else {
            Logger.shared.error("AX value set failed: \(setValueError.rawValue)")
            throw RobinError.textInsertionFailed("Focused text field rejected value replacement.")
        }

        let insertedLength = text.utf16.count
        var cursorRange = CFRange(location: selectedRange.location + insertedLength, length: 0)
        guard let cursorValue = AXValueCreate(.cfRange, &cursorRange) else {
            Logger.shared.error("Could not create AX cursor range after value insertion")
            return
        }

        let setRangeError = AXUIElementSetAttributeValue(
            focusedElement,
            "AXSelectedTextRange" as CFString,
            cursorValue
        )
        if setRangeError != .success {
            Logger.shared.error("AX selected range update failed after value insertion: \(setRangeError.rawValue)")
        }
    }

    private func selectedTextRange(in element: AXUIElement) throws -> CFRange {
        var rangeRef: CFTypeRef?
        let rangeError = AXUIElementCopyAttributeValue(
            element,
            "AXSelectedTextRange" as CFString,
            &rangeRef
        )
        guard rangeError == .success,
              let rangeRef,
              CFGetTypeID(rangeRef) == AXValueGetTypeID()
        else {
            Logger.shared.error("AX selected range read failed: \(rangeError.rawValue)")
            throw RobinError.textInsertionFailed("Focused text field did not expose selected text range.")
        }
        let axRange = rangeRef as! AXValue

        var range = CFRange()
        guard AXValueGetType(axRange) == .cfRange,
              AXValueGetValue(axRange, .cfRange, &range)
        else {
            throw RobinError.textInsertionFailed("Focused text field returned an invalid selected text range.")
        }

        return range
    }

    private func typeWithKeyboardEvents(_ text: String, target: AXUIElement?) throws {
        guard !text.isEmpty else { return }

        prepareTargetForTyping(target)

        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw RobinError.textInsertionFailed("Could not create keyboard event source.")
        }
        source.localEventsSuppressionInterval = 0

        for chunk in text.utf16.chunked(maxLength: 20) {
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            else {
                throw RobinError.textInsertionFailed("Could not create simulated typing events.")
            }

            chunk.withUnsafeBufferPointer { buffer in
                keyDown.keyboardSetUnicodeString(
                    stringLength: buffer.count,
                    unicodeString: buffer.baseAddress
                )
            }
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
            usleep(1_000)
        }

        Logger.shared.info("Inserted text with simulated Unicode keyboard events")
    }

    private func prepareTargetForTyping(_ target: AXUIElement?) {
        guard let target else { return }

        var pid: pid_t = 0
        if AXUIElementGetPid(target, &pid) == .success,
           let app = NSRunningApplication(processIdentifier: pid) {
            app.activate(options: [])
        }

        let focusError = AXUIElementSetAttributeValue(
            target,
            "AXFocused" as CFString,
            kCFBooleanTrue
        )
        if focusError != .success {
            Logger.shared.info("Could not focus insertion target before simulated typing: \(focusError.rawValue)")
        }
    }

    private func accessibilityTargets(preferred target: AXUIElement?) -> [AXUIElement] {
        var targets: [AXUIElement] = []
        var seen = Set<CFHashCode>()

        func append(_ element: AXUIElement?) {
            guard let element else { return }
            let hash = CFHash(element)
            guard !seen.contains(hash) else { return }
            seen.insert(hash)
            targets.append(element)
        }

        append(target)
        append(focusedTextElement())
        return targets
    }

    private func isAttributeSettable(_ attribute: String, on element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        let error = AXUIElementIsAttributeSettable(element, attribute as CFString, &settable)
        if error != .success {
            Logger.shared.info("AX settable check failed attribute=\(attribute) error=\(error.rawValue)")
        }
        return error == .success && settable.boolValue
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

private extension String {
    mutating func replaceUTF16Range(_ range: CFRange, with replacement: String) throws {
        guard range.location >= 0, range.length >= 0 else {
            throw RobinError.textInsertionFailed("Focused text field returned an invalid selected text range.")
        }

        guard let lowerUTF16 = utf16.index(utf16.startIndex, offsetBy: range.location, limitedBy: utf16.endIndex),
              let upperUTF16 = utf16.index(lowerUTF16, offsetBy: range.length, limitedBy: utf16.endIndex),
              let lower = String.Index(lowerUTF16, within: self),
              let upper = String.Index(upperUTF16, within: self)
        else {
            throw RobinError.textInsertionFailed("Focused text field selected range did not match its text value.")
        }

        replaceSubrange(lower..<upper, with: replacement)
    }
}
