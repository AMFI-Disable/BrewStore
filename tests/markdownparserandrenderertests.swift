@testable import BrewStore
import XCTest

final class MarkdownParserAndRendererTests: XCTestCase {
    func testParseHeadings() {
        let md = """
        # Main Header
        ## Secondary Header
        ### Tertiary Subheader
        """
        let blocks = MarkdownParser.parse(md)
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[0], .h1("Main Header"))
        XCTAssertEqual(blocks[1], .h2("Secondary Header"))
        XCTAssertEqual(blocks[2], .h3("Tertiary Subheader"))
    }

    func testParseBulletAndNumberedLists() {
        let md = """
        * Bullet One
        - Bullet Two
        • Bullet Three
          * Indented Bullet

        1. Numbered One
        2. Numbered Two
        """
        let blocks = MarkdownParser.parse(md)
        XCTAssertEqual(blocks.count, 6)
        XCTAssertEqual(blocks[0], .bullet(text: "Bullet One", indent: 0))
        XCTAssertEqual(blocks[1], .bullet(text: "Bullet Two", indent: 0))
        XCTAssertEqual(blocks[2], .bullet(text: "Bullet Three", indent: 0))
        XCTAssertEqual(blocks[3], .bullet(text: "Indented Bullet", indent: 1))
        XCTAssertEqual(blocks[4], .numbered(number: 1, text: "Numbered One"))
        XCTAssertEqual(blocks[5], .numbered(number: 2, text: "Numbered Two"))
    }

    func testParseCodeBlock() {
        let md = """
        Here is some code:
        ```swift
        let x = 42
        print(x)
        ```
        And a conclusion paragraph.
        """
        let blocks = MarkdownParser.parse(md)
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[0], .paragraph("Here is some code:"))
        XCTAssertEqual(blocks[1], .codeBlock(code: "let x = 42\nprint(x)", language: "swift"))
        XCTAssertEqual(blocks[2], .paragraph("And a conclusion paragraph."))
    }

    func testParseBlockquotesAndDividers() {
        let md = """
        > This is a quote
        > continuing on line 2

        ---

        Regular text below
        """
        let blocks = MarkdownParser.parse(md)
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[0], .blockquote("This is a quote continuing on line 2"))
        XCTAssertEqual(blocks[1], .divider)
        XCTAssertEqual(blocks[2], .paragraph("Regular text below"))
    }

    func testParseRealWorldStoryMarkdown() {
        let story = BrewStoreStory.allStories.first!
        let blocks = MarkdownParser.parse(story.bodyMarkdown)
        XCTAssertFalse(blocks.isEmpty)

        // Ensure headers and list items are recognized
        let hasH3 = blocks.contains {
            if case .h3 = $0 {
                return true
            }; return false
        }
        let hasBullets = blocks.contains {
            if case .bullet = $0 {
                return true
            }; return false
        }
        let hasParagraphs = blocks.contains {
            if case .paragraph = $0 {
                return true
            }; return false
        }

        XCTAssertTrue(hasH3, "Story should contain H3 section headers")
        XCTAssertTrue(hasBullets, "Story should contain bullet list items")
        XCTAssertTrue(hasParagraphs, "Story should contain introductory paragraphs")
    }
}
