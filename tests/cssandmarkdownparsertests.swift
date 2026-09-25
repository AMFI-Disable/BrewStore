@testable import BrewStore
import SwiftUI
import XCTest

final class CSSAndMarkdownParserTests: XCTestCase {

    // MARK: - HTML Entity Decoding

    func testDecodeHTMLEntities() {
        let input = "Cats &amp; Dogs &lt;3 &quot;Awesome&quot; &#39;Quotes&#39; &copy; 2026"
        let decoded = CSSAndMarkdownParser.decodeHTMLEntities(input)
        XCTAssertEqual(decoded, "Cats & Dogs <3 \"Awesome\" 'Quotes' © 2026")
    }

    func testDecodeNumericHTMLEntities() {
        // &#65; is 'A', &#x42; is 'B'
        let input = "&#65;&#x42;"
        let decoded = CSSAndMarkdownParser.decodeHTMLEntities(input)
        XCTAssertEqual(decoded, "AB")
    }

    // MARK: - CSS Color Parsing

    func testParseCSSColorsHex() {
        // 3-digit hex #f00
        let redColor = CSSAndMarkdownParser.parseCSSColor("#f00")
        XCTAssertNotNil(redColor)

        // 6-digit hex #00ff00
        let greenColor = CSSAndMarkdownParser.parseCSSColor("#00ff00")
        XCTAssertNotNil(greenColor)

        // 8-digit hex #0000ff80
        let blueAlphaColor = CSSAndMarkdownParser.parseCSSColor("#0000ff80")
        XCTAssertNotNil(blueAlphaColor)
    }

    func testParseCSSColorsRGB() {
        let rgbColor = CSSAndMarkdownParser.parseCSSColor("rgb(255, 128, 0)")
        XCTAssertNotNil(rgbColor)

        let rgbaColor = CSSAndMarkdownParser.parseCSSColor("rgba(0, 100, 200, 0.5)")
        XCTAssertNotNil(rgbaColor)
    }

    func testParseCSSColorsNamed() {
        let orange = CSSAndMarkdownParser.parseCSSColor("orange")
        XCTAssertEqual(orange, Color.orange)

        let cyan = CSSAndMarkdownParser.parseCSSColor("cyan")
        XCTAssertEqual(cyan, Color.cyan)

        let invalid = CSSAndMarkdownParser.parseCSSColor("not-a-real-color-12345")
        XCTAssertNil(invalid)
    }

    // MARK: - CSS Inline Style Parsing

    func testParseInlineStyle() {
        let css = "color: #ff3b30; font-weight: bold; background-color: #282c34; font-style: italic; text-decoration: underline; font-family: monospace;"
        let attrs = CSSAndMarkdownParser.parseInlineStyle(css)

        XCTAssertNotNil(attrs.foregroundColor)
        XCTAssertNotNil(attrs.backgroundColor)
        XCTAssertTrue(attrs.isBold)
        XCTAssertTrue(attrs.isItalic)
        XCTAssertTrue(attrs.isUnderlined)
        XCTAssertTrue(attrs.isMonospaced)
    }

    // MARK: - Stylesheet Extraction

    func testExtractStylesheets() {
        let raw = """
        <style>
            .warning { color: red; font-weight: bold; }
            .code-sample { font-family: monospace; }
        </style>
        <span class="warning">Caution!</span>
        """
        let (cleaned, classMap) = CSSAndMarkdownParser.extractStylesheets(from: raw)

        XCTAssertFalse(cleaned.contains("<style>"))
        XCTAssertTrue(cleaned.contains("Caution!"))
        XCTAssertNotNil(classMap["warning"])
        XCTAssertTrue(classMap["warning"]?.isBold == true)
        XCTAssertNotNil(classMap["code-sample"])
        XCTAssertTrue(classMap["code-sample"]?.isMonospaced == true)
    }

    // MARK: - Preprocessing

    func testPreprocessMarkdown() {
        let raw = """
        <!-- Comment to strip -->
        First line<br/>Second line<br>Third line
        <hr/>
        <style>.test { color: blue; }</style>
        Paragraph text</p>
        """
        let (processed, classMap) = CSSAndMarkdownParser.preprocessMarkdown(raw)

        XCTAssertFalse(processed.contains("Comment to strip"))
        XCTAssertFalse(processed.contains("<style>"))
        XCTAssertTrue(processed.contains("First line\nSecond line\nThird line"))
        XCTAssertTrue(processed.contains("\n---\n"))
        XCTAssertNotNil(classMap["test"])
    }

    // MARK: - Rich AttributedString Rendering

    func testRenderAttributedStringWithHTMLAndCSS() {
        let markup = "<span style=\"color: #ff0000; font-weight: bold;\">Important:</span> Run <code>brew update</code> &amp; enjoy!"
        let attrString = CSSAndMarkdownParser.renderAttributedString(markup)

        let plain = String(attrString.characters)
        XCTAssertEqual(plain, "Important: Run brew update & enjoy!")
    }

    func testRenderAttributedStringWithLinks() {
        let markup = "Visit <a href=\"https://brew.sh\">Homebrew Homepage</a> for docs."
        let attrString = CSSAndMarkdownParser.renderAttributedString(markup)

        let plain = String(attrString.characters)
        XCTAssertEqual(plain, "Visit Homebrew Homepage for docs.")

        // Verify link attribute exists
        var foundLink = false
        for run in attrString.runs {
            if let link = run.link {
                XCTAssertEqual(link.absoluteString, "https://brew.sh")
                foundLink = true
            }
        }
        XCTAssertTrue(foundLink)
    }

    func testMarkdownParserWithHTMLTags() {
        let md = """
        ### <span style="color: blue;">Setup Step</span>
        * <span style="font-weight: bold;">Step 1:</span> Install Xcode CLI tools via <code>xcode-select --install</code>.
        * <span style="font-weight: bold;">Step 2:</span> Run <code>brew install git</code>.
        """
        let blocks = MarkdownParser.parse(md)
        XCTAssertEqual(blocks.count, 3)

        if case let .h3(headerText) = blocks[0] {
            XCTAssertTrue(headerText.contains("Setup Step"))
        } else {
            XCTFail("First block should be H3")
        }

        if case let .bullet(b1Text, _) = blocks[1] {
            XCTAssertTrue(b1Text.contains("Step 1"))
        } else {
            XCTFail("Second block should be bullet")
        }
    }

    // MARK: - Markdown Table Parsing

    func testMarkdownTableParsing() {
        let md = """
        # Summary Table

        | Flag | Description | Default |
        | :--- | :--- | :--- |
        | `--all` | Process everything | false |
        | `--force` | Bypass prompts | false |

        End of documentation.
        """
        let blocks = MarkdownParser.parse(md)
        XCTAssertEqual(blocks.count, 3)

        if case let .h1(title) = blocks[0] {
            XCTAssertEqual(title, "Summary Table")
        } else {
            XCTFail("Block 0 should be H1")
        }

        if case let .table(headers, rows) = blocks[1] {
            XCTAssertEqual(headers, ["Flag", "Description", "Default"])
            XCTAssertEqual(rows.count, 2)
            XCTAssertEqual(rows[0], ["`--all`", "Process everything", "false"])
            XCTAssertEqual(rows[1], ["`--force`", "Bypass prompts", "false"])
        } else {
            XCTFail("Block 1 should be table")
        }

        if case let .paragraph(text) = blocks[2] {
            XCTAssertEqual(text, "End of documentation.")
        } else {
            XCTFail("Block 2 should be paragraph")
        }
    }

    func testMarkdownTableWithUnevenCells() {
        let md = """
        | Header 1 | Header 2 | Header 3 |
        |---|---|---|
        | Row 1 Col 1 | Row 1 Col 2 |
        | Row 2 Col 1 | Row 2 Col 2 | Row 2 Col 3 | Extra Col |
        """
        let blocks = MarkdownParser.parse(md)
        XCTAssertEqual(blocks.count, 1)

        if case let .table(headers, rows) = blocks[0] {
            XCTAssertEqual(headers.count, 3)
            XCTAssertEqual(rows.count, 2)
            // Row 1 should be padded with empty string to match header count 3
            XCTAssertEqual(rows[0].count, 3)
            XCTAssertEqual(rows[0][2], "")
            // Row 2 should be truncated to match header count 3
            XCTAssertEqual(rows[1].count, 3)
            XCTAssertEqual(rows[1][2], "Row 2 Col 3")
        } else {
            XCTFail("Block should be table")
        }
    }
}

