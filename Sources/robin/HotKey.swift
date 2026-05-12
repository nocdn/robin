import ApplicationServices
import Foundation

struct HotKey {
    let keyCode: CGKeyCode
    let modifiers: CGEventFlags
}

enum HotKeyParser {
    static func parse(_ value: String) throws -> HotKey {
        let pieces = value
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        guard let keyName = pieces.last else {
            throw RobinError.invalidHotKey(value)
        }

        var modifiers: CGEventFlags = []
        for modifier in pieces.dropLast() {
            switch modifier {
            case "control", "ctrl", "^":
                modifiers.insert(.maskControl)
            case "command", "cmd", "⌘":
                modifiers.insert(.maskCommand)
            case "option", "opt", "alt", "⌥":
                modifiers.insert(.maskAlternate)
            case "shift", "⇧":
                modifiers.insert(.maskShift)
            case "fn", "function":
                modifiers.insert(.maskSecondaryFn)
            default:
                throw RobinError.invalidHotKey(value)
            }
        }

        guard let keyCode = keyCodes[keyName] else {
            throw RobinError.invalidHotKey(value)
        }

        return HotKey(keyCode: keyCode, modifiers: modifiers)
    }

    private static let keyCodes: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
        "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
        "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
        "5": 23, "=": 24, "+": 24, "9": 25, "7": 26, "-": 27, "8": 28,
        "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35,
        "return": 36, "enter": 36, "l": 37, "j": 38, "'": 39, "k": 40,
        ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47,
        "tab": 48, "space": 49, "`": 50, "escape": 53, "esc": 53,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
        "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
        "home": 115, "pageup": 116, "delete": 117, "forwarddelete": 117,
        "end": 119, "pagedown": 121, "left": 123, "right": 124, "down": 125,
        "up": 126
    ]
}
