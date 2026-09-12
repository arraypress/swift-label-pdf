//
//  LabelContent.swift
//  LabelPDF
//
//  Created by David Sherlock on 2026.
//
//  What goes on one label.
//
//  Deliberately small. A label is a few square centimetres seen from arm's length — it holds
//  a handful of lines, perhaps a mark and a code, and anything more is a leaflet. The
//  temptation with a layout engine is to let it do everything; the useful thing here is that
//  it does not, so what comes out is legible at the size it is actually read at.
//

import Foundation

/// One label's content.
public struct LabelContent: Codable, Hashable, Sendable {

    /// Lines of text, top to bottom. The first is set slightly bolder.
    public let lines: [String]

    /// Text encoded as a QR code, drawn at the trailing edge — a URL, an asset id, a vCard.
    public let qr: String?

    /// A path to an image drawn at the leading edge. A logo, usually.
    public let image: String?

    public init(lines: [String], qr: String? = nil, image: String? = nil) {
        self.lines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        self.qr = qr?.isEmpty == true ? nil : qr
        self.image = image?.isEmpty == true ? nil : image
    }

    /// Whether this label would print nothing at all.
    public var isEmpty: Bool { lines.isEmpty && qr == nil && image == nil }

    /// One label built from a row of data, where the column order is the line order.
    ///
    /// Columns named `qr` or `image` are pulled out and used as those, rather than printed as
    /// a line of text — otherwise a mailing list with a URL column would set the URL in
    /// nine-point type across the middle of every label.
    public static func from(row: [String: String], order: [String]) -> LabelContent {
        var lines: [String] = []
        var qr: String?
        var image: String?
        for key in order {
            guard let value = row[key]?.trimmingCharacters(in: .whitespaces), !value.isEmpty
            else { continue }
            switch key.lowercased() {
            case "qr", "qrcode", "qr_code":  qr = value
            case "image", "logo", "icon":    image = value
            default:                         lines.append(value)
            }
        }
        return LabelContent(lines: lines, qr: qr, image: image)
    }
}

/// How a label's content is set.
public struct LabelStyle: Codable, Hashable, Sendable {

    /// Point size for the body lines. Nil measures one that fits.
    public let fontSize: Double?

    /// Space kept inside the label's edge, in points.
    ///
    /// Not decoration: sheet stock is die-cut with a tolerance, and a printer's paper feed has
    /// one of its own. Text set hard against the trim is text that will be cut on some sheets
    /// and not others.
    public let padding: Double

    /// Draw a hairline round each label, to check alignment on plain paper before committing
    /// a box of stock.
    public let outline: Bool

    /// Set the first line in a heavier weight.
    public let boldFirstLine: Bool

    /// Centre the text rather than ranging it left.
    public let centred: Bool

    public init(fontSize: Double? = nil, padding: Double = 6,
                outline: Bool = false, boldFirstLine: Bool = true, centred: Bool = false) {
        self.fontSize = fontSize
        self.padding = max(0, padding)
        self.outline = outline
        self.boldFirstLine = boldFirstLine
        self.centred = centred
    }

    public static let `default` = LabelStyle()
}
