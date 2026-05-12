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
            (1 << CGEventType.keyUp.rawValue)
        Logger.shared.info("Creating CGEvent tap with mask=\(mask)")

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
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

    fileprivate func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            Logger.shared.error("CGEvent tap disabled with type=\(type.rawValue); re-enabling")
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        guard keyCode == hotKey.keyCode else { return }
        Logger.shared.info("Observed configured keyCode=\(keyCode) eventType=\(type.rawValue) flags=\(flags.rawValue)")

        switch type {
        case .keyDown:
            let autoRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            guard !autoRepeat else {
                Logger.shared.info("Ignoring autorepeat keyDown")
                return
            }
            guard !isPressed else {
                Logger.shared.info("Ignoring keyDown because hotkey is already pressed")
                return
            }
            guard flags.containsAll(hotKey.modifiers) else {
                Logger.shared.info("Ignoring keyDown because modifiers do not match required=\(hotKey.modifiers.rawValue) actual=\(flags.rawValue)")
                return
            }
            isPressed = true
            Logger.shared.info("Hotkey match: pressed")
            onPressed?()
        case .keyUp:
            guard isPressed else {
                Logger.shared.info("Ignoring keyUp because hotkey was not marked pressed")
                return
            }
            isPressed = false
            Logger.shared.info("Hotkey match: released")
            onReleased?()
        default:
            break
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
    monitor.handle(type: type, event: event)
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
