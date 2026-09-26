import AppKit
import SwiftUI

public enum MarkdownCalloutType: String, Equatable, Sendable, CaseIterable {
    case note = "NOTE"
    case tip = "TIP"
    case important = "IMPORTANT"
    case warning = "WARNING"
    case caution = "CAUTION"

    public var title: String {
        switch self {
        case .note: "Note"
        case .tip: "Tip"
        case .important: "Important"
        case .warning: "Warning"
        case .caution: "Caution"
        }
    }

    public var iconName: String {
        switch self {
        case .note: "info.circle.fill"
        case .tip: "lightbulb.fill"
        case .important: "exclamationmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .caution: "hand.raised.fill"
        }
    }

    public var tintColor: Color {
        switch self {
        case .note: .blue
        case .tip: .green
        case .important: .purple
        case .warning: .orange
        case .caution: .red
        }
    }
}

public enum MarkdownBlock: Equatable, Identifiable {
    case h1(String)
    case h2(String)
    case h3(String)
    case bullet(text: String, indent: Int)
    case taskItem(checked: Bool, text: String, indent: Int)
    case numbered(number: Int, text: String)
    case codeBlock(code: String, language: String?)
    case blockquote(String)
    case callout(type: MarkdownCalloutType, title: String?, content: String)
    case divider
    case table(headers: [String], rows: [[String]])
    case paragraph(String)

    public var id: String {
        switch self {
        case let .h1(s): "h1-\(s)"
        case let .h2(s): "h2-\(s)"
        case let .h3(s): "h3-\(s)"
        case let .bullet(text, indent): "b-\(indent)-\(text)"
        case let .taskItem(checked, text, indent): "task-\(checked)-\(indent)-\(text)"
        case let .numbered(num, text): "n-\(num)-\(text)"
        case let .codeBlock(code, lang): "code-\(lang ?? "")-\(code.hashValue)"
        case let .blockquote(s): "quote-\(s)"
        case let .callout(type, title, content): "callout-\(type.rawValue)-\(title ?? "")-\(content.hashValue)"
        case .divider: "divider-\(UUID().uuidString)"
        case let .table(headers, rows): "table-\(headers.joined(separator: "-"))-\(rows.count)"
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

            // Blockquote & GitHub Callouts (> ...)
            if trimmed.hasPrefix(">") {
                let isPrefixedSpace = trimmed.hasPrefix("> ")
                let firstLineContent = trimmed == ">" ? "" : String(trimmed.dropFirst(isPrefixedSpace ? 2 : 1)).trimmingCharacters(in: .whitespaces)
                if let calloutHeader = parseCalloutType(from: firstLineContent) {
                    var calloutLines: [String] = []
                    i += 1
                    while i < lines.count {
                        let nextLine = lines[i]
                        let nextTrimmed = nextLine.trimmingCharacters(in: .whitespaces)
                        if nextTrimmed.hasPrefix("> ") {
                            calloutLines.append(String(nextTrimmed.dropFirst(2)))
                            i += 1
                        } else if nextTrimmed == ">" {
                            calloutLines.append("")
                            i += 1
                        } else if nextTrimmed.isEmpty || nextTrimmed.hasPrefix("#") || nextTrimmed.hasPrefix("```") || nextTrimmed == "---" {
                            break
                        } else {
                            calloutLines.append(nextTrimmed)
                            i += 1
                        }
                    }
                    blocks.append(.callout(type: calloutHeader.type, title: calloutHeader.customTitle, content: calloutLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)))
                    continue
                }

                // Standard Blockquote
                var quoteLines = [firstLineContent]
                i += 1
                while i < lines.count {
                    let nextTrimmed = lines[i].trimmingCharacters(in: .whitespaces)
                    if nextTrimmed.hasPrefix("> ") {
                        quoteLines.append(String(nextTrimmed.dropFirst(2)))
                        i += 1
                    } else if nextTrimmed == ">" {
                        quoteLines.append("")
                        i += 1
                    } else if nextTrimmed.isEmpty || nextTrimmed.hasPrefix("#") || nextTrimmed.hasPrefix("```") || nextTrimmed == "---" {
                        break
                    } else {
                        quoteLines.append(nextTrimmed)
                        i += 1
                    }
                }
                blocks.append(.blockquote(quoteLines.joined(separator: " ")))
                continue
            }

            // Task List (- [ ] or - [x] or * [ ] or * [x])
            if let task = parseTaskListItem(trimmed, rawLine: line) {
                blocks.append(.taskItem(checked: task.checked, text: task.text, indent: task.indent))
                i += 1
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

            // Markdown Table
            if trimmed.contains("|"), i + 1 < lines.count, isTableDelimiterRow(lines[i + 1]) {
                let headers = parseTableRowCells(trimmed)
                i += 2 // skip header and delimiter row
                var rows: [[String]] = []
                while i < lines.count {
                    let rLine = lines[i]
                    let rTrimmed = rLine.trimmingCharacters(in: .whitespaces)
                    if rTrimmed.isEmpty || !rTrimmed.contains("|") || rTrimmed.hasPrefix("#") || rTrimmed.hasPrefix("```") || rTrimmed == "---" {
                        break
                    }
                    let cells = parseTableRowCells(rTrimmed)
                    var normalizedCells = cells
                    if normalizedCells.count < headers.count {
                        normalizedCells.append(contentsOf: Array(repeating: "", count: headers.count - normalizedCells.count))
                    } else if normalizedCells.count > headers.count {
                        normalizedCells = Array(normalizedCells.prefix(headers.count))
                    }
                    rows.append(normalizedCells)
                    i += 1
                }
                blocks.append(.table(headers: headers, rows: rows))
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
                    nextTrimmed.hasPrefix(">") ||
                    nextTrimmed == "---" ||
                    (nextTrimmed.contains("|") && i + 1 < lines.count && isTableDelimiterRow(lines[i + 1])) ||
                    parseNumberedListItem(nextTrimmed) != nil ||
                    parseTaskListItem(nextTrimmed, rawLine: nextLine) != nil {
                    break
                }
                paragraphLines.append(nextTrimmed)
                i += 1
            }
            blocks.append(.paragraph(paragraphLines.joined(separator: " ")))
        }

        return blocks
    }

    private static func isTableDelimiterRow(_ line: String) -> Bool {
        let cleaned = line.trimmingCharacters(in: .whitespaces)
        guard cleaned.contains("-") else { return false }
        let cells = cleaned.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        guard !cells.isEmpty else { return false }
        for cell in cells {
            guard !cell.isEmpty else { continue }
            let allowed = CharacterSet(charactersIn: "-: ")
            if cell.unicodeScalars.contains(where: { !allowed.contains($0) }) {
                return false
            }
            if !cell.contains("-") {
                return false
            }
        }
        return true
    }

    private static func parseTableRowCells(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") {
            trimmed.removeFirst()
        }
        if trimmed.hasSuffix("|") {
            trimmed.removeLast()
        }
        return trimmed.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func parseNumberedListItem(_ line: String) -> (num: Int, text: String)? {
        guard let dotIndex = line.firstIndex(of: ".") else { return nil }
        let prefix = line[..<dotIndex]
        guard let number = Int(prefix), number > 0, number < 1000 else { return nil }
        let remainder = line[line.index(after: dotIndex)...].trimmingCharacters(in: .whitespaces)
        return (number, remainder)
    }

    private static func parseCalloutType(from line: String) -> (type: MarkdownCalloutType, customTitle: String?)? {
        guard line.hasPrefix("[!") else { return nil }
        guard let closeBracket = line.firstIndex(of: "]") else { return nil }
        let keyword = String(line[line.index(line.startIndex, offsetBy: 2)..<closeBracket]).uppercased().trimmingCharacters(in: .whitespaces)
        guard let type = MarkdownCalloutType(rawValue: keyword) else { return nil }
        let remainder = String(line[line.index(after: closeBracket)...]).trimmingCharacters(in: .whitespaces)
        return (type, remainder.isEmpty ? nil : remainder)
    }

    private static func parseTaskListItem(_ trimmed: String, rawLine: String) -> (checked: Bool, text: String, indent: Int)? {
        guard trimmed.hasPrefix("- [") || trimmed.hasPrefix("* [") else { return nil }
        let leadingSpaces = rawLine.prefix(while: { $0 == " " || $0 == "\t" }).count
        let indent = leadingSpaces / 2

        if trimmed.hasPrefix("- [ ] ") || trimmed.hasPrefix("* [ ] ") {
            let text = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            return (false, text, indent)
        }
        if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") ||
           trimmed.hasPrefix("* [x] ") || trimmed.hasPrefix("* [X] ") {
            let text = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            return (true, text, indent)
        }
        return nil
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

        case let .taskItem(checked, text, indent):
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: checked ? "checkmark.square.fill" : "square")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(checked ? accentColor : .secondary)
                    .padding(.top, 2)

                Text(CSSAndMarkdownParser.renderAttributedString(text, baseFont: baseFont, baseFontSize: 13, accentColor: accentColor, classMap: classMap))
                    .lineSpacing(lineSpacing)
                    .foregroundStyle(checked ? .secondary : .primary)
                    .strikethrough(checked, color: .secondary.opacity(0.6))
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

        case let .callout(type, customTitle, content):
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: type.iconName)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(type.tintColor)
                    Text(customTitle ?? type.title)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(type.tintColor)
                }
                if !content.isEmpty {
                    Text(CSSAndMarkdownParser.renderAttributedString(content, baseFont: baseFont, baseFontSize: 12.5, accentColor: accentColor, classMap: classMap))
                        .foregroundStyle(.primary)
                        .lineSpacing(lineSpacing)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(type.tintColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(type.tintColor.opacity(0.25), lineWidth: 1)
            )

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

        case let .table(headers, rows):
            ScrollView(.horizontal, showsIndicators: true) {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    if !headers.isEmpty {
                        GridRow {
                            ForEach(headers.indices, id: \.self) { colIdx in
                                Text(CSSAndMarkdownParser.renderAttributedString(
                                    headers[colIdx],
                                    baseFont: .system(size: 12, weight: .bold, design: .rounded),
                                    baseFontSize: 12,
                                    accentColor: accentColor,
                                    classMap: classMap
                                ))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                            }
                        }
                    }

                    ForEach(rows.indices, id: \.self) { rowIdx in
                        GridRow {
                            ForEach(rows[rowIdx].indices, id: \.self) { colIdx in
                                Text(CSSAndMarkdownParser.renderAttributedString(
                                    rows[rowIdx][colIdx],
                                    baseFont: baseFont,
                                    baseFontSize: 12,
                                    accentColor: accentColor,
                                    classMap: classMap
                                ))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        if rowIdx < rows.count - 1 {
                            Divider()
                                .opacity(0.35)
                        }
                    }
                }
                .padding(8)
            }
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
            )
            .padding(.vertical, 4)

        case let .paragraph(text):
            Text(CSSAndMarkdownParser.renderAttributedString(text, baseFont: baseFont, baseFontSize: 13, accentColor: accentColor, classMap: classMap))
                .lineSpacing(lineSpacing)
                .foregroundStyle(.primary)
        }
    }
}
