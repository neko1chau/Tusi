import AppKit

/// A user-recordable keyboard shortcut.
///
/// The display string is captured at record time rather than derived on the fly:
/// turning a keyCode back into a character requires the keyboard layout that was
/// active when the key was pressed, and that can change under us.
struct KeyCombo: Equatable {
    var keyCode: UInt16
    var modifiers: UInt
    var display: String

    static let defaultCopy = KeyCombo(
        keyCode: 8,  // C
        modifiers: NSEvent.ModifierFlags([.command, .shift]).rawValue,
        display: "⇧⌘C"  // Apple's canonical modifier order is ⌃⌥⇧⌘
    )

    func matches(_ event: NSEvent) -> Bool {
        event.keyCode == keyCode && Self.normalized(event.modifierFlags).rawValue == modifiers
    }

    /// Caps lock is a state, not an intent — a shortcut shouldn't stop working because
    /// it happens to be on.
    static func normalized(_ flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        flags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock)
    }

    static func describe(keyCode: UInt16, characters: String?, flags: NSEvent.ModifierFlags) -> String {
        var result = ""
        if flags.contains(.control) { result += "⌃" }
        if flags.contains(.option) { result += "⌥" }
        if flags.contains(.shift) { result += "⇧" }
        if flags.contains(.command) { result += "⌘" }
        return result + keyName(keyCode: keyCode, characters: characters)
    }

    private static func keyName(keyCode: UInt16, characters: String?) -> String {
        // Keys whose charactersIgnoringModifiers is a control code or invisible.
        switch keyCode {
        case 36, 76: return "⏎"
        case 48: return "⇥"
        case 49: return "Space"
        case 51: return "⌫"
        case 117: return "⌦"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        case 115: return "Home"
        case 119: return "End"
        case 116: return "⇞"
        case 121: return "⇟"
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        default: break
        }
        guard let characters, let first = characters.first, first.isLetter || first.isNumber || first.isPunctuation || first.isSymbol else {
            return "Key \(keyCode)"
        }
        return characters.uppercased()
    }
}
