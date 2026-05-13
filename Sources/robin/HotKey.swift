import ApplicationServices
import Foundation

struct HotKey {
    let keyCode: CGKeyCode
    let modifiers: CGEventFlags

    var isFunctionKey: Bool {
        keyCode == HotKeyParser.functionKeyCode
    }
}

enum HotKeyParser {
    static let defaultValue = "control+]"
    static let functionKeyCode: CGKeyCode = 63

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

    static func keyName(for keyCode: UInt16) -> String? {
        keyNamesByCode[CGKeyCode(keyCode)]
    }

    private static let keyCodes: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
        "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
        "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
        "5": 23, "=": 24, "+": 24, "9": 25, "7": 26, "-": 27, "8": 28,
        "0": 29, "§": 10, "±": 10, "section": 10, "iso-section": 10,
        "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35,
        "return": 36, "enter": 36, "l": 37, "j": 38, "'": 39, "k": 40,
        ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47,
        "tab": 48, "space": 49, "`": 50, "escape": 53, "esc": 53,
        "fn": functionKeyCode, "function": functionKeyCode,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
        "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
        "home": 115, "pageup": 116, "delete": 117, "forwarddelete": 117,
        "end": 119, "pagedown": 121, "left": 123, "right": 124, "down": 125,
        "up": 126, "yen": 93, "¥": 93, "jis-yen": 93, "jis-underscore": 94,
        "jis-keypad-comma": 95, "eisu": 102, "kana": 104
    ]

    private static let keyNamesByCode: [CGKeyCode: String] = [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x",
        8: "c", 9: "v", 10: "§", 11: "b", 12: "q", 13: "w", 14: "e", 15: "r",
        16: "y", 17: "t", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "o", 32: "u", 33: "[", 34: "i", 35: "p", 36: "return",
        37: "l", 38: "j", 39: "'", 40: "k", 41: ";", 42: "\\", 43: ",",
        44: "/", 45: "n", 46: "m", 47: ".", 48: "tab", 49: "space",
        50: "`", 53: "escape", 63: "fn", 96: "f5", 97: "f6", 98: "f7", 99: "f3",
        100: "f8", 101: "f9", 103: "f11", 109: "f10", 111: "f12",
        115: "home", 116: "pageup", 117: "delete", 118: "f4", 119: "end",
        120: "f2", 121: "pagedown", 122: "f1", 123: "left", 124: "right",
        125: "down", 126: "up", 93: "yen", 94: "jis-underscore",
        95: "jis-keypad-comma", 102: "eisu", 104: "kana"
    ]
}
