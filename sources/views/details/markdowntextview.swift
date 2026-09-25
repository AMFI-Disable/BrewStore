import AppKit
import SwiftUI

public enum MarkdownBlock: Equatable, Identifiable {
    case h1(String)
    case h2(String)
    case h3(String)
    case bullet(text: String, indent: Int)
    case numbered(number: Int, text: String)
    case codeBlock(code: String, language: String?)
    case blockquote(String)
    case divider
    case paragraph(String)

    public var id: String {
        switch self {
        case let .h1(s): "h1-\(s)"
        case let .h2(s): "h2-\(s)"
        case let .h3(s): "h3-\(s)"
        case let .bullet(text, indent): "b-\(indent)-\(text)"
        case let .numbered(num, text): "n-\(num)-\(text)"
        case let .codeBlock(code, lang): "code-\(lang ?? "")-\(code.hashValue)"
        case let .blockquote(s): "quote-\(s)"
        case .divider: "divider-\(UUID().uuidString)"
        case let .paragraph(s): "p-\(s.hashValue)"
        }
    }
}

public enum MarkdownParser {
    public static func parse(_ raw: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let (preprocessed, _) = CSSAndMarkdownParser.preprocessMarkdown(raw)
        let lines = preprocessed.components(separatedBy: .newlines)
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Empty line
            if trimmed.isEmpty {
                i += 1
                continue
            }

            // Code block ```
            if trimmed.hasPrefix("```") {
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count {
                    let cLine = lines[i]
                    if cLine.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        i += 1
                        break
                    }
                    codeLines.append(cLine)
                    i += 1
                }
                blocks.append(.codeBlock(code: codeLines.joined(separator: "\n"), language: lang.isEmpty ? nil : lang))
                continue
            }

            // Horizontal Rule
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                blocks.append(.divider)
                i += 1
                continue
            }

            // Headings
            if trimmed.hasPrefix("### ") {
                blocks.append(.h3(String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces)))
                i += 1
                continue
            }
            if trimmed.hasPrefix("## ") {
                blocks.append(.h2(String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)))
                i += 1
                continue
            }
            if trimmed.hasPrefix("# ") {
                blocks.append(.h1(String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)))
                i += 1
                continue
            }

            // Blockquote
            if trimmed.hasPrefix("> ") {
                var quoteLines = [String(trimmed.dropFirst(2))]
                i += 1
                while i < lines.count {
                    let nextTrimmed = lines[i].trimmingCharacters(in: .whitespaces)
                    if nextTrimmed.hasPrefix("> ") {
                        quoteLines.append(String(nextTrimmed.dropFirst(2)))
                        i += 1
                    } else if nextTrimmed.isEmpty {
                        break
                    } else {
                        quoteLines.append(nextTrimmed)
                        i += 1
                    }
                }
                blocks.append(.blockquote(quoteLines.joined(separator: " ")))
                continue
            }

            // Bullet List (*, -, •)
            if trimmed.hasPrefix("* ") || trimmed.hasPrefix("- ") || trimmed.hasPrefix("• ") {
                let leadingSpaces = line.prefix(while: { $0 == " " || $0 == "\t" }).count
                let indent = leadingSpaces / 2
                let text = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                blocks.append(.bullet(text: text, indent: indent))
                i += 1
                continue
            }

            // Numbered List (1. , 2. , etc)
            if let match = parseNumberedListItem(trimmed) {
                blocks.append(.numbered(number: match.num, text: match.text))
                i += 1
                continue
            }

            // Standard Paragraph
            var paragraphLines = [trimmed]
            i += 1
            while i < lines.count {
                let nextLine = lines[i]
                let nextTrimmed = nextLine.trimmingCharacters(in: .whitespaces)
                if nextTrimmed.isEmpty ||
                    nextTrimmed.hasPrefix("#") ||
                    nextTrimmed.hasPrefix("```") ||
                    nextTrimmed.hasPrefix("* ") ||
                    nextTrimmed.hasPrefix("- ") ||
                    nextTrimmed.hasPrefix("• ") ||
                    nextTrimmed.hasPrefix("> ") ||
                    nextTrimmed == "---" ||
                    parseNumberedListItem(nextTrimmed) != nil {
                    break
                }
                paragraphLines.append(nextTrimmed)
                i += 1
            }
            blocks.append(.paragraph(paragraphLines.joined(separator: " ")))
        }

        return blocks
    }

    private static func parseNumberedListItem(_ line: String) -> (num: Int, text: String)? {
        guard let dotIndex = line.firstIndex(of: ".") else { return nil }
        let prefix = line[..<dotIndex]
        guard let number = Int(prefix), number > 0, number < 1000 else { return nil }
        let remainder = line[line.index(after: dotIndex)...].trimmingCharacters(in: .whitespaces)
        return (number, remainder)
    }
}

public struct MarkdownTextView: View {
    public let markdown: String
    public var baseFont: Font = .body
    public var lineSpacing: CGFloat = 5
    public var accentColor: Color = .accentColor

    public init(
        markdown: String,
        baseFont: Font = .body,
        lineSpacing: CGFloat = 5,
        accentColor: Color = .accentColor
    ) {
        self.markdown = markdown
        self.baseFont = baseFont
        self.lineSpacing = lineSpacing
        self.accentColor = accentColor
    }

    public var body: some View {
        let (preprocessed, classMap) = CSSAndMarkdownParser.preprocessMarkdown(markdown)
        let blocks = MarkdownParser.parse(preprocessed)

        VStack(alignment: .leading, spacing: 14) {
            ForEach(blocks.indices, id: \.self) { idx in
                renderBlock(blocks[idx], classMap: classMap)
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func renderBlock(_ block: MarkdownBlock, classMap: [String: CSSStyleAttributes]) -> some View {
        switch block {
        case let .h1(text):
            Text(CSSAndMarkdownParser.renderAttributedString(text, baseFont: .system(size: 24, weight: .bold, design: .rounded), baseFontSize: 24, accentColor: accentColor, classMap: classMap))
                .foregroundStyle(.primary)
                .padding(.top, 10)
                .padding(.bottom, 2)

        case let .h2(text):
            Text(CSSAndMarkdownParser.renderAttributedString(text, baseFont: .system(size: 20, weight: .bold, design: .rounded), baseFontSize: 20, accentColor: accentColor, classMap: classMap))
                .foregroundStyle(.primary)
                .padding(.top, 8)
                .padding(.bottom, 2)

        case let .h3(text):
            VStack(alignment: .leading, spacing: 4) {
                Text(CSSAndMarkdownParser.renderAttributedString(text, baseFont: .system(size: 16, weight: .semibold, design: .rounded), baseFontSize: 16, accentColor: accentColor, classMap: classMap))
                    .foregroundStyle(.primary)
            }
            .padding(.top, 6)
            .padding(.bottom, 2)

        case let .bullet(text, indent):
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(accentColor)
                    .frame(width: 5, height: 5)
                    .padding(.top, 7)

                Text(CSSAndMarkdownParser.renderAttributedString(text, baseFont: baseFont, baseFontSize: 13, accentColor: accentColor, classMap: classMap))
                    .lineSpacing(lineSpacing)
                    .foregroundStyle(.primary)
            }
            .padding(.leading, CGFloat(indent * 16))
            .padding(.vertical, 1)

        case let .numbered(number, text):
            HStack(alignment: .top, spacing: 8) {
                Text("\(number).")
                    .font(.system(.subheadline, design: .monospaced).bold())
                    .foregroundStyle(accentColor)
                    .frame(minWidth: 20, alignment: .trailing)

                Text(CSSAndMarkdownParser.renderAttributedString(text, baseFont: baseFont, baseFontSize: 13, accentColor: accentColor, classMap: classMap))
                    .lineSpacing(lineSpacing)
                    .foregroundStyle(.primary)
            }
            .padding(.vertical, 1)

        case let .blockquote(text):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(accentColor.opacity(0.8))
                    .frame(width: 3.5)

                Text(CSSAndMarkdownParser.renderAttributedString(text, baseFont: baseFont.italic(), baseFontSize: 13, accentColor: accentColor, classMap: classMap))
                    .foregroundStyle(.secondary)
                    .lineSpacing(lineSpacing)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))

        case let .codeBlock(code, lang):
            VStack(alignment: .leading, spacing: 6) {
                if let lang, !lang.isEmpty {
                    HStack {
                        Text(lang.uppercased())
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(code, forType: .string)
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                }

                ScrollView(.horizontal, showsIndicators: true) {
                    Text(code)
                        .font(.system(.caption, design: .monospaced))
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.8), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
            )

        case .divider:
            Divider()
                .padding(.vertical, 6)

        case let .paragraph(text):
            Text(CSSAndMarkdownParser.renderAttributedString(text, baseFont: baseFont, baseFontSize: 13, accentColor: accentColor, classMap: classMap))
                .lineSpacing(lineSpacing)
                .foregroundStyle(.primary)
        }
    }
}
