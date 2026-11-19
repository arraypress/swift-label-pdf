//
//  FittingTests.swift
//  LabelPDFTests
//
//  Created by David Sherlock on 2026.
//
//  Long addresses onto small labels, and nothing lost on the way.
//
//  The rule: text is never cut to make it fit. It shrinks, then wraps, and when a label
//  still cannot hold it, it is printed whole and a warning says so. Asserted by rendering
//  the PDF and reading the text back out of it with PDFKit — the reader the sheet meets
//  first — rather than by trusting the layout arithmetic to have reached the page.
//

import PDFKit
import TextPDF
import XCTest
@testable import LabelPDF

final class FittingTests: XCTestCase {

    // MARK: Helpers

    /// Everything the rendered sheet says, whitespace taken out: PDF text extraction inserts
    /// its own spacing, and a wrapped line is still the line.
    private func pageText(_ pdf: TextPDF.Document) throws -> String {
        let document = try XCTUnwrap(PDFDocument(data: pdf.render()), "the file did not parse")
        return (0..<document.pageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined()
            .filter { !$0.isWhitespace }
    }

    private func squeezed(_ text: String) -> String { text.filter { !$0.isWhitespace } }

    private let longAddress = LabelContent(lines: [
        "Professor Bartholomew Montgomery-Fitzwilliam III",
        "Department of Computational Linguistics and Phonetics",
        "Flat 14B, Riverside Court, 1278 Upper Thames Embankment Road",
        "Kingston upon Thames, Greater London KT1 2AB, United Kingdom",
    ])

    // MARK: Nothing is cut

    /// The headline: long addresses on the smallest address stock come back whole.
    func testLongAddressesSurviveOnEveryAddressStock() throws {
        for sheet in [Sheets.l7160, Sheets.l7163, Sheets.avery5160, Sheets.l7651] {
            let labels = Array(repeating: longAddress, count: 3)
            let pdf = try LabelRenderer.render(labels, on: sheet)
            let page = try pageText(pdf)

            for line in longAddress.lines {
                XCTAssertTrue(page.contains(squeezed(line)), "\(sheet.code) lost \"\(line)\"")
            }
            XCTAssertFalse(page.contains("..."), "\(sheet.code) shortened something")
        }
    }

    /// A long address on standard stock fits once wrapped, so there is nothing to warn about.
    func testALongAddressThatFitsWrappedRaisesNoWarning() throws {
        let pdf = try LabelRenderer.render([longAddress], on: Sheets.l7160)
        XCTAssertEqual(LabelRenderer.warnings([longAddress], on: Sheets.l7160, verifying: pdf), [])
    }

    /// A URL is one unbroken word. It wraps mid-word rather than running over the die cut.
    func testAnUnbrokenURLWrapsAndSurvives() throws {
        let url = "https://example.com/orders/2026/11/abcdefghijklmnopqrstuvwxyz0123456789"
        let content = LabelContent(lines: ["Order", url])
        let pdf = try LabelRenderer.render([content], on: Sheets.l7160)

        XCTAssertGreaterThan(pdf.drawnText.count, 2, "the URL should have wrapped")
        XCTAssertTrue(try pageText(pdf).contains(url))
        XCTAssertEqual(LabelRenderer.warnings([content], on: Sheets.l7160, verifying: pdf), [])
    }

    // MARK: Shrink, then wrap

    /// A line a little too long at twelve points is set smaller, on one line of its own.
    func testShrinkingComesBeforeWrapping() {
        let pdf = TextPDF.Document(width: 595, height: 842, margin: 0)
        let line = "12 Example Street, Bangkok 10110"
        let width = pdf.width(of: line, size: 9, font: .helveticaBold)
        let setting = LabelRenderer.fit([line], width: width, height: 100,
                                        style: .default, on: pdf)

        XCTAssertTrue(setting.fits)
        XCTAssertEqual(setting.size, 9)
        XCTAssertEqual(setting.lines.map(\.text), [line], "it shrank rather than wrapped")
    }

    /// Too long for one line even at the floor: wrapped, at the largest size that fits.
    func testWrappingWhenShrinkingIsNotEnough() {
        let pdf = TextPDF.Document(width: 595, height: 842, margin: 0)
        let line = String(repeating: "word ", count: 30).trimmingCharacters(in: .whitespaces)
        let setting = LabelRenderer.fit([line], width: 120, height: 200,
                                        style: .default, on: pdf)

        XCTAssertTrue(setting.fits)
        XCTAssertGreaterThan(setting.lines.count, 1)
        XCTAssertGreaterThan(setting.size, LabelRenderer.minimumSize,
                             "a wrapped label still takes the largest size that fits")
        XCTAssertEqual(setting.lines.map(\.text).joined(separator: " "), line)
    }

    /// Six points is the floor, wrapped or not.
    func testTheFittedSizeHasAFloor() {
        let pdf = TextPDF.Document(width: 595, height: 842, margin: 0)
        let many = (0 ..< 30).map { "Line \($0)" }
        let setting = LabelRenderer.fit(many, width: 40, height: 30, style: .default, on: pdf)

        XCTAssertEqual(setting.size, LabelRenderer.minimumSize)
        XCTAssertFalse(setting.fits)
        XCTAssertEqual(setting.lines.map(\.text), many, "every line is still set")
    }

    /// A wrapped first line stays bold all the way through; the rest stay regular.
    func testAWrappedFirstLineIsBoldThroughout() {
        let pdf = TextPDF.Document(width: 595, height: 842, margin: 0)
        let first = String(repeating: "Name ", count: 20).trimmingCharacters(in: .whitespaces)
        let setting = LabelRenderer.fit([first, "City"], width: 80, height: 400,
                                        style: .default, on: pdf)

        let bold = setting.lines.filter(\.bold).map(\.text)
        XCTAssertGreaterThan(bold.count, 1)
        XCTAssertEqual(bold.joined(separator: " "), first)
        XCTAssertEqual(setting.lines.last, .init(text: "City", bold: false))
    }

    // MARK: When it cannot fit

    /// More text than the smallest stock can hold at six points, even wrapped: printed whole,
    /// hanging from the top so the first line stays on the label, and reported.
    func testTextThatCannotFitIsPrintedWholeAndReported() throws {
        let essay = LabelContent(lines: (1 ... 12).map { "Line \($0) of a label with far too much on it" })
        let pdf = try LabelRenderer.render([essay], on: Sheets.l7651)
        let page = try pageText(pdf)

        for line in essay.lines {
            XCTAssertTrue(page.contains(squeezed(line)), "lost \"\(line)\"")
        }

        let warnings = LabelRenderer.warnings([essay], on: Sheets.l7651)
        XCTAssertEqual(warnings.count, 1)
        XCTAssertTrue(warnings[0].hasPrefix("Label 1 (Line 1 of a label"))
        XCTAssertTrue(warnings[0].contains("does not fit L7651"))
        XCTAssertTrue(warnings[0].contains("6 pt"))
        XCTAssertEqual(LabelRenderer.warnings([essay], on: Sheets.l7651, verifying: pdf), warnings)
    }

    /// Hung from the top, the first line is inside the label; centred, it would sit above it.
    func testOverflowingTextKeepsItsFirstLineOnTheLabel() throws {
        let essay = LabelContent(lines: (1 ... 12).map { "Line \($0) of a label with far too much on it" })
        let pdf = try LabelRenderer.render([essay], on: Sheets.l7651)
        let slot = Imposition.slot(at: 0, on: Sheets.l7651)
        let document = try XCTUnwrap(PDFDocument(data: pdf.render()))
        let page = try XCTUnwrap(document.page(at: 0))
        let selection = try XCTUnwrap(page.selection(for: CGRect(
            x: slot.x, y: slot.y, width: slot.width, height: slot.height)))
        XCTAssertTrue(squeezed(selection.string ?? "").contains("Line1ofalabel"),
                      "the first line ran off the top of its label")
    }

    /// An explicit size that cannot fit is honoured, wrapped, and reported as asked for.
    func testAnExplicitSizeThatCannotFitIsReported() throws {
        let content = LabelContent(lines: ["Katherine Johnson", "NASA Langley Research Center"])
        let style = LabelStyle(fontSize: 24)
        let pdf = try LabelRenderer.render([content], on: Sheets.l7651, style: style)

        XCTAssertTrue(try pageText(pdf).contains("NASALangleyResearchCenter"))
        let warnings = LabelRenderer.warnings([content], on: Sheets.l7651, style: style)
        XCTAssertEqual(warnings.count, 1)
        XCTAssertTrue(warnings[0].contains("at the 24 pt asked for"))
    }

    // MARK: Checking the drawn page

    /// A line that did not reach the page is caught, whatever the layout believed.
    func testADroppedLineIsCaughtOnTheDrawnPage() throws {
        let short = LabelContent(lines: ["Ada Lovelace", "London"])
        let drawn = try LabelRenderer.render([LabelContent(lines: ["Ada Lovelace"])],
                                             on: Sheets.l7160)
        XCTAssertEqual(LabelRenderer.warnings([short], on: Sheets.l7160, verifying: drawn),
                       ["Label 1 (Ada Lovelace): \"London\" did not reach the page."])
    }

    /// A line cut with an ellipsis is not the line.
    func testAShortenedLineIsCaughtOnTheDrawnPage() {
        let content = LabelContent(lines: ["12 Example Street"])
        let drawn = TextPDF.Document(width: 595, height: 842, margin: 0)
        drawn.textAt("12 Example St...", x: 10, y: 400, size: 9)
        XCTAssertEqual(LabelRenderer.warnings([content], on: Sheets.l7160, verifying: drawn),
                       ["Label 1 (12 Example Street): \"12 Example Street\" did not reach the page."])
    }

    /// Lines are found in order, so one label's text cannot vouch for another's.
    func testOneLabelCannotVouchForAnother() throws {
        let labels = [LabelContent(lines: ["Ada", "London"]), LabelContent(lines: ["Grace", "London"])]
        let drawn = try LabelRenderer.render([labels[0], LabelContent(lines: ["Grace"])],
                                             on: Sheets.l7160)
        XCTAssertEqual(LabelRenderer.warnings(labels, on: Sheets.l7160, verifying: drawn),
                       ["Label 2 (Grace): \"London\" did not reach the page."])
    }

    /// Characters no font here can draw print as `?`, and that is said, not left to be found.
    func testQuestionMarksAreReported() throws {
        let content = LabelContent(lines: ["Москва", "Россия"])
        let pdf = try LabelRenderer.render([content], on: Sheets.l7160)
        let warnings = LabelRenderer.warnings([content], on: Sheets.l7160, verifying: pdf)
        XCTAssertEqual(warnings.count, 2)
        XCTAssertTrue(warnings.allSatisfy { $0.contains("print as ?") })
    }

    /// With a font that covers them, the same lines print as written, and nothing is said.
    func testAFontFixesTheQuestionMarks() throws {
        let path = "/System/Library/Fonts/Supplemental/Arial Unicode.ttf"
        try XCTSkipUnless(FileManager.default.fileExists(atPath: path), "Arial Unicode is not installed")
        let font = try EmbeddedFont.load(URL(fileURLWithPath: path))

        let content = LabelContent(lines: ["Анна Каренина", "ул. Тверская, д. 12, кв. 345",
                                           "Москва 125009, Россия"])
        let pdf = try LabelRenderer.render([content], on: Sheets.l7160, font: font)
        let page = try pageText(pdf)
        for line in content.lines {
            XCTAssertTrue(page.contains(squeezed(line)), "lost \"\(line)\"")
        }
        XCTAssertEqual(LabelRenderer.warnings([content], on: Sheets.l7160, font: font,
                                              verifying: pdf), [])
    }

    // MARK: Codes and images

    func testARefusedBarcodeIsReported() {
        let content = LabelContent(lines: ["Sea Salt & Bergamot"], barcode: "NOT-DIGITS")
        XCTAssertEqual(LabelRenderer.warnings([content], on: Sheets.l7165),
                       ["Label 1 (Sea Salt & Bergamot): the barcode \"NOT-DIGITS\" was not drawn: "
                        + "EAN-13 takes digits only."])
    }

    func testABarcodeTooBigForTheLabelIsReported() {
        let tiny = LabelSheet.millimetres(code: "TINY", purpose: "test", page: Sheets.a4,
                                          columns: 2, rows: 2, label: (20, 8),
                                          margin: (left: 10, top: 10), gap: (x: 2, y: 2))
        let content = LabelContent(lines: ["£24.00"], barcode: "5012345678900")
        let warnings = LabelRenderer.warnings([content], on: tiny)
        XCTAssertTrue(warnings.contains("Label 1 (£24.00): the barcode \"5012345678900\" was not "
                                        + "drawn: the label is too small for one that would scan."),
                      "\(warnings)")
    }

    func testAQRCodeThatCannotBeEncodedIsReported() {
        let content = LabelContent(lines: ["Asset"], qr: String(repeating: "x", count: 5000))
        let warnings = LabelRenderer.warnings([content], on: Sheets.l7165)
        XCTAssertEqual(warnings.count, 1)
        XCTAssertTrue(warnings[0].contains("QR code"))
    }

    func testAnUnreadableImageIsReported() {
        let content = LabelContent(lines: ["Asset"], image: "/nonexistent/logo.png")
        XCTAssertEqual(LabelRenderer.warnings([content], on: Sheets.l7165),
                       ["Label 1 (Asset): the image at /nonexistent/logo.png could not be read, "
                        + "so it was not drawn."])
    }

    func testNothingToWarnAboutIsEmpty() throws {
        let content = LabelContent(lines: ["Sea Salt & Bergamot", "220g"],
                                   qr: "https://example.com/l/1", barcode: "5012345678900")
        let pdf = try LabelRenderer.render([content], on: Sheets.l7165)
        XCTAssertEqual(LabelRenderer.warnings([content], on: Sheets.l7165, verifying: pdf), [])
    }

    /// A run that would be refused outright has nothing to warn about — render says why.
    func testARefusedRunHasNoWarnings() {
        XCTAssertEqual(LabelRenderer.warnings([], on: Sheets.l7160), [])
    }
}
