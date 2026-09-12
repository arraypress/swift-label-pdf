//
//  LabelRenderer.swift
//  LabelPDF
//
//  Created by David Sherlock on 2026.
//
//  Content onto slots, slots onto pages, pages into a PDF.
//
//  The drawing is the easy half; ``Imposition`` did the part that is expensive to get wrong.
//  What is left here is fitting words into a few square centimetres so they are still legible
//  at arm's length, and knowing when to give up and shorten them rather than let them run
//  over the die cut.
//

import Foundation
import TextPDF

/// Draws labels onto a sheet.
public enum LabelRenderer {

    /// Render a run of labels.
    ///
    /// - Parameters:
    ///   - content: one entry per label, in order.
    ///   - sheet: the stock.
    ///   - style: how the text is set.
    ///   - startAt: labels to skip on the first sheet, for part-used stock.
    /// - Throws: ``LabelError`` when there is nothing to print, the geometry is broken, or
    ///   the skip runs past the end of a sheet.
    public static func render(_ content: [LabelContent],
                              on sheet: LabelSheet,
                              style: LabelStyle = .default,
                              startAt: Int = 0) throws -> Document {
        let printable = content.filter { !$0.isEmpty }
        guard !printable.isEmpty else { throw LabelError.nothingToPrint }
        guard sheet.fits else { throw LabelError.geometryDoesNotFit(sheet.code) }
        guard startAt >= 0, startAt < sheet.perSheet else {
            throw LabelError.startsPastTheSheet(startAt: startAt, perSheet: sheet.perSheet)
        }

        // Margin zero: a label sheet has no page margin of its own. Every position comes from
        // the stock's geometry, and a document margin would silently shift all of it.
        let pdf = Document(width: sheet.pageWidth, height: sheet.pageHeight,
                           margin: 0, fontSize: 9, leading: 11)

        var page = 0
        for (index, label) in printable.enumerated() {
            let slot = Imposition.slot(at: index, on: sheet, startAt: startAt)
            while page < slot.page {
                _ = pdf.pageBreak()
                page += 1
            }
            draw(label, in: slot, on: pdf, style: style, sheet: sheet)
        }
        return pdf
    }

    /// One label.
    static func draw(_ content: LabelContent, in slot: Slot, on pdf: Document,
                     style: LabelStyle, sheet: LabelSheet) {
        if style.outline {
            // A hairline, drawn as four lines rather than a filled rect — a fill would cover
            // the label. This is the alignment proof, printed on plain paper and held against
            // the real stock before a box is committed.
            let ink = Color.grey(180)
            if sheet.cornerRadius > 0 {
                _ = pdf.circle(x: slot.x + slot.width / 2, y: slot.y + slot.height / 2,
                               radius: 0.4, color: ink)
            }
            _ = pdf.line(from: slot.x, slot.y, to: slot.right, slot.y,
                         color: ink, thickness: 0.25)
            _ = pdf.line(from: slot.x, slot.top, to: slot.right, slot.top,
                         color: ink, thickness: 0.25)
            _ = pdf.line(from: slot.x, slot.y, to: slot.x, slot.top,
                         color: ink, thickness: 0.25)
            _ = pdf.line(from: slot.right, slot.y, to: slot.right, slot.top,
                         color: ink, thickness: 0.25)
        }

        let padding = min(style.padding, min(slot.width, slot.height) / 4)
        var textLeft = slot.x + padding
        var textWidth = slot.width - padding * 2

        // A QR takes the trailing edge and as much height as the label allows, square.
        if let code = content.qr {
            let side = min(slot.height - padding * 2, slot.width / 3)
            if side > 8 {
                let drawn = pdf.qr(code,
                                   x: slot.right - padding - side,
                                   y: slot.y + (slot.height - side) / 2,
                                   size: side, correction: .medium, quiet: 1)
                if drawn { textWidth -= side + padding }
            }
        }

        // A logo takes the leading edge, square, and pushes the text across.
        if let path = content.image,
           let picture = try? EmbeddedImage.load(URL(fileURLWithPath: path)) {
            let side = min(slot.height - padding * 2, slot.width / 4)
            if side > 6 {
                _ = pdf.image(picture, x: textLeft, y: slot.y + (slot.height - side) / 2,
                              width: side, height: side)
                textLeft += side + padding
                textWidth -= side + padding
            }
        }

        // A barcode takes the foot of the label, full width, and the text sits above it.
        // Across rather than beside, because a linear code needs length to be read and a
        // label is wider than it is tall.
        var textBottom = slot.y + padding
        if let code = content.barcode {
            let captionRoom = Barcode.captionHeight(for: slot.width - padding * 2)
            let barHeight = min((slot.height - padding * 2) * 0.4, 34)
            if barHeight > 8, slot.width - padding * 2 > 40 {
                let failure = pdf.barcode(code, symbology: content.symbology,
                                          x: slot.x + padding, y: slot.y + padding + captionRoom,
                                          width: slot.width - padding * 2, height: barHeight)
                // A refused barcode leaves the text alone rather than leaving a gap where one
                // would have been — the label still prints, just without it.
                if failure == nil { textBottom += barHeight + captionRoom + padding / 2 }
            }
        }

        guard !content.lines.isEmpty, textWidth > 4 else { return }

        let textHeight = max(8, slot.top - padding - textBottom)
        let size = style.fontSize ?? fittingSize(content.lines, width: textWidth,
                                                 height: textHeight, on: pdf)
        let leading = size * 1.22
        let blockHeight = leading * Double(content.lines.count)
        // Centred vertically: a label read at arm's length looks wrong hung from the top,
        // and the die cut is not always exactly where the artwork thinks it is.
        var baseline = textBottom + (textHeight + blockHeight) / 2 - leading * 0.8

        for (index, line) in content.lines.enumerated() {
            let bold = style.boldFirstLine && index == 0
            let font: Font = bold ? .helveticaBold : .helvetica
            let shown = pdf.fit(line, into: textWidth, size: size, font: font)
            // TextPDF centres WITHIN a box, and ignores the alignment entirely when
            // boxWidth is zero — which is its default. Shifting x to the middle instead does
            // nothing at all: the text is drawn left-aligned from the centre, which looks
            // like centring having no effect, because it does not.
            _ = pdf.textAt(shown, x: textLeft, y: baseline, size: size, font: font,
                           align: style.centred ? .center : .left,
                           boxWidth: style.centred ? textWidth : 0)
            baseline -= leading
        }
    }

    /// The largest size at which every line fits the label, within sensible bounds.
    ///
    /// Stepping down rather than solving: the measurement is per-font and per-string, the
    /// range is small, and a loop of a dozen measurements is far cheaper than being wrong.
    /// Six points is the floor — smaller than that is not a label, it is a rumour.
    static func fittingSize(_ lines: [String], width: Double, height: Double,
                            on pdf: Document) -> Double {
        let longest = lines.max { pdf.width(of: $0, size: 10) < pdf.width(of: $1, size: 10) }
            ?? lines[0]
        var size = 12.0
        while size > 6 {
            let fitsWidth = pdf.width(of: longest, size: size, font: .helveticaBold) <= width
            let fitsHeight = size * 1.22 * Double(lines.count) <= height
            if fitsWidth && fitsHeight { return size }
            size -= 0.5
        }
        return 6
    }
}
