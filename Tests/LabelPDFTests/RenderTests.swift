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

    /// Centring is done by giving TextPDF a box to centre within. It ignores the alignment
    /// when the box is zero wide — which is its default — so a centred label that merely
    /// shifts x prints left-aligned from the middle and looks like the flag does nothing.
    func testCentredTextIsActuallyCentred() throws {
        let short = LabelContent(lines: ["Hi"])
        let left = try LabelRenderer.render([short], on: Sheets.l7165,
                                            style: LabelStyle(centred: false))
        let centred = try LabelRenderer.render([short], on: Sheets.l7165,
                                               style: LabelStyle(centred: true))

        // A change detector, and worth saying so rather than dressing it up: it proves the
        // flag reaches the drawing and alters it, not that the result is visually centred.
        // What proved that was rendering a sheet of badges and looking at them — which is how
        // the bug was found, since the broken version differed from nothing and looked fine
        // in every unit test.
        XCTAssertNotEqual(try left.render(), try centred.render(),
                          "centring must change where the text lands")
    }

    // MARK: Fitting

    /// Asserted through wrapping, which is observable: at six points the line is set on one
    /// line of its own, at twenty it cannot be and is wrapped — whole either way.
    func testAnExplicitSizeIsHonoured() throws {
        let long = LabelContent(lines: ["Katherine Johnson NASA Langley Research"])
        func drawn(_ size: Double) throws -> [String] {
            try LabelRenderer.render([long], on: Sheets.l7160,
                                     style: LabelStyle(fontSize: size)).drawnText
        }
        XCTAssertEqual(try drawn(6), long.lines, "six points fits the whole line on one line")
        let large = try drawn(20)
        XCTAssertGreaterThan(large.count, 1, "twenty points cannot, so it wraps")
        XCTAssertEqual(large.joined(separator: " "), long.lines[0], "and loses nothing")
    }

    /// Padding cannot eat the whole label, however large it is asked to be.
    func testAbsurdPaddingDoesNotSwallowTheLabel() throws {
        let pdf = try LabelRenderer.render([address], on: Sheets.l7651,
                                           style: LabelStyle(padding: 500))
        XCTAssertFalse(pdf.drawnText.isEmpty, "something should still print")
    }
}

// MARK: - Barcodes

extension RenderTests {

    /// A product label carries a retail code for the till AND often a QR to the listing.
    /// They are not alternatives and go in different places.
    func testABarcodeAndAQRCanBothBeOnOneLabel() throws {
        let content = LabelContent(lines: ["Sea Salt & Bergamot", "220g"],
                                   qr: "https://example.com/l/1",
                                   barcode: "5012345678900")
        let pdf = try LabelRenderer.render([content], on: Sheets.l7165)
        XCTAssertGreaterThan(try pdf.render().count, 2000)
        XCTAssertTrue(pdf.drawnText.contains { $0.contains("Sea Salt") })
        XCTAssertTrue(pdf.drawnText.contains("012345"), "the barcode's own digits are drawn")
    }

    func testBarcodeColumnsAreRecognisedByName() {
        for name in ["barcode", "ean", "upc", "sku"] {
            let content = LabelContent.from(row: ["product": "Candle", name: "5012345678900"],
                                            order: ["product", name])
            XCTAssertEqual(content.barcode, "5012345678900", "\(name) should become a barcode")
            XCTAssertEqual(content.lines, ["Candle"], "\(name) must not print as a line of text")
        }
    }

    /// A label too small for a readable barcode prints the text rather than a smudge.
    func testATinyLabelSkipsTheBarcodeAndStillPrints() throws {
        let content = LabelContent(lines: ["£24.00"], barcode: "5012345678900")
        let pdf = try LabelRenderer.render([content], on: Sheets.l7651)   // 38 × 21 mm
        XCTAssertFalse(pdf.drawnText.isEmpty, "the price still has to print")
    }

    /// A refused barcode must not leave a gap where one would have been.
    func testABadBarcodeLeavesTheLabelOtherwiseIntact() throws {
        let content = LabelContent(lines: ["Sea Salt & Bergamot"], barcode: "NOT-DIGITS")
        let pdf = try LabelRenderer.render([content], on: Sheets.l7165)
        XCTAssertTrue(pdf.drawnText.contains { $0.contains("Sea Salt") })
    }

    func testSymbologyCanBeChosen() throws {
        let content = LabelContent(lines: ["Asset"], barcode: "ASSET-014", symbology: .code128)
        let pdf = try LabelRenderer.render([content], on: Sheets.l7165)
        XCTAssertTrue(pdf.drawnText.contains("ASSET-014"))
    }

    func testContentWithOnlyABarcodeIsNotEmpty() {
        XCTAssertFalse(LabelContent(lines: [], barcode: "5012345678900").isEmpty)
    }
}
