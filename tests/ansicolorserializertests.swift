import SwiftUI
import XCTest
@testable import BrewStore

final class ANSIColorSerializerTests: XCTestCase {

    func testPlainTextParsing() {
        let text = "Hello Homebrew!"
        let segments = ANSIColorSerializer.parse(text)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments.first?.text, "Hello Homebrew!")
        XCTAssertNil(segments.first?.foregroundColor)
        XCTAssertFalse(segments.first?.isBold ?? true)
    }

    func testSingleForegroundColor() {
        let text = "\u{001B}[32m==> Installing package\u{001B}[0m"
        let segments = ANSIColorSerializer.parse(text)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments.first?.text, "==> Installing package")
        XCTAssertEqual(segments.first?.foregroundColor, .green)
        XCTAssertFalse(segments.first?.isBold ?? true)
    }

    func testBoldAndColorCombination() {
        let text = "\u{001B}[1;31mError: Fatal installation failure\u{001B}[0m normal text"
        let segments = ANSIColorSerializer.parse(text)
        XCTAssertEqual(segments.count, 2)

        let errorSegment = segments[0]
        XCTAssertEqual(errorSegment.text, "Error: Fatal installation failure")
        XCTAssertEqual(errorSegment.foregroundColor, .red)
        XCTAssertTrue(errorSegment.isBold)

        let normalSegment = segments[1]
        XCTAssertEqual(normalSegment.text, " normal text")
        XCTAssertNil(normalSegment.foregroundColor)
        XCTAssertFalse(normalSegment.isBold)
    }

    func testUnderlineAttribute() {
        let text = "\u{001B}[4mhttps://brew.sh\u{001B}[24m link"
        let segments = ANSIColorSerializer.parse(text)
        XCTAssertEqual(segments.count, 2)
        XCTAssertTrue(segments[0].isUnderlined)
        XCTAssertFalse(segments[1].isUnderlined)
    }

    func testStripAnsiCodes() {
        let text = "\u{001B}[32m==>\u{001B}[0m \u{001B}[1mDownloading\u{001B}[0m package"
        let clean = ANSIColorSerializer.stripAnsiCodes(text)
        XCTAssertEqual(clean, "==> Downloading package")
    }

    func testDownloadProgressExtraction() {
        let line1 = "==> Downloading https://ghcr.io/v2/homebrew/core/ripgrep/blobs/sha256:abc ## 65.4%"
        let progress1 = ANSIColorSerializer.extractDownloadProgress(from: line1)
        XCTAssertEqual(progress1, 65.4)

        let line2 = "Downloading bottle [ 100% ]"
        let progress2 = ANSIColorSerializer.extractDownloadProgress(from: line2)
        XCTAssertEqual(progress2, 100.0)

        let line3 = "Regular compilation line without percentage"
        let progress3 = ANSIColorSerializer.extractDownloadProgress(from: line3)
        XCTAssertNil(progress3)
    }

    func testAttributedStringGeneration() {
        let text = "\u{001B}[32mSuccess\u{001B}[0m"
        let attr = ANSIColorSerializer.attributedString(from: text)
        XCTAssertFalse(attr.characters.isEmpty)
        XCTAssertEqual(String(attr.characters), "Success")
    }

    func testParseLinesToAttributedStrings() {
        let multiline = "Line 1\n\u{001B}[33mLine 2\u{001B}[0m\nLine 3"
        let lines = ANSIColorSerializer.parseLinesToAttributedStrings(multiline)
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(String(lines[0].characters), "Line 1")
        XCTAssertEqual(String(lines[1].characters), "Line 2")
        XCTAssertEqual(String(lines[2].characters), "Line 3")
    }
}
