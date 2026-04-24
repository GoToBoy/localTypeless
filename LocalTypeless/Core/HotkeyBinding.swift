import Foundation
import AppKit

struct HotkeyBinding: Codable, Equatable, Hashable {

    enum Trigger: String, Codable { case press, doubleTap, longPress }

    enum ModifierOnly: String, Codable {
        case leftCommand, rightCommand
        case leftOption, rightOption
        case leftControl, rightControl
        case leftShift, rightShift
        case fn

        var displayName: String {
            switch self {
            case .leftCommand:  return "Left ⌘"
            case .rightCommand: return "Right ⌘"
            case .leftOption:   return "Left ⌥"
            case .rightOption:  return "Right ⌥"
            case .leftControl:  return "Left ⌃"
            case .rightControl: return "Right ⌃"
            case .leftShift:    return "Left ⇧"
            case .rightShift:   return "Right ⇧"
            case .fn:           return "fn"
            }
        }
    }

    let keyCode: UInt16?
    let modifierMask: NSEvent.ModifierFlags
    let trigger: Trigger
    let modifierOnly: ModifierOnly?

    static let `default` = HotkeyBinding(
        keyCode: nil,
        modifierMask: [],
        trigger: .doubleTap,
        modifierOnly: .rightOption
    )

    var displayString: String {
        if let mod = modifierOnly {
            let prefix: String = {
                switch trigger {
                case .press: return "Tap"
                case .doubleTap: return "Double-tap"
                case .longPress: return "Hold"
                }
            }()
            return "\(prefix) \(mod.displayName)"
        }
        var s = ""
        if modifierMask.contains(.command) { s += "⌘" }
        if modifierMask.contains(.shift)   { s += "⇧" }
        if modifierMask.contains(.control) { s += "⌃" }
        if modifierMask.contains(.option)  { s += "⌥" }
        if let kc = keyCode {
            s += Self.displayCharacter(for: kc) ?? "?"
        }
        return s
    }

    private static let keyCodeNames: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L", 38: "J",
        39: "'", 40: "K", 41: ";", 45: "N", 46: "M", 49: "Space"
    ]

    static func displayCharacter(for keyCode: UInt16) -> String? {
        keyCodeNames[keyCode]
    }
}

extension HotkeyBinding {
    func conflictsWith(_ other: HotkeyBinding) -> Bool {
        if let k1 = keyCode, let k2 = other.keyCode {
            return k1 == k2 && modifierMask == other.modifierMask
        }
        if let m1 = modifierOnly, let m2 = other.modifierOnly {
            return m1 == m2 && trigger == other.trigger
        }
        return false
    }
}

extension NSEvent.ModifierFlags: @retroactive Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.rawValue)
    }
}

extension NSEvent.ModifierFlags: @retroactive Codable {
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(UInt.self)
        self = NSEvent.ModifierFlags(rawValue: raw)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(self.rawValue)
    }
}
