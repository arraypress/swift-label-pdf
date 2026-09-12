//
//  Sheets.swift
//  LabelPDF
//
//  Created by David Sherlock on 2026.
//
//  The stock catalogue: what you can buy, by the code printed on the box.
//
//  WHAT THIS IS NOT FOR. A carrier's shipping label — the one with the postage barcode — is
//  not in here and never will be. Those are issued against a paid postage account, carry a
//  tracking number the carrier assigned, and are produced by the marketplace or the carrier's
//  own software. Etsy, eBay and Royal Mail all hand you one. A PDF that merely looks like one
//  is worse than nothing: it will be refused at the counter, or worse, accepted and lost.
//
//  WHAT IT IS FOR is everything you print on blank sheet stock yourself, which is the part
//  nobody hands you: return address labels, product and ingredient labels, care and batch
//  labels, jar and bottle labels, thank-you stickers, name badges, folder and shelf labels,
//  and QR asset tags.
//
//  ON THE NUMBERS, and this is the part to read before trusting them. Each label size, column
//  count and gap here is the published dimension for that code. The LEFT MARGINS, however,
//  are derived rather than transcribed: sheet stock is die-cut in a press with the die centred
//  on the web, so the space left over on the right equals the margin on the left, and the
//  margin follows from the page width and the grid. Four of the ten were transcribed wrong at
//  first and the symmetry test caught every one — which is the argument for deriving them.
//
//  Vertical margins are NOT symmetric and are not derived: a printer needs more clearance at
//  the leading edge than the trailing one, and stock is cut accordingly.
//
//  ``LabelSheet/fits`` proves each geometry is consistent with its page, and the test suite
//  proves the horizontal symmetry. Neither can catch a wrong number that happens to be
//  self-consistent. **Print one sheet on plain paper with `outline` on and hold it against the
//  real stock before committing a box.** That is cheap; a box is not.
//

import Foundation

/// Every stock geometry this knows, by code.
public enum Sheets {

    /// A4, 210 × 297 mm.
    static let a4 = (width: 210.0, height: 297.0)

    /// US Letter, 8.5 × 11 in.
    static let letter = (width: 8.5, height: 11.0)

    // MARK: - A4 stock

    /// 21 per sheet, 63.5 × 38.1 mm. The default address label across Europe, and the one
    /// most people mean when they say "a sheet of labels".
    public static let l7160 = LabelSheet.millimetres(
        code: "L7160", purpose: "address",
        page: a4, columns: 3, rows: 7,
        label: (63.5, 38.1), margin: (left: 7.2, top: 15.1), gap: (x: 2.5, y: 0))

    /// 14 per sheet, 99.1 × 38.1 mm. A wide address label — two columns, so long lines fit
    /// without wrapping.
    public static let l7163 = LabelSheet.millimetres(
        code: "L7163", purpose: "address",
        page: a4, columns: 2, rows: 7,
        label: (99.1, 38.1), margin: (left: 4.65, top: 15.1), gap: (x: 2.5, y: 0))

    /// 8 per sheet, 99.1 × 67.7 mm. Big enough for a product label with ingredients on it.
    public static let l7165 = LabelSheet.millimetres(
        code: "L7165", purpose: "product",
        page: a4, columns: 2, rows: 4, 
        label: (99.1, 67.7), margin: (left: 4.65, top: 13.0), gap: (x: 2.5, y: 0))

    /// 24 per sheet, 63.5 × 33.9 mm. Small product and batch labels.
    public static let l7159 = LabelSheet.millimetres(
        code: "L7159", purpose: "product",
        page: a4, columns: 3, rows: 8,
        label: (63.5, 33.9), margin: (left: 7.2, top: 13.1), gap: (x: 2.5, y: 0))

    /// 65 per sheet, 38.1 × 21.2 mm. The smallest common stock — price tags, cable labels,
    /// anything where the label must not dominate what it is stuck to.
    public static let l7651 = LabelSheet.millimetres(
        code: "L7651", purpose: "small / price",
        page: a4, columns: 5, rows: 13,
        label: (38.1, 21.2), margin: (left: 4.75, top: 10.7), gap: (x: 2.5, y: 0))

    /// 24 round labels, 40 mm across. Jar lids, thank-you stickers, sealing a bag.
    public static let l7780 = LabelSheet.millimetres(
        code: "L7780", purpose: "round sticker",
        page: a4, columns: 4, rows: 6,
        label: (40, 40), margin: (left: 13.0, top: 13.5), gap: (x: 8.0, y: 4.0),
        cornerRadius: 20)

    /// 24 per sheet, 70 × 37 mm. Herma's equivalent of the common address label, and the
    /// default stock in a lot of European stationery cupboards.
    public static let herma4450 = LabelSheet.millimetres(
        code: "4450", purpose: "address (Herma)",
        page: a4, columns: 3, rows: 8,
        label: (70, 37), margin: (left: 0, top: 0), gap: (x: 0, y: 0))

    // MARK: - US Letter stock

    /// 30 per sheet, 2.625 × 1 in. The American address label — what "Avery 5160" means.
    public static let avery5160 = LabelSheet.inches(
        code: "5160", purpose: "address",
        page: letter, columns: 3, rows: 10,
        label: (2.625, 1.0), margin: (left: 0.1875, top: 0.5), gap: (x: 0.125, y: 0))

    /// 10 per sheet, 4 × 2 in. Shipping-sized, for a return address or a product label.
    public static let avery5163 = LabelSheet.inches(
        code: "5163", purpose: "large",
        page: letter, columns: 2, rows: 5,
        label: (4.0, 2.0), margin: (left: 0.15625, top: 0.5), gap: (x: 0.1875, y: 0))

    /// 8 per sheet, 3.375 × 2.333 in. Name badges — the conference stock.
    public static let avery5395 = LabelSheet.inches(
        code: "5395", purpose: "name badge",
        page: letter, columns: 2, rows: 4,
        label: (3.375, 2.333), margin: (left: 0.71875, top: 0.6), gap: (x: 0.3125, y: 0))

    // MARK: - Lookup

    /// Every sheet in the catalogue, in the order they are listed.
    public static let all: [LabelSheet] = [
        l7160, l7163, l7165, l7159, l7651, l7780, herma4450,
        avery5160, avery5163, avery5395,
    ]

    /// Find a sheet by its code, however it was typed.
    ///
    /// Accepts the code with or without its vendor prefix and in any case, because the number
    /// is what is printed on the box and "L7160", "l7160" and "7160" all mean it.
    public static func named(_ code: String) -> LabelSheet? {
        let wanted = code.uppercased().trimmingCharacters(in: .whitespaces)
        if let exact = all.first(where: { $0.code == wanted }) { return exact }
        let digits = wanted.drop { !$0.isNumber }
        guard !digits.isEmpty else { return nil }
        return all.first { $0.code.drop { !$0.isNumber } == digits }
    }
}
