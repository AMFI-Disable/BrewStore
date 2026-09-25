import AppKit
import Foundation
import SwiftUI

/// Attributes parsed from CSS styles, HTML tags, and inline formatting.
public struct CSSStyleAttributes: Equatable, Sendable {
    public var foregroundColor: Color?
    public var backgroundColor: Color?
    public var isBold: Bool = false
    public var isItalic: Bool = false
    public var isUnderlined: Bool = false
    public var isStrikethrough: Bool = false
    public var isMonospaced: Bool = false
    public var linkURL: URL?
    public var fontSizeDelta: CGFloat?

    public init(
        foregroundColor: Color? = nil,
        backgroundColor: Color? = nil,
        isBold: Bool = false,
        isItalic: Bool = false,
        isUnderlined: Bool = false,
        isStrikethrough: Bool = false,
        isMonospaced: Bool = false,
        linkURL: URL? = nil,
        fontSizeDelta: CGFloat? = nil
    ) {
        self.foregroundColor = foregroundColor
        self.backgroundColor = backgroundColor
        self.isBold = isBold
        self.isItalic = isItalic
        self.isUnderlined = isUnderlined
        self.isStrikethrough = isStrikethrough
        self.isMonospaced = isMonospaced
        self.linkURL = linkURL
        self.fontSizeDelta = fontSizeDelta
    }

    /// Merges other attributes on top of self (overlay priority).
    public func merging(_ other: CSSStyleAttributes) -> CSSStyleAttributes {
        var merged = self
        if let fg = other.foregroundColor { merged.foregroundColor = fg }
        if let bg = other.backgroundColor { merged.backgroundColor = bg }
        if other.isBold { merged.isBold = true }
        if other.isItalic { merged.isItalic = true }
        if other.isUnderlined { merged.isUnderlined = true }
        if other.isStrikethrough { merged.isStrikethrough = true }
        if other.isMonospaced { merged.isMonospaced = true }
        if let link = other.linkURL { merged.linkURL = link }
        if let delta = other.fontSizeDelta { merged.fontSizeDelta = delta }
        return merged
    }
}

/// Robust parser for CSS styling, HTML tags, and Markdown formatting, converting rich markup into SwiftUI `AttributedString`.
public enum CSSAndMarkdownParser {

    // MARK: - HTML Entity Decoding

    private static let namedEntities: [String: String] = [
        "&amp;": "&",
        "&lt;": "<",
        "&gt;": ">",
        "&quot;": "\"",
        "&apos;": "'",
        "&#39;": "'",
        "&#x27;": "'",
        "&nbsp;": " ",
        "&copy;": "©",
        "&reg;": "®",
        "&trade;": "™",
        "&bull;": "•",
        "&hellip;": "…",
        "&mdash;": "—",
        "&ndash;": "–",
        "&cent;": "¢",
        "&pound;": "£",
        "&yen;": "¥",
        "&euro;": "€"
    ]

    /// Decodes HTML entities into Unicode characters.
    public static func decodeHTMLEntities(_ input: String) -> String {
        guard input.contains("&") else { return input }
        var result = input

        for (entity, replacement) in namedEntities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }

        // Numeric decimal entities: &#123;
        let decPattern = "&#([0-9]{1,6});"
        if let regex = try? NSRegularExpression(pattern: decPattern) {
            let nsString = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: nsString.length)).reversed()
            for match in matches {
                let entityRange = match.range
                let numRange = match.range(at: 1)
                let numStr = nsString.substring(with: numRange)
                if let codePoint = UInt32(numStr), let scalar = UnicodeScalar(codePoint) {
                    result = (result as NSString).replacingCharacters(in: entityRange, with: String(scalar))
                }
            }
        }

        // Numeric hex entities: &#x1f600;
        let hexPattern = "&#[xX]([0-9a-fA-F]{1,6});"
        if let regex = try? NSRegularExpression(pattern: hexPattern) {
            let nsString = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: nsString.length)).reversed()
            for match in matches {
                let entityRange = match.range
                let hexRange = match.range(at: 1)
                let hexStr = nsString.substring(with: hexRange)
                if let codePoint = UInt32(hexStr, radix: 16), let scalar = UnicodeScalar(codePoint) {
                    result = (result as NSString).replacingCharacters(in: entityRange, with: String(scalar))
                }
            }
        }

        return result
    }

    // MARK: - CSS Color Parsing

    private static let standardNamedColors: [String: Color] = [
        "black": .black,
        "white": .white,
        "gray": .gray,
        "grey": .gray,
        "red": .red,
        "green": .green,
        "blue": .blue,
        "orange": .orange,
        "yellow": .yellow,
        "pink": .pink,
        "purple": .purple,
        "cyan": .cyan,
        "mint": .mint,
        "teal": .teal,
        "indigo": .indigo,
        "brown": .brown,
        "crimson": Color(red: 0.86, green: 0.08, blue: 0.24),
        "gold": Color(red: 1.0, green: 0.84, blue: 0.0),
        "lime": Color(red: 0.0, green: 1.0, blue: 0.0),
        "magenta": Color(red: 1.0, green: 0.0, blue: 1.0),
        "violet": Color(red: 0.93, green: 0.51, blue: 0.93)
    ]

    /// Parses a CSS color value (hex, rgb, rgba, or named) into a SwiftUI `Color`.
    public static func parseCSSColor(_ raw: String) -> Color? {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleaned.isEmpty else { return nil }

        // Named colors
        if let named = standardNamedColors[cleaned] {
            return named
        }

        // Hex colors (#rgb, #rgba, #rrggbb, #rrggbbaa)
        if cleaned.hasPrefix("#") {
            let hex = String(cleaned.dropFirst())
            var int: UInt64 = 0
            guard Scanner(string: hex).scanHexInt64(&int) else { return nil }

            let r, g, b, a: Double
            switch hex.count {
            case 3: // RGB (12-bit)
                r = Double((int >> 8) * 17) / 255.0
                g = Double((int >> 4 & 0xF) * 17) / 255.0
                b = Double((int & 0xF) * 17) / 255.0
                a = 1.0
            case 4: // RGBA (16-bit)
                r = Double((int >> 12) * 17) / 255.0
                g = Double((int >> 8 & 0xF) * 17) / 255.0
                b = Double((int >> 4 & 0xF) * 17) / 255.0
                a = Double((int & 0xF) * 17) / 255.0
            case 6: // RRGGBB (24-bit)
                r = Double(int >> 16) / 255.0
                g = Double(int >> 8 & 0xFF) / 255.0
                b = Double(int & 0xFF) / 255.0
                a = 1.0
            case 8: // RRGGBBAA (32-bit)
                r = Double(int >> 24) / 255.0
                g = Double(int >> 16 & 0xFF) / 255.0
                b = Double(int >> 8 & 0xFF) / 255.0
                a = Double(int & 0xFF) / 255.0
            default:
                return nil
            }
            return Color(red: r, green: g, blue: b, opacity: a)
        }

        // Functional rgb(...) or rgba(...)
        if cleaned.hasPrefix("rgb") {
            let inner = cleaned
                .replacingOccurrences(of: "rgba(", with: "")
                .replacingOccurrences(of: "rgb(", with: "")
                .replacingOccurrences(of: ")", with: "")
            let components = inner.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            if components.count >= 3 {
                guard let r = Double(components[0]),
                      let g = Double(components[1]),
                      let b = Double(components[2]) else { return nil }
                let a = components.count >= 4 ? (Double(components[3]) ?? 1.0) : 1.0
                return Color(red: r / 255.0, green: g / 255.0, blue: b / 255.0, opacity: a)
            }
        }

        return nil
    }

    // MARK: - CSS Inline & Stylesheet Parsing

    /// Parses a CSS declaration block (e.g. `color: red; font-weight: bold; background: #eee`).
    public static func parseInlineStyle(_ styleString: String) -> CSSStyleAttributes {
        var attributes = CSSStyleAttributes()
        let declarations = styleString.split(separator: ";")

        for decl in declarations {
            let parts = decl.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            let property = parts[0].lowercased()
            let value = parts[1].lowercased()

            switch property {
            case "color":
                attributes.foregroundColor = parseCSSColor(value)

            case "background", "background-color":
                attributes.backgroundColor = parseCSSColor(value)

            case "font-weight":
                if value == "bold" || value == "bolder" || value == "700" || value == "800" || value == "900" || value == "600" {
                    attributes.isBold = true
                } else if value == "normal" || value == "400" {
                    attributes.isBold = false
                }

            case "font-style":
                if value == "italic" || value == "oblique" {
                    attributes.isItalic = true
                }

            case "text-decoration", "text-decoration-line":
                if value.contains("underline") {
                    attributes.isUnderlined = true
                }
                if value.contains("line-through") {
                    attributes.isStrikethrough = true
                }

            case "font-family":
                if value.contains("mono") || value.contains("courier") || value.contains("menlo") || value.contains("consolas") {
                    attributes.isMonospaced = true
                }

            case "font-size":
                if value == "small" || value == "smaller" {
                    attributes.fontSizeDelta = -2
                } else if value == "x-small" || value == "xx-small" {
                    attributes.fontSizeDelta = -3
                } else if value == "large" || value == "larger" {
                    attributes.fontSizeDelta = 2
                } else if value == "x-large" || value == "xx-large" {
                    attributes.fontSizeDelta = 4
                }

            default:
                break
            }
        }

        return attributes
    }

    /// Extracts `<style>...</style>` stylesheet blocks and parses CSS class rules (e.g. `.badge { color: red; }`).
    public static func extractStylesheets(from rawText: String) -> (cleanedText: String, classMap: [String: CSSStyleAttributes]) {
        var classMap: [String: CSSStyleAttributes] = [:]
        guard rawText.contains("<style") else {
            return (rawText, classMap)
        }

        let pattern = "(?is)<style[^>]*>(.*?)</style>"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return (rawText, classMap)
        }

        let nsString = rawText as NSString
        let matches = regex.matches(in: rawText, range: NSRange(location: 0, length: nsString.length))

        for match in matches {
            guard match.numberOfRanges > 1 else { continue }
            let styleContent = nsString.substring(with: match.range(at: 1))

            // Parse CSS class rules: .className { declarations }
            let rulePattern = "(?s)\\.([a-zA-Z0-9_-]+)\\s*\\{([^\\}]+)\\}"
            if let ruleRegex = try? NSRegularExpression(pattern: rulePattern) {
                let ruleMatches = ruleRegex.matches(in: styleContent, range: NSRange(location: 0, length: (styleContent as NSString).length))
                for rMatch in ruleMatches {
                    if rMatch.numberOfRanges > 2 {
                        let className = (styleContent as NSString).substring(with: rMatch.range(at: 1))
                        let decls = (styleContent as NSString).substring(with: rMatch.range(at: 2))
                        classMap[className] = parseInlineStyle(decls)
                    }
                }
            }
        }

        let cleaned = regex.stringByReplacingMatches(in: rawText, range: NSRange(location: 0, length: nsString.length), withTemplate: "")
        return (cleaned, classMap)
    }

    // MARK: - Markdown & Markup Preprocessor

    /// Strips HTML tags and comments to produce clean plain text.
    public static func stripHTML(_ input: String) -> String {
        var text = decodeHTMLEntities(input)
        text = text.replacingOccurrences(of: "(?is)<!--.*?-->", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return text
    }

    /// Preprocesses markdown text containing HTML linebreaks, dividers, and styling blocks.
    public static func preprocessMarkdown(_ raw: String) -> (text: String, classMap: [String: CSSStyleAttributes]) {
        // 1. Strip ANSI escape sequences from terminal logs or raw caveats
        var processed = ANSIColorSerializer.stripAnsiCodes(raw)

        // 2. Strip HTML comments
        processed = processed.replacingOccurrences(of: "(?is)<!--.*?-->", with: "", options: .regularExpression)

        // 3. Extract <style> blocks
        let (noStylesheets, classMap) = extractStylesheets(from: processed)
        processed = noStylesheets

        // 4. Normalize HTML linebreaks & structural tags
        processed = processed.replacingOccurrences(of: "(?i)<br\\s*/?>", with: "\n", options: .regularExpression)
        processed = processed.replacingOccurrences(of: "(?i)<hr\\s*/?>", with: "\n---\n", options: .regularExpression)
        processed = processed.replacingOccurrences(of: "(?i)</p>", with: "\n\n", options: .regularExpression)
        processed = processed.replacingOccurrences(of: "(?i)</div>", with: "\n", options: .regularExpression)

        return (processed, classMap)
    }

    // MARK: - Rich AttributedString Rendering

    /// Renders text with combined CSS styles, HTML tags, and Markdown syntax into a native SwiftUI `AttributedString`.
    public static func renderAttributedString(
        _ rawText: String,
        baseFont: Font = .body,
        baseFontSize: CGFloat = 13,
        accentColor: Color = .accentColor,
        classMap: [String: CSSStyleAttributes] = [:]
    ) -> AttributedString {
        let cleanInput = ANSIColorSerializer.stripAnsiCodes(rawText)
        guard !cleanInput.isEmpty else { return AttributedString() }

        // Check if there is any HTML markup or entities
        let hasHTML = cleanInput.contains("<") || cleanInput.contains("&")
        if !hasHTML {
            // Pure markdown path using native Swift AttributedString markdown parser
            if let parsed = try? AttributedString(markdown: cleanInput, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                return applyBaseStyling(to: parsed, baseFont: baseFont, baseFontSize: baseFontSize, accentColor: accentColor)
            }
            return AttributedString(cleanInput)
        }

        // Hybrid HTML + CSS + Markdown tokenized parser
        return parseHybridHTMLAndMarkdown(
            cleanInput,
            baseFont: baseFont,
            baseFontSize: baseFontSize,
            accentColor: accentColor,
            classMap: classMap
        )
    }

    private static func applyBaseStyling(
        to attrString: AttributedString,
        baseFont: Font,
        baseFontSize: CGFloat,
        accentColor: Color
    ) -> AttributedString {
        var result = attrString
        // Provide pleasant link color
        for run in result.runs {
            if run.link != nil {
                result[run.range].foregroundColor = accentColor
                result[run.range].underlineStyle = .single
            }
        }
        return result
    }

    /// Parses inline HTML tags, CSS inline styles, and embedded markdown into a unified `AttributedString`.
    private static func parseHybridHTMLAndMarkdown(
        _ rawText: String,
        baseFont: Font,
        baseFontSize: CGFloat,
        accentColor: Color,
        classMap: [String: CSSStyleAttributes]
    ) -> AttributedString {
        var finalResult = AttributedString()
        var styleStack: [CSSStyleAttributes] = [CSSStyleAttributes()]

        let tagPattern = "(?is)<(/)?([a-zA-Z0-9_-]+)([^>]*)>"
        guard let tagRegex = try? NSRegularExpression(pattern: tagPattern) else {
            return (try? AttributedString(markdown: decodeHTMLEntities(rawText))) ?? AttributedString(rawText)
        }

        let nsString = rawText as NSString
        var lastLocation = 0

        let matches = tagRegex.matches(in: rawText, range: NSRange(location: 0, length: nsString.length))

        for match in matches {
            // Text segment before the tag
            if match.range.location > lastLocation {
                let textChunk = nsString.substring(with: NSRange(location: lastLocation, length: match.range.location - lastLocation))
                appendStyledSegment(
                    textChunk,
                    style: styleStack.last ?? CSSStyleAttributes(),
                    to: &finalResult,
                    baseFontSize: baseFontSize,
                    accentColor: accentColor
                )
            }

            let isClosing = match.range(at: 1).location != NSNotFound
            let tagName = nsString.substring(with: match.range(at: 2)).lowercased()
            let rawAttrs = match.range(at: 3).location != NSNotFound ? nsString.substring(with: match.range(at: 3)) : ""

            if isClosing {
                // Pop matching tag from stack
                if styleStack.count > 1 {
                    styleStack.removeLast()
                }
            } else {
                // Self-closing line break tag
                if tagName == "br" {
                    finalResult.append(AttributedString("\n"))
                    lastLocation = match.range.location + match.range.length
                    continue
                }
                if tagName == "hr" {
                    finalResult.append(AttributedString("\n───\n"))
                    lastLocation = match.range.location + match.range.length
                    continue
                }

                // Compute attributes for new tag
                var tagStyle = CSSStyleAttributes()

                // Tag-specific default styles
                switch tagName {
                case "b", "strong":
                    tagStyle.isBold = true
                case "i", "em":
                    tagStyle.isItalic = true
                case "u":
                    tagStyle.isUnderlined = true
                case "s", "del", "strike":
                    tagStyle.isStrikethrough = true
                case "code", "kbd", "samp", "tt":
                    tagStyle.isMonospaced = true
                    tagStyle.backgroundColor = Color.secondary.opacity(0.12)
                    tagStyle.fontSizeDelta = -1
                case "mark":
                    tagStyle.backgroundColor = Color.yellow.opacity(0.35)
                case "small":
                    tagStyle.fontSizeDelta = -2
                case "a":
                    if let href = extractAttribute("href", from: rawAttrs), let url = URL(string: href) {
                        tagStyle.linkURL = url
                        tagStyle.foregroundColor = accentColor
                        tagStyle.isUnderlined = true
                    }
                case "font":
                    if let colorStr = extractAttribute("color", from: rawAttrs), let c = parseCSSColor(colorStr) {
                        tagStyle.foregroundColor = c
                    }
                    if let face = extractAttribute("face", from: rawAttrs), face.lowercased().contains("mono") {
                        tagStyle.isMonospaced = true
                    }
                default:
                    break
                }

                // Check class attribute
                if let className = extractAttribute("class", from: rawAttrs), let classStyle = classMap[className] {
                    tagStyle = tagStyle.merging(classStyle)
                }

                // Check style attribute: style="..."
                if let inlineStyleStr = extractAttribute("style", from: rawAttrs) {
                    let parsedStyle = parseInlineStyle(inlineStyleStr)
                    tagStyle = tagStyle.merging(parsedStyle)
                }

                // Inherit existing active styles and push
                let inherited = (styleStack.last ?? CSSStyleAttributes()).merging(tagStyle)
                styleStack.append(inherited)
            }

            lastLocation = match.range.location + match.range.length
        }

        // Trailing text after last tag
        if lastLocation < nsString.length {
            let trailingChunk = nsString.substring(with: NSRange(location: lastLocation, length: nsString.length - lastLocation))
            appendStyledSegment(
                trailingChunk,
                style: styleStack.last ?? CSSStyleAttributes(),
                to: &finalResult,
                baseFontSize: baseFontSize,
                accentColor: accentColor
            )
        }

        return finalResult
    }

    private static func extractAttribute(_ attrName: String, from attributeString: String) -> String? {
        let pattern = "(?i)\(attrName)\\s*=\\s*[\"']([^\"']*)[\"']"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = attributeString as NSString
        guard let match = regex.firstMatch(in: attributeString, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges > 1 else { return nil }
        return ns.substring(with: match.range(at: 1))
    }

    private static func appendStyledSegment(
        _ text: String,
        style: CSSStyleAttributes,
        to target: inout AttributedString,
        baseFontSize: CGFloat,
        accentColor: Color
    ) {
        guard !text.isEmpty else { return }

        // Decode HTML entities
        let decoded = decodeHTMLEntities(text)

        // Parse any embedded inline markdown (e.g. **bold**, *italic*, `code`)
        var segment: AttributedString
        if let md = try? AttributedString(markdown: decoded, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            segment = md
        } else {
            segment = AttributedString(decoded)
        }

        // Apply CSS attributes
        if let fg = style.foregroundColor {
            segment.foregroundColor = fg
        }
        if let bg = style.backgroundColor {
            segment.backgroundColor = bg
        }
        if style.isUnderlined {
            segment.underlineStyle = .single
        }
        if style.isStrikethrough {
            segment.strikethroughStyle = .single
        }
        if let link = style.linkURL {
            segment.link = link
            if style.foregroundColor == nil {
                segment.foregroundColor = accentColor
            }
        }

        // Font calculation
        let size = baseFontSize + (style.fontSizeDelta ?? 0)
        let weight: Font.Weight = style.isBold ? .bold : .regular
        let design: Font.Design = style.isMonospaced ? .monospaced : .default

        var font = Font.system(size: max(size, 9), weight: weight, design: design)
        if style.isItalic {
            font = font.italic()
        }
        segment.font = font

        target.append(segment)
    }
}
