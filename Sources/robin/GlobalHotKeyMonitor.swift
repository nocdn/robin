@preconcurrency import ApplicationServices
@preconcurrency import Foundation

final class GlobalHotKeyMonitor: @unchecked Sendable {
    var onPressed: (() -> Void)?
    var onReleased: (() -> Void)?

    private static let relevantModifierMask: CGEventFlags = [
        .maskControl,
        .maskCommand,
        .maskAlternate,
        .maskShift,
        .maskSecondaryFn
    ]

    private let hotKey: HotKey
    private let stateLock = NSLock()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var eventRunLoop: CFRunLoop?
    private var eventThread: Thread?
    private var isPressed = false
    private var suppressMainKeyUntilKeyUp = false

    init(hotKey: HotKey) {
        self.hotKey = hotKey
    }

    deinit {
        stop()
    }

    func start() throws {
        stop()

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

        let eventMask = (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)
        Logger.shared.info("Creating CGEvent tap with mask=\(eventMask)")

        let tapConfigurations: [(location: CGEventTapLocation, name: String)] = [
            (.cghidEventTap, "cghidEventTap"),
            (.cgSessionEventTap, "cgSessionEventTap")
        ]

        var selectedTap: CFMachPort?
        var selectedLocationName = ""
        for configuration in tapConfigurations {
            if let tap = CGEvent.tapCreate(
                tap: configuration.location,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: CGEventMask(eventMask),
                callback: eventCallback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ) {
                selectedTap = tap
                selectedLocationName = configuration.name
                break
            }
            Logger.shared.error("CGEvent tap creation failed for \(configuration.name)")
        }

        guard let selectedTap else {
            Logger.shared.error("CGEvent tap creation returned nil")
            throw RobinError.hotKeyPermissionDenied
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, selectedTap, 0)
        let tapLocationName = selectedLocationName
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            guard let self else {
                ready.signal()
                return
            }

            let runLoop = CFRunLoopGetCurrent()
            self.stateLock.lock()
            self.eventRunLoop = runLoop
            self.stateLock.unlock()

            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: selectedTap, enable: true)
            Logger.shared.info("CGEvent tap enabled on dedicated thread location=\(tapLocationName)")
            ready.signal()
            CFRunLoopRun()
            CGEvent.tapEnable(tap: selectedTap, enable: false)
            CFRunLoopRemoveSource(runLoop, source, .commonModes)

            self.stateLock.lock()
            if self.eventRunLoop === runLoop {
                self.eventRunLoop = nil
            }
            self.stateLock.unlock()
            Logger.shared.info("CGEvent tap thread stopped")
        }
        thread.name = "dev.local.robin.hotkey-monitor"

        eventTap = selectedTap
        runLoopSource = source
        eventThread = thread
        thread.start()
        ready.wait()
        Logger.shared.info("Hotkey monitor event thread started")
    }

    func stop() {
        Logger.shared.info("Stopping hotkey monitor")

        let shouldRelease = resetPressedState()
        if shouldRelease {
            dispatchReleased(reason: "monitorStopped")
        }

        stateLock.lock()
        let runLoop = eventRunLoop
        let thread = eventThread
        let tap = eventTap
        stateLock.unlock()

        if let runLoop {
            CFRunLoopStop(runLoop)
        } else if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }

        if let thread {
            for _ in 0..<50 {
                if thread.isFinished {
                    break
                }
                usleep(10_000)
            }
        }

        stateLock.lock()
        runLoopSource = nil
        eventTap = nil
        eventThread = nil
        eventRunLoop = nil
        stateLock.unlock()
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            Logger.shared.error("CGEvent tap disabled with type=\(type.rawValue); re-enabling")
            let shouldRelease = resetPressedState()
            if shouldRelease {
                dispatchReleased(reason: "tapDisabled")
            }

            stateLock.lock()
            let tap = eventTap
            stateLock.unlock()
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return false
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        switch type {
        case .flagsChanged:
            return handleFlagsChanged(keyCode: keyCode, flags: flags)
        case .keyDown:
            return handleKeyDown(keyCode: keyCode, flags: flags, event: event)
        case .keyUp:
            return handleKeyUp(keyCode: keyCode)
        default:
            return false
        }
    }

    private func handleKeyDown(keyCode: CGKeyCode, flags: CGEventFlags, event: CGEvent) -> Bool {
        guard keyCode == hotKey.keyCode else { return false }

        let autoRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

        stateLock.lock()
        let shouldSuppress = isPressed || suppressMainKeyUntilKeyUp
        stateLock.unlock()
        if shouldSuppress {
            if autoRepeat {
                Logger.shared.info("Suppressing autorepeat for active hotkey")
            }
            return true
        }

        guard modifiersExactlyMatch(flags) else {
            Logger.shared.info(
                "Ignoring keyDown because modifiers do not exactly match required=\(requiredModifiers.rawValue) actual=\(relevantModifiers(in: flags).rawValue)"
            )
            return false
        }

        guard !autoRepeat else {
            Logger.shared.info("Suppressing autorepeat keyDown for matching hotkey")
            return true
        }

        stateLock.lock()
        isPressed = true
        suppressMainKeyUntilKeyUp = true
        stateLock.unlock()

        Logger.shared.info("Hotkey match: pressed")
        dispatchPressed()
        return true
    }

    private func handleKeyUp(keyCode: CGKeyCode) -> Bool {
        guard keyCode == hotKey.keyCode else { return false }

        stateLock.lock()
        let wasPressed = isPressed
        let shouldSuppress = isPressed || suppressMainKeyUntilKeyUp
        isPressed = false
        suppressMainKeyUntilKeyUp = false
        stateLock.unlock()

        guard shouldSuppress else {
            Logger.shared.info("Ignoring keyUp because hotkey was not active")
            return false
        }

        if wasPressed {
            Logger.shared.info("Hotkey match: released")
            dispatchReleased(reason: "keyUp")
        } else {
            Logger.shared.info("Suppressing trailing keyUp after hotkey release")
        }
        return true
    }

    private func handleFlagsChanged(keyCode: CGKeyCode, flags: CGEventFlags) -> Bool {
        if hotKey.isFunctionKey, keyCode == hotKey.keyCode {
            return handleFunctionKeyFlagsChanged(flags: flags)
        }

        stateLock.lock()
        let wasPressed = isPressed
        let shouldRelease = wasPressed && !modifiersExactlyMatch(flags)
        if shouldRelease {
            isPressed = false
        }
        stateLock.unlock()

        if shouldRelease {
            Logger.shared.info("Hotkey match: released after modifier break")
            dispatchReleased(reason: "modifierBreak")
        }
        return false
    }

    private func handleFunctionKeyFlagsChanged(flags: CGEventFlags) -> Bool {
        let activeModifiers = relevantModifiers(in: flags)
        let requiredWithFunctionKey = requiredModifiers.union(.maskSecondaryFn)
        let functionCombinationPressed = activeModifiers == requiredWithFunctionKey

        stateLock.lock()
        if functionCombinationPressed {
            guard !isPressed else {
                stateLock.unlock()
                Logger.shared.info("Suppressing repeated fn flagsChanged while hotkey is active")
                return true
            }

            isPressed = true
            suppressMainKeyUntilKeyUp = false
            stateLock.unlock()

            Logger.shared.info("Function hotkey match: pressed")
            dispatchPressed()
            return true
        }

        guard isPressed else {
            stateLock.unlock()
            return false
        }

        isPressed = false
        suppressMainKeyUntilKeyUp = false
        stateLock.unlock()

        Logger.shared.info("Function hotkey match: released")
        dispatchReleased(reason: "functionFlagsChanged")
        return true
    }

    private var requiredModifiers: CGEventFlags {
        relevantModifiers(in: hotKey.modifiers)
    }

    private func modifiersExactlyMatch(_ flags: CGEventFlags) -> Bool {
        relevantModifiers(in: flags) == requiredModifiers
    }

    private func relevantModifiers(in flags: CGEventFlags) -> CGEventFlags {
        flags.intersection(Self.relevantModifierMask)
    }

    private func resetPressedState() -> Bool {
        stateLock.lock()
        let shouldRelease = isPressed
        isPressed = false
        suppressMainKeyUntilKeyUp = false
        stateLock.unlock()
        return shouldRelease
    }

    private func dispatchPressed() {
        DispatchQueue.main.async { [weak self] in
            self?.onPressed?()
        }
    }

    private func dispatchReleased(reason: String) {
        Logger.shared.info("Dispatching hotkey release reason=\(reason)")
        DispatchQueue.main.async { [weak self] in
            self?.onReleased?()
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
