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
}
