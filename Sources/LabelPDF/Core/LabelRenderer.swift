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
//  at arm's length — smaller, then wrapped — and, when even that cannot hold them, printing
//  them whole and saying so. Never shortening them: a label with half a street name on it is
//  not an address, and it looks like one.
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
    ///   - font: a TrueType font for text the built-in fonts cannot draw — a Cyrillic or
    ///     Greek address, which would otherwise print as `?`. Used only for the lines that
    ///     need it, so the rest stay in Helvetica.
    /// - Throws: ``LabelError`` when there is nothing to print, the geometry is broken, or
    ///   the skip runs past the end of a sheet.
    public static func render(_ content: [LabelContent],
                              on sheet: LabelSheet,
                              style: LabelStyle = .default,
                              startAt: Int = 0,
                              font: EmbeddedFont? = nil) throws -> Document {
        try layOut(content, on: sheet, style: style, startAt: startAt, font: font).document
    }

    // MARK: Warnings

    /// What on these labels will not print as given.
    ///
    /// Text that cannot fit its label even wrapped at the six-point floor, and the codes and
    /// images that could not be drawn at all. The text is never cut to make it fit — it is
    /// kept whole and runs past the label's edge, where it will print across the die cut or
    /// onto the next label — so this is the only place that says so before the stock does.
    ///
    /// Empty when everything fits, and when the run would be refused outright: ``render``
    /// throws for that, and says why.
    ///
    /// Pass the same `font` the run was rendered with: it changes how wide the text is.
    public static func warnings(_ content: [LabelContent],
                                on sheet: LabelSheet,
                                style: LabelStyle = .default,
                                font: EmbeddedFont? = nil) -> [String] {
        (try? layOut(content, on: sheet, style: style, startAt: 0, font: font).warnings) ?? []
    }

    /// The same, and whether every line of every label actually reached a drawn page.
    ///
    /// ``warnings(_:on:style:)`` inspects the layout; this also asks the finished document —
    /// the question that matters, because a renderer that went back to shortening a line, or
    /// stopped drawing one, would pass every check that only reads the content. Lines are
    /// matched in order and with the whitespace taken out, so a line wrapped onto two is
    /// still there. Characters the fonts cannot draw, which print as `?`, are reported too.
    public static func warnings(_ content: [LabelContent],
                                on sheet: LabelSheet,
                                style: LabelStyle = .default,
                                font: EmbeddedFont? = nil,
                                verifying document: Document) -> [String] {
        var out = warnings(content, on: sheet, style: style, font: font)
        let page = DrawnLines.squeezed(document.drawnText)
        var cursor = page.startIndex
        for (index, label) in content.filter({ !$0.isEmpty }).enumerated() {
            for line in label.lines {
                if let found = DrawnLines.find(line, in: page, from: cursor) {
                    cursor = found
                } else {
                    out.append("\(name(of: label, at: index)): \"\(line)\" did not reach the page.")
                }
            }
        }
        for substitution in document.substitutions {
            let advice = substitution.unsupportedScript == nil
                ? "pass a font that covers them" : "no font here can set that script"
            out.append("\"\(substitution.text)\" has characters the built-in fonts cannot draw; "
                + "they print as ? — \(advice).")
        }
        return out
    }

    /// How a warning names a label: its place in the run and its first line, which is what
    /// somebody holding the sheet can find.
    static func name(of label: LabelContent, at index: Int) -> String {
        guard let first = label.lines.first else { return "Label \(index + 1)" }
        return "Label \(index + 1) (\(first))"
    }

    // MARK: Layout

    /// The run laid out, with what did not go onto it as asked.
    static func layOut(_ content: [LabelContent],
                       on sheet: LabelSheet,
                       style: LabelStyle,
                       startAt: Int,
                       font: EmbeddedFont? = nil) throws -> (document: Document, warnings: [String]) {
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
        pdf.embeddedFont = font

        var warnings: [String] = []
        var page = 0
        for (index, label) in printable.enumerated() {
            let slot = Imposition.slot(at: index, on: sheet, startAt: startAt)
            while page < slot.page {
                _ = pdf.pageBreak()
                page += 1
            }
            warnings += draw(label, in: slot, on: pdf, style: style, sheet: sheet)
                .map { "\(name(of: label, at: index)): \($0)" }
        }
        return (pdf, warnings)
    }

    /// One label. Returns what could not be drawn as given.
    @discardableResult
    static func draw(_ content: LabelContent, in slot: Slot, on pdf: Document,
                     style: LabelStyle, sheet: LabelSheet) -> [String] {
        var problems: [String] = []
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
                if drawn {
                    textWidth -= side + padding
                } else {
                    problems.append("the QR code for \"\(code)\" was not drawn: it holds more "
                        + "than a QR code can carry.")
                }
            } else {
                problems.append("the QR code for \"\(code)\" was not drawn: the label is too "
                    + "small for one that would scan.")
            }
        }

        // A logo takes the leading edge, square, and pushes the text across.
        if let path = content.image {
            let side = min(slot.height - padding * 2, slot.width / 4)
            if let picture = try? EmbeddedImage.load(URL(fileURLWithPath: path)) {
                if side > 6 {
                    _ = pdf.image(picture, x: textLeft, y: slot.y + (slot.height - side) / 2,
                                  width: side, height: side)
                    textLeft += side + padding
                    textWidth -= side + padding
                } else {
                    problems.append("the image at \(path) was not drawn: the label is too small.")
                }
            } else {
                problems.append("the image at \(path) could not be read, so it was not drawn.")
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
                if let failure {
                    problems.append("the barcode \"\(code)\" was not drawn: "
                        + describe(failure) + ".")
                } else {
                    textBottom += barHeight + captionRoom + padding / 2
                }
            } else {
                problems.append("the barcode \"\(code)\" was not drawn: the label is too small "
                    + "for one that would scan.")
            }
        }

        guard !content.lines.isEmpty else { return problems }

        // Never narrower than a point: a label crowded by a code and a logo still sets its
        // text, a character a line if it comes to that, rather than skipping it.
        textWidth = max(textWidth, 1)
        let textHeight = max(8, slot.top - padding - textBottom)
        let setting = fit(content.lines, width: textWidth, height: textHeight,
                          style: style, on: pdf)
        let leading = setting.size * 1.22
        let blockHeight = leading * Double(setting.lines.count)

        // Centred vertically: a label read at arm's length looks wrong hung from the top,
        // and the die cut is not always exactly where the artwork thinks it is. Text that
        // cannot fit hangs from the top instead, so what runs over is the end of it and the
        // first line — the name, usually — stays on the label.
        var baseline = setting.fits
            ? textBottom + (textHeight + blockHeight) / 2 - leading * 0.8
            : slot.top - padding - leading * 0.8

        for line in setting.lines {
            let font: Font = line.bold ? .helveticaBold : .helvetica
            // TextPDF centres WITHIN a box, and ignores the alignment entirely when
            // boxWidth is zero — which is its default. Shifting x to the middle instead does
            // nothing at all: the text is drawn left-aligned from the centre, which looks
            // like centring having no effect, because it does not.
            _ = pdf.textAt(line.text, x: textLeft, y: baseline, size: setting.size, font: font,
                           align: style.centred ? .center : .left,
                           boxWidth: style.centred ? textWidth : 0)
            baseline -= leading
        }

        if !setting.fits {
            let over = Int((blockHeight - textHeight) / leading) + 1
            let asked = style.fontSize == nil ? "even wrapped at \(format(setting.size)) pt"
                                              : "at the \(format(setting.size)) pt asked for"
            problems.append("the text does not fit \(sheet.code) \(asked); it is printed whole "
                + "and about \(over) line\(over == 1 ? "" : "s") run\(over == 1 ? "s" : "") past "
                + "the label's edge.")
        }
        return problems
    }

    // MARK: Fitting

    /// The text of one label as it will be set.
    struct Setting: Equatable {

        /// One line as drawn.
        struct Line: Equatable {
            let text: String
            let bold: Bool
        }

        let size: Double
        let lines: [Line]

        /// Whether the lines fit the space they were set for. When they do not, they are all
        /// still here — nothing is ever cut to make text fit.
        let fits: Bool
    }

    /// Six points is the floor — smaller than that is not a label, it is a rumour.
    static let minimumSize = 6.0

    /// Where the search for a size starts.
    static let maximumSize = 12.0

    /// The largest size at which every line fits the label, within sensible bounds.
    ///
    /// Shrink first, then wrap: each line kept on one line of its own down to the floor,
    /// because an address read as written is easier to read than one broken up; and only
    /// when no size manages that, the lines wrapped onto more lines, again largest size
    /// first. When nothing fits even wrapped at the floor, the text is set wrapped at the
    /// floor anyway and reported as not fitting. It is never shortened: a label with half
    /// a street name on it is not an address, and it looks like one.
    ///
    /// An explicit size is honoured: it is the only size tried, wrapped if it must be.
    ///
    /// Stepping down rather than solving: the measurement is per-font and per-string, the
    /// range is small, and a loop of a dozen measurements is far cheaper than being wrong.
    static func fit(_ lines: [String], width: Double, height: Double,
                    style: LabelStyle, on pdf: Document) -> Setting {
        let sizes = style.fontSize.map { [$0] }
            ?? Array(stride(from: maximumSize, through: minimumSize, by: -0.5))

        func font(_ index: Int) -> Font {
            style.boldFirstLine && index == 0 ? .helveticaBold : .helvetica
        }
        func set(_ size: Double, wrapping: Bool) -> [Setting.Line] {
            lines.enumerated().flatMap { index, line -> [Setting.Line] in
                let pieces = wrapping
                    ? pdf.lines(of: line, width: width, size: size, font: font(index))
                    : [line]
                return pieces.map { Setting.Line(text: $0, bold: font(index) == .helveticaBold) }
            }
        }
        func fits(_ set: [Setting.Line], at size: Double) -> Bool {
            size * 1.22 * Double(set.count) <= height
                && set.allSatisfy {
                    pdf.width(of: $0.text, size: size, font: $0.bold ? .helveticaBold : .helvetica)
                        <= width
                }
        }

        for wrapping in [false, true] {
            for size in sizes {
                let candidate = set(size, wrapping: wrapping)
                if fits(candidate, at: size) {
                    return Setting(size: size, lines: candidate, fits: true)
                }
            }
        }
        let floor = sizes.last ?? minimumSize
        return Setting(size: floor, lines: set(floor, wrapping: true), fits: false)
    }

    /// A size as a person writes it: 6, 7.5.
    static func format(_ size: Double) -> String {
        size == size.rounded() ? String(Int(size)) : String(format: "%.1f", size)
    }

    /// Why a barcode was refused, in words.
    static func describe(_ failure: Barcode.Failure) -> String {
        switch failure {
        case .empty:
            return "it is empty"
        case .notNumeric(let symbology):
            return "\(symbology.displayName) takes digits only"
        case .wrongLength(let symbology, let expected, let got):
            return "\(symbology.displayName) takes \(expected) digits, not \(got)"
        case .badCheckDigit(let expected, let got):
            return "its check digit is \(got) and should be \(expected)"
        case .refused(let symbology):
            return "it cannot be encoded as \(symbology.displayName)"
        case .tooSmall:
            return "the label is too small for one that would scan"
        }
    }
}

/// Whether a label's lines reached the page. Pure functions of the drawn text, so the
/// matching rule is pinned without rendering anything.
enum DrawnLines {

    /// Everything drawn, as one string with the whitespace taken out.
    ///
    /// Whitespace goes because a line wrapped to fit its label is still on the page — and a
    /// word too long for the label is broken mid-word, so rejoining the pieces with a space
    /// would not give the original back.
    static func squeezed(_ drawn: [String]) -> String {
        drawn.joined().filter { !$0.isWhitespace }
    }

    /// Where `line` ends on `page`, searching from `start` — so each label's lines are
    /// found in order and one label's text cannot vouch for another's. `nil` when it is not
    /// there; a blank line is trivially there and moves nothing.
    static func find(_ line: String, in page: String, from start: String.Index) -> String.Index? {
        let squeezed = line.filter { !$0.isWhitespace }
        guard !squeezed.isEmpty else { return start }
        return page[start...].range(of: squeezed)?.upperBound
    }
}
