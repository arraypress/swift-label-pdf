//
//  Imposition.swift
//  LabelPDF
//
//  Created by David Sherlock on 2026.
//
//  Which label goes where.
//
//  All of it is arithmetic and none of it touches a PDF, which is the point: the expensive
//  failure here is a run that creeps off true one column at a time, and that is a sum, not a
//  drawing. It can be asserted to the tenth of a point without rendering anything.
//

import Foundation

/// One label's place on a page.
public struct Slot: Hashable, Sendable {

    /// Which page, counting from zero.
    public let page: Int

    /// Column and row within the sheet, counting from zero, left to right and top to bottom.
    public let column: Int
    public let row: Int

    /// The label's bottom-left corner in PDF coordinates, where y runs UP from the foot of
    /// the page.
    public let x: Double
    public let y: Double

    /// The label's size.
    public let width: Double
    public let height: Double

    /// The label's top edge, which is where text starts.
    public var top: Double { y + height }

    /// The label's right edge.
    public var right: Double { x + width }

    public init(page: Int, column: Int, row: Int,
                x: Double, y: Double, width: Double, height: Double) {
        self.page = page
        self.column = column
        self.row = row
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// Places labels onto sheets.
public enum Imposition {

    /// Where the label at `index` sits.
    ///
    /// - Parameters:
    ///   - index: counting from zero across the whole run, not within a page.
    ///   - sheet: the stock.
    ///   - startAt: how many label positions to skip on the FIRST sheet, for stock that has
    ///     already been partly used. Counted the way a person counts them — left to right,
    ///     top to bottom — so `--start-at 3` means "the first three are gone, begin at the
    ///     fourth".
    ///
    /// **The top margin is measured from the top of the page and PDF coordinates run from
    /// the bottom.** That conversion happens here, once. Every bug where labels print
    /// mirrored down the sheet is this subtraction done in the wrong place or not at all.
    public static func slot(at index: Int, on sheet: LabelSheet, startAt: Int = 0) -> Slot {
        let offset = max(0, index) + max(0, startAt)
        let perSheet = sheet.perSheet
        let page = offset / perSheet
        let within = offset % perSheet
        let row = within / sheet.columns
        let column = within % sheet.columns

        let x = sheet.marginLeft + Double(column) * sheet.pitchX
        // From the top of the page down to this row's top edge, then down again by the
        // label's own height to reach its bottom — which is where PDF wants its origin.
        let topDown = sheet.marginTop + Double(row) * sheet.pitchY
        let y = sheet.pageHeight - topDown - sheet.labelHeight

        return Slot(page: page, column: column, row: row,
                    x: x, y: y, width: sheet.labelWidth, height: sheet.labelHeight)
    }

    /// Every slot for a run of `count` labels.
    public static func slots(count: Int, on sheet: LabelSheet, startAt: Int = 0) -> [Slot] {
        guard count > 0 else { return [] }
        return (0 ..< count).map { slot(at: $0, on: sheet, startAt: startAt) }
    }

    /// How many sheets a run needs.
    ///
    /// Includes the positions skipped by `startAt`, because those are on the first sheet and
    /// the first sheet still goes through the printer.
    public static func pages(for count: Int, on sheet: LabelSheet, startAt: Int = 0) -> Int {
        guard count > 0 else { return 0 }
        let total = count + max(0, startAt)
        return (total + sheet.perSheet - 1) / sheet.perSheet
    }

    /// How many labels are wasted by starting partway into the first sheet.
    public static func skipped(startAt: Int, on sheet: LabelSheet) -> Int {
        min(max(0, startAt), sheet.perSheet)
    }
}
