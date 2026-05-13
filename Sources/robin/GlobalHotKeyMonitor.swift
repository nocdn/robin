import ApplicationServices
import Foundation

final class GlobalHotKeyMonitor {
    var onPressed: (() -> Void)?
    var onReleased: (() -> Void)?

    private let hotKey: HotKey
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isPressed = false

    init(hotKey: HotKey) {
        self.hotKey = hotKey
    }

    deinit {
        stop()
    }

    func start() throws {
        let canListenBeforeRequest = CGPreflightListenEventAccess()
        Logger.shared.info("Input Monitoring listen preflight before request: \(canListenBeforeRequest)")
        if !canListenBeforeRequest {
            let granted = CGRequestListenEventAccess()
            Logger.shared.info("Input Monitoring listen request returned: \(granted)")
        }
        let canListenAfterRequest = CGPreflightListenEventAccess()
        Logger.shared.info("Input Monitoring listen preflight after request: \(canListenAfterRequest)")

        let options = [
            "AXTrustedCheckOptionPrompt": true
        ] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        Logger.shared.info("AX trusted status: \(trusted)")

        let mask = (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)
        Logger.shared.info("Creating CGEvent tap with mask=\(mask)")

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: eventCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Logger.shared.error("CGEvent tap creation returned nil")
            throw RobinError.hotKeyPermissionDenied
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
        Logger.shared.info("CGEvent tap enabled")
    }

    func stop() {
        Logger.shared.info("Stopping hotkey monitor")
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        runLoopSource = nil
        eventTap = nil
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            Logger.shared.error("CGEvent tap disabled with type=\(type.rawValue); re-enabling")
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return false
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        guard keyCode == hotKey.keyCode else { return false }
        Logger.shared.info("Observed configured keyCode=\(keyCode) eventType=\(type.rawValue) flags=\(flags.rawValue)")

        switch type {
        case .flagsChanged:
            guard hotKey.isFunctionKey else { return false }
            let functionPressed = flags.contains(.maskSecondaryFn)
            if functionPressed {
                guard !isPressed else {
                    Logger.shared.info("Ignoring flagsChanged because hotkey is already pressed")
                    return true
                }
                guard flags.containsAll(hotKey.modifiers) else {
                    Logger.shared.info("Ignoring flagsChanged because modifiers do not match required=\(hotKey.modifiers.rawValue) actual=\(flags.rawValue)")
                    return false
                }
                isPressed = true
                Logger.shared.info("Hotkey match: pressed")
                onPressed?()
                return true
            } else {
                guard isPressed else {
                    Logger.shared.info("Ignoring flagsChanged because hotkey was not marked pressed")
                    return false
                }
                isPressed = false
                Logger.shared.info("Hotkey match: released")
                onReleased?()
                return true
            }
        case .keyDown:
            let autoRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            guard isPressed || flags.containsAll(hotKey.modifiers) else {
                Logger.shared.info("Ignoring keyDown because modifiers do not match required=\(hotKey.modifiers.rawValue) actual=\(flags.rawValue)")
                return false
            }
            guard !autoRepeat else {
                Logger.shared.info("Ignoring autorepeat keyDown")
                return true
            }
            guard !isPressed else {
                Logger.shared.info("Ignoring keyDown because hotkey is already pressed")
                return true
            }
            isPressed = true
            Logger.shared.info("Hotkey match: pressed")
            onPressed?()
            return true
        case .keyUp:
            guard isPressed else {
                Logger.shared.info("Ignoring keyUp because hotkey was not marked pressed")
                return false
            }
            isPressed = false
            Logger.shared.info("Hotkey match: released")
            onReleased?()
            return true
        default:
            return false
        }
    }
}

private let eventCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let monitor = Unmanaged<GlobalHotKeyMonitor>
        .fromOpaque(userInfo)
        .takeUnretainedValue()
    if monitor.handle(type: type, event: event) {
        return nil
    }
    return Unmanaged.passUnretained(event)
}

private extension CGEventFlags {
    func containsAll(_ required: CGEventFlags) -> Bool {
        if required.contains(.maskControl), !contains(.maskControl) { return false }
        if required.contains(.maskCommand), !contains(.maskCommand) { return false }
        if required.contains(.maskAlternate), !contains(.maskAlternate) { return false }
        if required.contains(.maskShift), !contains(.maskShift) { return false }
        if required.contains(.maskSecondaryFn), !contains(.maskSecondaryFn) { return false }
        return true
    }
}
