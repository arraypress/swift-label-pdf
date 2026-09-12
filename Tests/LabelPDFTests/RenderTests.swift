//
//  RenderTests.swift
//  LabelPDFTests
//
//  Created by David Sherlock on 2026.
//
//  Content onto labels, and the refusals.
//

import TextPDF
import XCTest
@testable import LabelPDF

private typealias TextPDFDocument = TextPDF.Document

final class RenderTests: XCTestCase {

    private let address = LabelContent(lines: ["Freshly Squeezed", "12 Example Street",
                                               "Bangkok 10110"])

    // MARK: Producing something

    func testAFullSheetRendersOnePage() throws {
        let pdf = try LabelRenderer.render(Array(repeating: address, count: 21), on: Sheets.l7160)
        XCTAssertEqual(pdf.pageCount(), 1)
        XCTAssertGreaterThan(try pdf.render().count, 1000)
    }

    func testARunLongerThanASheetBreaksToTheNextPage() throws {
        let pdf = try LabelRenderer.render(Array(repeating: address, count: 22), on: Sheets.l7160)
        XCTAssertEqual(pdf.pageCount(), 2)
    }

    /// The page is the stock's size, not A4 by coincidence, and it carries no margin of its
    /// own — every position comes from the geometry.
    func testThePageIsTheStockSize() throws {
        let pdf = try LabelRenderer.render([address], on: Sheets.avery5160)
        XCTAssertEqual(pdf.width(), 8.5 * pointsPerInch, accuracy: 0.01)
        XCTAssertEqual(pdf.height(), 11 * pointsPerInch, accuracy: 0.01)
    }

    func testTextReachesThePage() throws {
        let pdf = try LabelRenderer.render([address], on: Sheets.l7160)
        let bytes = try pdf.render()
        XCTAssertGreaterThan(bytes.count, 500)
        XCTAssertFalse(pdf.drawnText.isEmpty)
        XCTAssertTrue(pdf.drawnText.contains { $0.contains("Freshly") })
    }

    func testAQRCodeIsDrawn() throws {
        let plain = try LabelRenderer.render([address], on: Sheets.l7165).render().count
        let coded = try LabelRenderer.render(
            [LabelContent(lines: address.lines, qr: "https://example.com/listing/1")],
            on: Sheets.l7165).render().count
        XCTAssertGreaterThan(coded, plain + 200, "a QR is several hundred squares of path")
    }

    /// The alignment proof: printed on plain paper, held against the real stock.
    func testOutlineAddsMarksWithoutCoveringTheLabel() throws {
        let plain = try LabelRenderer.render([address], on: Sheets.l7160,
                                             style: LabelStyle(outline: false)).render().count
        let outlined = try LabelRenderer.render([address], on: Sheets.l7160,
                                                style: LabelStyle(outline: true)).render().count
        XCTAssertGreaterThan(outlined, plain)
    }

    // MARK: Refusals

    func testNothingToPrintIsRefused() {
        XCTAssertThrowsError(try LabelRenderer.render([], on: Sheets.l7160)) {
            XCTAssertEqual($0 as? LabelError, .nothingToPrint)
        }
        // Entries with no content at all are dropped, and a run of only those is empty.
        XCTAssertThrowsError(try LabelRenderer.render([LabelContent(lines: [])], on: Sheets.l7160)) {
            XCTAssertEqual($0 as? LabelError, .nothingToPrint)
        }
    }

    func testABrokenGeometryIsRefusedBeforeDrawing() {
        let broken = LabelSheet.millimetres(
            code: "BROKEN", purpose: "test", page: Sheets.a4,
            columns: 9, rows: 7, label: (63.5, 38.1),
            margin: (left: 7.2, top: 15.1), gap: (x: 2.5, y: 0))
        XCTAssertThrowsError(try LabelRenderer.render([address], on: broken)) {
            XCTAssertEqual($0 as? LabelError, .geometryDoesNotFit("BROKEN"))
        }
    }

    func testSkippingPastASheetIsRefused() {
        XCTAssertThrowsError(try LabelRenderer.render([address], on: Sheets.l7160, startAt: 21)) {
            XCTAssertEqual($0 as? LabelError, .startsPastTheSheet(startAt: 21, perSheet: 21))
        }
        XCTAssertNoThrow(try LabelRenderer.render([address], on: Sheets.l7160, startAt: 20))
    }

    // MARK: Content

    func testBlankLinesAreDropped() {
        let content = LabelContent(lines: ["Name", "", "   ", "City"])
        XCTAssertEqual(content.lines, ["Name", "City"])
    }

    /// A mailing list with a URL column should not set the URL across the middle of every
    /// label in nine-point type.
    func testQRAndImageColumnsAreNotPrintedAsText() {
        let content = LabelContent.from(
            row: ["name": "Ada", "city": "London", "qr": "https://example.com", "logo": "/tmp/x.png"],
            order: ["name", "city", "qr", "logo"])

        XCTAssertEqual(content.lines, ["Ada", "London"])
        XCTAssertEqual(content.qr, "https://example.com")
        XCTAssertEqual(content.image, "/tmp/x.png")
    }

    func testColumnOrderIsLineOrder() {
        let content = LabelContent.from(row: ["a": "1", "b": "2", "c": "3"], order: ["c", "a", "b"])
        XCTAssertEqual(content.lines, ["3", "1", "2"])
    }

    func testEmptyColumnsAreSkippedNotPrintedAsGaps() {
        let content = LabelContent.from(row: ["a": "1", "b": "", "c": "3"], order: ["a", "b", "c"])
        XCTAssertEqual(content.lines, ["1", "3"], "an empty column leaves no blank line")
    }

    // MARK: Fitting

    /// Text too long for the label is shortened rather than run over the die cut.
    func testLongTextIsShortenedToTheLabel() throws {
        let long = LabelContent(lines: [String(repeating: "Wide ", count: 40)])
        let pdf = try LabelRenderer.render([long], on: Sheets.l7651)   // 38 × 21 mm, the smallest
        let drawn = try XCTUnwrap(pdf.drawnText.first)
        XCTAssertLessThan(drawn.count, long.lines[0].count, "it must be truncated to fit")
    }

    /// Six points is the floor — smaller is not a label, it is a rumour.
    func testTheFittedSizeHasAFloor() throws {
        let pdf = TextPDFDocumentForTests()
        let many = (0 ..< 30).map { "Line \($0)" }
        let size = LabelRenderer.fittingSize(many, width: 40, height: 30, on: pdf)
        XCTAssertGreaterThanOrEqual(size, 6)
        XCTAssertLessThanOrEqual(size, 12)
    }

    func testAnExplicitSizeIsHonoured() throws {
        let pdf = try LabelRenderer.render([address], on: Sheets.l7160,
                                           style: LabelStyle(fontSize: 7))
        XCTAssertGreaterThan(try pdf.render().count, 500)
    }

    /// Padding cannot eat the whole label, however large it is asked to be.
    func testAbsurdPaddingDoesNotSwallowTheLabel() throws {
        let pdf = try LabelRenderer.render([address], on: Sheets.l7651,
                                           style: LabelStyle(padding: 500))
        XCTAssertFalse(pdf.drawnText.isEmpty, "something should still print")
    }
}

/// A bare document for measuring, so the size fitter can be tested without a sheet.
private func TextPDFDocumentForTests() -> TextPDFDocument {
    TextPDFDocument(width: 595, height: 842, margin: 0, fontSize: 9, leading: 11)
}
