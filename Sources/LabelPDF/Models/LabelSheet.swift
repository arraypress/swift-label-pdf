//
//  LabelSheet.swift
//  LabelPDF
//
//  Created by David Sherlock on 2026.
//
//  How a sheet of labels is laid out.
//
//  Pure arithmetic, so the one thing that is expensive to get wrong — a run whose labels
//  creep a millimetre further off true with every column, discovered after a box of sheets
//  has gone through the printer — is assertable without rendering anything.
//
//  A GEOMETRY IS NOT A GUESS AND MUST NOT BE TREATED AS ONE. The catalogue in ``Sheets``
//  carries the published dimensions for each stock code, and ``fits`` checks that they are
//  internally consistent with the page they claim to be printed on. What neither can check is
//  whether the numbers were transcribed correctly in the first place — so before committing a
//  box of stock, print one sheet on plain paper and hold it against the real thing. That is
//  cheap; a box is not.
//

import Foundation

/// Points per millimetre. Label stock is quoted in millimetres in Europe, inches in the
/// United States, and points nowhere at all.
public let pointsPerMillimetre = 72.0 / 25.4

/// Points per inch, for the American stock codes.
public let pointsPerInch = 72.0

/// The geometry of one sheet of labels: where the grid starts, how big each label is, and
/// how far apart they are.
///
/// **Pitch is not the label size.** The distance from one label's left edge to the next
/// label's left edge includes the gap between them, and on most stock that gap is not zero.
/// Laying out by label width instead of pitch is the classic error: the first column looks
/// perfect and the last is half a label off the edge.
public struct LabelSheet: Codable, Hashable, Sendable {

    /// The stock code — "L7160", "5160". Uppercase.
    public let code: String

    /// What it is for, in words a person recognises: "address", "name badge", "asset tag".
    public let purpose: String

    /// The paper, in points.
    public let pageWidth: Double
    public let pageHeight: Double

    /// Labels across, and down.
    public let columns: Int
    public let rows: Int

    /// One label's size in points.
    public let labelWidth: Double
    public let labelHeight: Double

    /// From the page's left edge to the first column's left edge.
    public let marginLeft: Double

    /// From the page's TOP edge to the first row's top edge.
    ///
    /// Measured from the top because that is how every stock vendor quotes it and how anybody
    /// holding a sheet thinks about it. PDF coordinates run from the bottom, and the
    /// conversion happens once, in ``Imposition``, rather than in every caller's head.
    public let marginTop: Double

    /// Left edge to left edge of the next column, gap included.
    public let pitchX: Double

    /// Top edge to top edge of the next row, gap included.
    public let pitchY: Double

    /// Corner rounding, for stock that is die-cut round. Zero for square labels.
    public let cornerRadius: Double

    public init(code: String, purpose: String,
                pageWidth: Double, pageHeight: Double,
                columns: Int, rows: Int,
                labelWidth: Double, labelHeight: Double,
                marginLeft: Double, marginTop: Double,
                pitchX: Double, pitchY: Double,
                cornerRadius: Double = 0) {
        self.code = code.uppercased()
        self.purpose = purpose
        self.pageWidth = pageWidth
        self.pageHeight = pageHeight
        self.columns = max(1, columns)
        self.rows = max(1, rows)
        self.labelWidth = labelWidth
        self.labelHeight = labelHeight
        self.marginLeft = marginLeft
        self.marginTop = marginTop
        self.pitchX = pitchX
        self.pitchY = pitchY
        self.cornerRadius = max(0, cornerRadius)
    }

    /// A sheet described in millimetres, which is how European stock is quoted.
    ///
    /// `gapX` and `gapY` are the space BETWEEN labels; the pitch is worked out from them, so
    /// a caller cannot supply a pitch that disagrees with the label size.
    public static func millimetres(code: String, purpose: String,
                                   page: (width: Double, height: Double),
                                   columns: Int, rows: Int,
                                   label: (width: Double, height: Double),
                                   margin: (left: Double, top: Double),
                                   gap: (x: Double, y: Double),
                                   cornerRadius: Double = 0) -> LabelSheet {
        let mm = pointsPerMillimetre
        return LabelSheet(
            code: code, purpose: purpose,
            pageWidth: page.width * mm, pageHeight: page.height * mm,
            columns: columns, rows: rows,
            labelWidth: label.width * mm, labelHeight: label.height * mm,
            marginLeft: margin.left * mm, marginTop: margin.top * mm,
            pitchX: (label.width + gap.x) * mm, pitchY: (label.height + gap.y) * mm,
            cornerRadius: cornerRadius * mm)
    }

    /// A sheet described in inches, which is how American stock is quoted.
    public static func inches(code: String, purpose: String,
                              page: (width: Double, height: Double),
                              columns: Int, rows: Int,
                              label: (width: Double, height: Double),
                              margin: (left: Double, top: Double),
                              gap: (x: Double, y: Double),
                              cornerRadius: Double = 0) -> LabelSheet {
        LabelSheet(
            code: code, purpose: purpose,
            pageWidth: page.width * pointsPerInch, pageHeight: page.height * pointsPerInch,
            columns: columns, rows: rows,
            labelWidth: label.width * pointsPerInch, labelHeight: label.height * pointsPerInch,
            marginLeft: margin.left * pointsPerInch, marginTop: margin.top * pointsPerInch,
            pitchX: (label.width + gap.x) * pointsPerInch,
            pitchY: (label.height + gap.y) * pointsPerInch,
            cornerRadius: cornerRadius * pointsPerInch)
    }

    /// How many labels one sheet holds.
    public var perSheet: Int { columns * rows }

    /// The gap between one label and the next, across and down.
    public var gapX: Double { pitchX - labelWidth }
    public var gapY: Double { pitchY - labelHeight }

    /// Whether the grid actually fits on the page it claims.
    ///
    /// The check that catches a transcription error. The last column's right edge is
    /// `marginLeft + (columns - 1) × pitchX + labelWidth`; if that runs past the paper, the
    /// numbers are wrong and no amount of careful drawing will save them.
    ///
    /// A tenth of a point of tolerance, because published dimensions are rounded to a tenth
    /// of a millimetre and the arithmetic should not fail on the rounding.
    public var fits: Bool {
        guard labelWidth > 0, labelHeight > 0, pitchX > 0, pitchY > 0 else { return false }
        guard gapX >= -0.1, gapY >= -0.1 else { return false }
        let tolerance = 0.1
        let right = marginLeft + Double(columns - 1) * pitchX + labelWidth
        let bottom = marginTop + Double(rows - 1) * pitchY + labelHeight
        return right <= pageWidth + tolerance
            && bottom <= pageHeight + tolerance
            && marginLeft >= -tolerance && marginTop >= -tolerance
    }

    /// A one-line description: "L7160 · 21 per sheet · 63.5 × 38.1 mm · address".
    public var summary: String {
        let width = labelWidth / pointsPerMillimetre
        let height = labelHeight / pointsPerMillimetre
        return String(format: "%@ · %d per sheet · %.1f × %.1f mm · %@",
                      code, perSheet, width, height, purpose)
    }
}
