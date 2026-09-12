//
//  GeometryTests.swift
//  LabelPDFTests
//
//  Created by David Sherlock on 2026.
//
//  The arithmetic, which is the half that is expensive to get wrong.
//
//  A label that is drawn slightly ugly is a shrug. A run that creeps a millimetre off true
//  with every column is a box of stock in the bin, and it is discovered after the printing,
//  not before. All of it is sums, so all of it is assertable here without rendering anything.
//

import XCTest
@testable import LabelPDF

final class GeometryTests: XCTestCase {

    // MARK: The catalogue

    /// Every published geometry has to be internally consistent with the page it claims.
    /// This is what catches a digit transposed while transcribing a vendor's table.
    func testEveryCataloguedSheetFitsItsPage() {
        for sheet in Sheets.all {
            XCTAssertTrue(sheet.fits, "\(sheet.code) does not fit its page")
        }
    }

    /// Sheet stock is manufactured symmetrically: what is left over on the right should match
    /// the margin on the left. A geometry where they differ by more than a rounding is
    /// usually a wrong pitch, and this catches it where `fits` alone would not.
    func testMarginsAreSymmetricOnStockThatShouldBe() {
        // Herma 4450 is genuinely edge to edge — 3 × 70 mm is exactly 210 mm — so it has no
        // margin to be symmetric with and is excluded deliberately rather than by accident.
        for sheet in Sheets.all where sheet.code != "4450" {
            let right = sheet.pageWidth
                - (sheet.marginLeft + Double(sheet.columns - 1) * sheet.pitchX + sheet.labelWidth)
            XCTAssertEqual(right, sheet.marginLeft, accuracy: 1.0,
                           "\(sheet.code): left margin \(sheet.marginLeft), right slack \(right)")
        }
    }

    func testSheetsAreFoundByCodeHoweverItIsTyped() {
        XCTAssertEqual(Sheets.named("L7160")?.code, "L7160")
        XCTAssertEqual(Sheets.named("l7160")?.code, "L7160")
        XCTAssertEqual(Sheets.named("7160")?.code, "L7160", "the number is what is on the box")
        XCTAssertEqual(Sheets.named(" 5160 ")?.code, "5160")
        XCTAssertNil(Sheets.named("nonsense"))
        XCTAssertNil(Sheets.named(""))
    }

    func testPerSheetMatchesTheGrid() {
        XCTAssertEqual(Sheets.l7160.perSheet, 21)
        XCTAssertEqual(Sheets.l7651.perSheet, 65)
        XCTAssertEqual(Sheets.avery5160.perSheet, 30)
        for sheet in Sheets.all {
            XCTAssertEqual(sheet.perSheet, sheet.columns * sheet.rows, sheet.code)
        }
    }

    /// The conversions are where a units mistake hides.
    func testUnitConversions() {
        XCTAssertEqual(pointsPerMillimetre * 25.4, 72, accuracy: 0.0001)
        XCTAssertEqual(Sheets.l7160.labelWidth / pointsPerMillimetre, 63.5, accuracy: 0.01)
        XCTAssertEqual(Sheets.avery5160.labelWidth / pointsPerInch, 2.625, accuracy: 0.0001)
        XCTAssertEqual(Sheets.l7160.pageWidth, 210 * pointsPerMillimetre, accuracy: 0.01)
        XCTAssertEqual(Sheets.avery5160.pageHeight, 11 * 72, accuracy: 0.01)
    }

    /// Pitch is label plus gap, and the gap is what a naive layout forgets.
    func testPitchIncludesTheGap() {
        let sheet = Sheets.l7160
        XCTAssertEqual(sheet.gapX, 2.5 * pointsPerMillimetre, accuracy: 0.01)
        XCTAssertEqual(sheet.gapY, 0, accuracy: 0.01, "L7160's rows touch")
        XCTAssertEqual(sheet.pitchX, sheet.labelWidth + sheet.gapX, accuracy: 0.0001)
    }

    // MARK: fits

    func testABrokenGeometryIsRejected() {
        let tooWide = LabelSheet.millimetres(
            code: "BROKEN", purpose: "test", page: Sheets.a4,
            columns: 4, rows: 7, label: (63.5, 38.1),
            margin: (left: 7.2, top: 15.1), gap: (x: 2.5, y: 0))
        XCTAssertFalse(tooWide.fits, "four 63.5 mm columns do not fit 210 mm")

        let tooTall = LabelSheet.millimetres(
            code: "BROKEN2", purpose: "test", page: Sheets.a4,
            columns: 3, rows: 9, label: (63.5, 38.1),
            margin: (left: 7.2, top: 15.1), gap: (x: 2.5, y: 0))
        XCTAssertFalse(tooTall.fits)
    }

    func testOverlappingLabelsAreRejected() {
        // A pitch smaller than the label means each label prints over the last.
        let overlapping = LabelSheet(
            code: "OVERLAP", purpose: "test", pageWidth: 595, pageHeight: 842,
            columns: 3, rows: 7, labelWidth: 180, labelHeight: 108,
            marginLeft: 20, marginTop: 40, pitchX: 150, pitchY: 108)
        XCTAssertFalse(overlapping.fits, "a pitch under the label width overlaps")
    }

    func testZeroSizedLabelsAreRejected() {
        let empty = LabelSheet(code: "X", purpose: "t", pageWidth: 595, pageHeight: 842,
                               columns: 1, rows: 1, labelWidth: 0, labelHeight: 0,
                               marginLeft: 0, marginTop: 0, pitchX: 0, pitchY: 0)
        XCTAssertFalse(empty.fits)
    }

    // MARK: Imposition

    /// The first label is at the top LEFT, and in PDF coordinates that is a high y.
    func testTheFirstSlotIsTopLeft() {
        let sheet = Sheets.l7160
        let first = Imposition.slot(at: 0, on: sheet)

        XCTAssertEqual(first.page, 0)
        XCTAssertEqual(first.column, 0)
        XCTAssertEqual(first.row, 0)
        XCTAssertEqual(first.x, sheet.marginLeft, accuracy: 0.001)
        XCTAssertEqual(first.top, sheet.pageHeight - sheet.marginTop, accuracy: 0.001,
                       "the top margin is measured from the top of the page")
    }

    /// Every bug where labels come out mirrored down the sheet is this subtraction.
    func testRowsRunDownThePageNotUp() {
        let sheet = Sheets.l7160
        let firstRow = Imposition.slot(at: 0, on: sheet)
        let secondRow = Imposition.slot(at: sheet.columns, on: sheet)

        XCTAssertEqual(secondRow.row, 1)
        XCTAssertLessThan(secondRow.y, firstRow.y, "the second row is lower on the page")
        XCTAssertEqual(firstRow.y - secondRow.y, sheet.pitchY, accuracy: 0.001)
    }

    func testColumnsRunLeftToRight() {
        let sheet = Sheets.l7160
        let first = Imposition.slot(at: 0, on: sheet)
        let second = Imposition.slot(at: 1, on: sheet)

        XCTAssertEqual(second.column, 1)
        XCTAssertEqual(second.row, 0, "the second label is beside the first, not beneath it")
        XCTAssertEqual(second.x - first.x, sheet.pitchX, accuracy: 0.001)
        XCTAssertEqual(second.y, first.y, accuracy: 0.001)
    }

    /// The whole grid must stay on the paper — the assertion that catches creep.
    func testEverySlotOnASheetStaysOnThePaper() {
        for sheet in Sheets.all {
            for index in 0 ..< sheet.perSheet {
                let slot = Imposition.slot(at: index, on: sheet)
                XCTAssertGreaterThanOrEqual(slot.x, -0.1, "\(sheet.code) slot \(index) off the left")
                XCTAssertLessThanOrEqual(slot.right, sheet.pageWidth + 0.1,
                                         "\(sheet.code) slot \(index) off the right")
                XCTAssertGreaterThanOrEqual(slot.y, -0.1, "\(sheet.code) slot \(index) off the foot")
                XCTAssertLessThanOrEqual(slot.top, sheet.pageHeight + 0.1,
                                         "\(sheet.code) slot \(index) off the head")
                XCTAssertEqual(slot.page, 0)
            }
        }
    }

    func testTheSlotAfterTheLastStartsANewPage() {
        let sheet = Sheets.l7160
        let last = Imposition.slot(at: sheet.perSheet - 1, on: sheet)
        let next = Imposition.slot(at: sheet.perSheet, on: sheet)

        XCTAssertEqual(last.page, 0)
        XCTAssertEqual(next.page, 1)
        XCTAssertEqual(next.column, 0)
        XCTAssertEqual(next.row, 0)
        XCTAssertEqual(next.x, Imposition.slot(at: 0, on: sheet).x, accuracy: 0.001,
                       "a new page starts where the first one did")
    }

    // MARK: Part-used sheets

    /// The feature anyone with a drawer of half-used label sheets actually wants.
    func testStartAtSkipsUsedLabels() {
        let sheet = Sheets.l7160
        let started = Imposition.slot(at: 0, on: sheet, startAt: 3)
        let plain = Imposition.slot(at: 3, on: sheet)

        XCTAssertEqual(started.column, plain.column)
        XCTAssertEqual(started.row, plain.row)
        XCTAssertEqual(started.x, plain.x, accuracy: 0.001)
        XCTAssertEqual(started.y, plain.y, accuracy: 0.001)
    }

    func testStartAtRollsOntoTheNextPage() {
        let sheet = Sheets.l7160
        let slot = Imposition.slot(at: 5, on: sheet, startAt: 20)
        XCTAssertEqual(slot.page, 1, "20 skipped plus 5 is past a 21-label sheet")
    }

    // MARK: Page counts

    func testPageCounts() {
        let sheet = Sheets.l7160     // 21 per sheet
        XCTAssertEqual(Imposition.pages(for: 0, on: sheet), 0)
        XCTAssertEqual(Imposition.pages(for: 1, on: sheet), 1)
        XCTAssertEqual(Imposition.pages(for: 21, on: sheet), 1)
        XCTAssertEqual(Imposition.pages(for: 22, on: sheet), 2)
        XCTAssertEqual(Imposition.pages(for: 42, on: sheet), 2)
        XCTAssertEqual(Imposition.pages(for: 43, on: sheet), 3)
    }

    /// The skipped labels are on the first sheet, and the first sheet still goes through the
    /// printer — so they count toward the page total.
    func testSkippedLabelsCountTowardThePageTotal() {
        let sheet = Sheets.l7160
        XCTAssertEqual(Imposition.pages(for: 10, on: sheet, startAt: 11), 1)
        XCTAssertEqual(Imposition.pages(for: 11, on: sheet, startAt: 11), 2)
        XCTAssertEqual(Imposition.skipped(startAt: 11, on: sheet), 11)
        XCTAssertEqual(Imposition.skipped(startAt: 99, on: sheet), 21, "capped at a sheet")
    }

    func testSlotsForARunAreContiguous() {
        let slots = Imposition.slots(count: 25, on: Sheets.l7160)
        XCTAssertEqual(slots.count, 25)
        XCTAssertEqual(slots.filter { $0.page == 0 }.count, 21)
        XCTAssertEqual(slots.filter { $0.page == 1 }.count, 4)
        XCTAssertEqual(Set(slots.map { "\($0.page)/\($0.row)/\($0.column)" }).count, 25,
                       "no two labels may share a position")
    }

    func testANonPositiveCountProducesNoSlots() {
        XCTAssertTrue(Imposition.slots(count: 0, on: Sheets.l7160).isEmpty)
        XCTAssertTrue(Imposition.slots(count: -5, on: Sheets.l7160).isEmpty)
    }
}
