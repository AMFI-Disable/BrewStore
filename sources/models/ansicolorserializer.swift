import Foundation
import SwiftUI

/// Represents a parsed segment of terminal output with ANSI styling attributes.
struct ANSISegment: Equatable, Sendable {
    let text: String
    let foregroundColor: Color?
    let backgroundColor: Color?
    let isBold: Bool
    let isDim: Bool
    let isUnderlined: Bool

    init(
        text: String,
        foregroundColor: Color? = nil,
        backgroundColor: Color? = nil,
        isBold: Bool = false,
        isDim: Bool = false,
        isUnderlined: Bool = false
    ) {
        self.text = text
        self.foregroundColor = foregroundColor
        self.backgroundColor = backgroundColor
        self.isBold = isBold
        self.isDim = isDim
        self.isUnderlined = isUnderlined
    }
}

/// Serializes and deserializes terminal ANSI escape codes into native SwiftUI styles and `AttributedString`.
enum ANSIColorSerializer: Sendable {

    /// Parses raw ANSI-encoded string into discrete styled segments.
    static func parse(_ rawText: String) -> [ANSISegment] {
        guard !rawText.isEmpty else { return [] }

        var segments: [ANSISegment] = []
        var currentForeground: Color?
        var currentBackground: Color?
        var isBold = false
        var isDim = false
        var isUnderlined = false

        let scanner = Scanner(string: rawText)
        scanner.charactersToBeSkipped = nil

        let escapeChar = "\u{001B}"

        while !scanner.isAtEnd {
            // Read normal text up to the next escape character
            if let textChunk = scanner.scanUpToString(escapeChar) {
                // Filter out carriage returns without newlines if present
                let cleanChunk = textChunk.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "")
                if !cleanChunk.isEmpty {
                    segments.append(ANSISegment(
                        text: cleanChunk,
                        foregroundColor: currentForeground,
                        backgroundColor: currentBackground,
                        isBold: isBold,
                        isDim: isDim,
                        isUnderlined: isUnderlined
                    ))
                }
            }

            guard scanner.scanString(escapeChar) != nil else {
                break
            }

            // Check if this is a CSI sequence: "\e["
            if scanner.scanString("[") != nil {
                // Scan parameter bytes up to terminating command character
                var paramString = ""
                while !scanner.isAtEnd {
                    guard let ch = scanner.scanCharacter() else { break }
                    if ch.isLetter || ch == "@" || ch == "`" || ch == "~" {
                        // Terminating command found
                        if ch == "m" {
                            // SGR (Select Graphic Rendition)
                            applySGR(paramString, foreground: &currentForeground, background: &currentBackground, isBold: &isBold, isDim: &isDim, isUnderlined: &isUnderlined)
                        }
                        // Non-'m' CSI codes (cursor, clear line, etc.) are discarded
                        break
                    } else {
                        paramString.append(ch)
                    }
                }
            } else if scanner.scanString("]") != nil {
                // OSC sequence: scan up to BEL (\u{0007}) or ST (\u{001B}\)
                _ = scanner.scanUpToString("\u{0007}")
                _ = scanner.scanString("\u{0007}")
            }
        }

        return segments
    }

    /// Converts raw text containing ANSI escape sequences into a single styled SwiftUI `AttributedString`.
    static func attributedString(
        from rawText: String,
        defaultColor: Color = .primary,
        baseFontSize: CGFloat = 11
    ) -> AttributedString {
        let segments = parse(rawText)
        var result = AttributedString()

        for segment in segments {
            var piece = AttributedString(segment.text)
            piece.foregroundColor = segment.foregroundColor ?? defaultColor
            if let bg = segment.backgroundColor {
                piece.backgroundColor = bg
            }

            let weight: Font.Weight = segment.isBold ? .bold : (segment.isDim ? .light : .regular)
            piece.font = .system(size: baseFontSize, weight: weight, design: .monospaced)

            if segment.isUnderlined {
                piece.underlineStyle = .single
            }

            result.append(piece)
        }

        return result
    }

    /// Parses multiline raw ANSI text into an array of attributed strings, one per line.
    static func parseLinesToAttributedStrings(
        _ rawText: String,
        defaultColor: Color = .primary,
        baseFontSize: CGFloat = 11
    ) -> [AttributedString] {
        let lines = rawText.components(separatedBy: .newlines)
        return lines.map { line in
            attributedString(from: line, defaultColor: defaultColor, baseFontSize: baseFontSize)
        }
    }

    /// Completely strips ANSI escape sequences from text for pure plaintext extraction.
    static func stripAnsiCodes(_ rawText: String) -> String {
        guard rawText.contains("\u{001B}") else { return rawText }
        let pattern = "\\x1B(?:\\[[0-?]*[ -/]*[@-~]|\\][^\u{0007}\u{001B}]*(?:\u{0007}|\\x1B\\\\))"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return rawText
        }
        let range = NSRange(rawText.startIndex..<rawText.endIndex, in: rawText)
        return regex.stringByReplacingMatches(in: rawText, options: [], range: range, withTemplate: "")
    }

    /// Extracts download or build progress percentage (0.0 - 100.0) from Homebrew output lines.
    static func extractDownloadProgress(from line: String) -> Double? {
        let clean = stripAnsiCodes(line)

        // Pattern 1: Homebrew curl style: "## 65.4%" or "##O#- # 82.1%"
        if let match = clean.range(of: #"(\d{1,3}(?:\.\d+)?)%"#, options: .regularExpression) {
            let percentageString = clean[match].dropLast() // remove "%"
            if let val = Double(percentageString), val >= 0, val <= 100 {
                return val
            }
        }

        // Pattern 2: "[ 45% ]"
        if let match = clean.range(of: #"\[\s*(\d{1,3})%\s*\]"#, options: .regularExpression) {
            let inside = clean[match]
                .replacingOccurrences(of: "[", with: "")
                .replacingOccurrences(of: "]", with: "")
                .replacingOccurrences(of: "%", with: "")
                .trimmingCharacters(in: .whitespaces)
            if let val = Double(inside), val >= 0, val <= 100 {
                return val
            }
        }

        return nil
    }

    // MARK: - Internal SGR State Decoder

    private static func applySGR(
        _ params: String,
        foreground: inout Color?,
        background: inout Color?,
        isBold: inout Bool,
        isDim: inout Bool,
        isUnderlined: inout Bool
    ) {
        if params.isEmpty {
            // "\e[m" is reset
            reset(foreground: &foreground, background: &background, isBold: &isBold, isDim: &isDim, isUnderlined: &isUnderlined)
            return
        }

        let codes = params.split(separator: ";").compactMap { Int($0) }
        var index = 0

        while index < codes.count {
            let code = codes[index]

            switch code {
            case 0:
                reset(foreground: &foreground, background: &background, isBold: &isBold, isDim: &isDim, isUnderlined: &isUnderlined)
            case 1:
                isBold = true
            case 2:
                isDim = true
            case 4:
                isUnderlined = true
            case 22:
                isBold = false
                isDim = false
            case 24:
                isUnderlined = false
            case 30: foreground = .black
            case 31: foreground = .red
            case 32: foreground = .green
            case 33: foreground = .yellow
            case 34: foreground = .blue
            case 35: foreground = .purple
            case 36: foreground = .cyan
            case 37: foreground = .white
            case 39: foreground = nil // default foreground
            case 40: background = .black
            case 41: background = .red
            case 42: background = .green
            case 43: background = .yellow
            case 44: background = .blue
            case 45: background = .purple
            case 46: background = .cyan
            case 47: background = .white
            case 49: background = nil // default background
            case 90: foreground = Color.gray
            case 91: foreground = Color.red.opacity(0.8)
            case 92: foreground = Color.green.opacity(0.8)
            case 93: foreground = Color.yellow.opacity(0.8)
            case 94: foreground = Color.blue.opacity(0.8)
            case 95: foreground = Color.purple.opacity(0.8)
            case 96: foreground = Color.cyan.opacity(0.8)
            case 97: foreground = Color.white.opacity(0.9)
            case 100: background = Color.gray.opacity(0.3)
            case 101: background = Color.red.opacity(0.3)
            case 102: background = Color.green.opacity(0.3)
            case 103: background = Color.yellow.opacity(0.3)
            case 104: background = Color.blue.opacity(0.3)
            case 105: background = Color.purple.opacity(0.3)
            case 106: background = Color.cyan.opacity(0.3)
            case 107: background = Color.white.opacity(0.3)
            case 38:
                // Extended foreground (256-color or 24-bit RGB)
                if index + 2 < codes.count && codes[index + 1] == 5 {
                    let colorIndex = codes[index + 2]
                    foreground = colorFrom256(colorIndex)
                    index += 2
                } else if index + 4 < codes.count && codes[index + 1] == 2 {
                    let r = Double(codes[index + 2]) / 255.0
                    let g = Double(codes[index + 3]) / 255.0
                    let b = Double(codes[index + 4]) / 255.0
                    foreground = Color(red: r, green: g, blue: b)
                    index += 4
                }
            case 48:
                // Extended background
                if index + 2 < codes.count && codes[index + 1] == 5 {
                    let colorIndex = codes[index + 2]
                    background = colorFrom256(colorIndex)
                    index += 2
                } else if index + 4 < codes.count && codes[index + 1] == 2 {
                    let r = Double(codes[index + 2]) / 255.0
                    let g = Double(codes[index + 3]) / 255.0
                    let b = Double(codes[index + 4]) / 255.0
                    background = Color(red: r, green: g, blue: b)
                    index += 4
                }
            default:
                break
            }

            index += 1
        }
    }

    private static func reset(
        foreground: inout Color?,
        background: inout Color?,
        isBold: inout Bool,
        isDim: inout Bool,
        isUnderlined: inout Bool
    ) {
        foreground = nil
        background = nil
        isBold = false
        isDim = false
        isUnderlined = false
    }

    private static func colorFrom256(_ index: Int) -> Color {
        switch index {
        case 0: return .black
        case 1: return .red
        case 2: return .green
        case 3: return .yellow
        case 4: return .blue
        case 5: return .purple
        case 6: return .cyan
        case 7: return .white
        case 8...15: return .gray
        case 16...231:
            let colorVal = index - 16
            let r = Double((colorVal / 36) % 6) / 5.0
            let g = Double((colorVal / 6) % 6) / 5.0
            let b = Double(colorVal % 6) / 5.0
            return Color(red: r, green: g, blue: b)
        case 232...255:
            let gray = Double(index - 232) / 23.0
            return Color(white: gray)
        default:
            return .primary
        }
    }
}
