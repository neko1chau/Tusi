import Foundation

/// Converts straight ASCII quotes into typographic ones.
///
/// The system prompt already asks for typographic punctuation, but cheap models comply
/// unevenly, so the result is normalized here too — a deterministic pass is the only way
/// to actually guarantee it. Text inside code spans and fenced blocks is left byte-exact:
/// curly quotes there would break the code the translation is trying to preserve.
enum SmartQuotes {
    static func apply(to text: String) -> String {
        guard text.contains("\"") || text.contains("'") else { return text }

        let characters = Array(text)
        var result = ""
        result.reserveCapacity(characters.count)

        var insideCode = false
        var doubleIsOpen = false
        var singleIsOpen = false
        var previous: Character?
        var index = 0

        while index < characters.count {
            let character = characters[index]

            // A run of backticks opens or closes code — ` for spans, ``` for blocks.
            if character == "`" {
                var end = index
                while end < characters.count, characters[end] == "`" { end += 1 }
                result.append(contentsOf: characters[index..<end])
                insideCode.toggle()
                previous = "`"
                index = end
                continue
            }

            if insideCode {
                result.append(character)
                previous = character
                index += 1
                continue
            }

            let next: Character? = index + 1 < characters.count ? characters[index + 1] : nil
            switch character {
            case "\"":
                let opening = isOpening(previous: previous, isOpen: doubleIsOpen)
                doubleIsOpen = opening
                result.append(opening ? "\u{201C}" : "\u{201D}")
            case "'":
                // A straight quote between Latin word characters is an apostrophe, not a
                // quote mark: don’t, it’s, teams’ — never a nesting delimiter.
                if let previous, (previous.isLetter || previous.isNumber), !isCJK(previous) {
                    result.append("\u{2019}")
                } else if let next, next.isNumber, !(previous.map { $0.isLetter || $0.isNumber } ?? false) {
                    result.append("\u{2019}")  // elision: the ’90s
                } else {
                    let opening = isOpening(previous: previous, isOpen: singleIsOpen)
                    singleIsOpen = opening
                    result.append(opening ? "\u{2018}" : "\u{2019}")
                }
            default:
                result.append(character)
            }
            previous = character
            index += 1
        }
        return result
    }

    /// Latin text puts a space before an opening quote, so the preceding character settles
    /// it. CJK text doesn't — 他说“你好” has the quote flush against the character — so there
    /// the only reliable signal is whether a quote is currently open.
    private static func isOpening(previous: Character?, isOpen: Bool) -> Bool {
        guard let previous else { return true }
        if isCJK(previous) { return !isOpen }
        if previous.isWhitespace { return true }
        return "([{<\u{201C}\u{2018}—–-".contains(previous)
    }

    private static func isCJK(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        switch scalar.value {
        case 0x3000...0x303F,    // CJK punctuation: 。，、：；「」
             0x3040...0x30FF,    // Kana
             0x3400...0x4DBF,    // Han extension A
             0x4E00...0x9FFF,    // Han
             0xAC00...0xD7AF,    // Hangul
             0xF900...0xFAFF,    // Han compatibility
             0xFF00...0xFFEF:    // Fullwidth forms: ！？（）
            return true
        default:
            return false
        }
    }
}
