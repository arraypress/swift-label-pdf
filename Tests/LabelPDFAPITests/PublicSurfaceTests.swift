//
//  PublicSurfaceTests.swift
//  LabelPDFAPITests
//
//  Created by David Sherlock on 2026.
//
//  Plain `import`, no `@testable`, on purpose.
//
//  Everything a caller outside this package is meant to reach has to be reachable here, and
//  the other test target cannot prove that: `@testable` makes internal declarations visible,
//  so a symbol that quietly loses its `public` keeps passing every test in it and breaks only
//  when somebody else builds against the tag.
//

import Foundation
import XCTest
import LabelPDF
import TextPDF

final class PublicSurfaceTests: XCTestCase {

    /// The shortest path from nothing to a PDF, using only what is public.
    func testTheWholeJobIsDoableFromOutsideThePackage() throws {
        let sheet = try XCTUnwrap(Sheets.named("L7160"))
        let labels = [
            LabelContent(lines: ["Ada Lovelace", "12 Example Street", "London"]),
            LabelContent(lines: ["Grace Hopper", "34 Sample Road", "New York"], qr: "https://example.com"),
        ]
        let pdf = try LabelRenderer.render(labels, on: sheet,
                                           style: LabelStyle(padding: 6, outline: true),
                                           startAt: 2)
        XCTAssertGreaterThan(try pdf.render().count, 500)
    }

    /// What will not print as given has to be askable from outside, or a caller cannot
    /// tell anybody before the stock goes through the printer.
    func testWarningsArePublic() throws {
        let labels = [LabelContent(lines: (1 ... 12).map { "A line of a label with too much on it \($0)" })]
        let pdf = try LabelRenderer.render(labels, on: Sheets.l7651)
        XCTAssertFalse(LabelRenderer.warnings(labels, on: Sheets.l7651).isEmpty)
        XCTAssertFalse(LabelRenderer.warnings(labels, on: Sheets.l7651, style: .default,
                                              verifying: pdf).isEmpty)
    }

    func testTheCatalogueIsPublic() {
        XCTAssertFalse(Sheets.all.isEmpty)
        XCTAssertEqual(Sheets.l7160.code, "L7160")
        XCTAssertEqual(Sheets.avery5160.code, "5160")
        XCTAssertTrue(Sheets.all.allSatisfy { $0.fits })
        XCTAssertFalse(Sheets.l7160.summary.isEmpty)
    }

    func testGeometryCanBeBuiltAndInspectedFromOutside() {
        let custom = LabelSheet.millimetres(
            code: "CUSTOM", purpose: "test", page: (210, 297),
            columns: 2, rows: 2, label: (90, 50),
            margin: (left: 10, top: 10), gap: (x: 10, y: 10))

        XCTAssertTrue(custom.fits)
        XCTAssertEqual(custom.perSheet, 4)
        XCTAssertEqual(custom.gapX, 10 * pointsPerMillimetre, accuracy: 0.01)
        XCTAssertEqual(custom.labelWidth, 90 * pointsPerMillimetre, accuracy: 0.01)

        let inches = LabelSheet.inches(
            code: "US", purpose: "test", page: (8.5, 11),
            columns: 2, rows: 2, label: (3, 2), margin: (left: 1, top: 1), gap: (x: 0.5, y: 0.5))
        XCTAssertTrue(inches.fits)
        XCTAssertEqual(inches.labelWidth, 3 * pointsPerInch, accuracy: 0.01)
    }

    func testImpositionIsPublic() {
        let slot = Imposition.slot(at: 4, on: Sheets.l7160, startAt: 0)
        XCTAssertEqual(slot.row, 1)
        XCTAssertEqual(slot.column, 1)
        XCTAssertGreaterThan(slot.top, slot.y)
        XCTAssertGreaterThan(slot.right, slot.x)

        XCTAssertEqual(Imposition.pages(for: 22, on: Sheets.l7160), 2)
        XCTAssertEqual(Imposition.slots(count: 3, on: Sheets.l7160).count, 3)
        XCTAssertEqual(Imposition.skipped(startAt: 5, on: Sheets.l7160), 5)
    }

    func testContentCanBeBuiltFromARowFromOutside() {
        let content = LabelContent.from(row: ["name": "Ada", "qr": "x"], order: ["name", "qr"])
        XCTAssertEqual(content.lines, ["Ada"])
        XCTAssertEqual(content.qr, "x")
        XCTAssertFalse(content.isEmpty)
    }

    /// Errors are part of the contract: a caller has to be able to match on them.
    func testErrorsAreMatchableFromOutside() {
        do {
            _ = try LabelRenderer.render([], on: Sheets.l7160)
            XCTFail("expected a refusal")
        } catch let error as LabelError {
            XCTAssertEqual(error, .nothingToPrint)
            XCTAssertFalse(error.localizedDescription.isEmpty)
        } catch {
            XCTFail("the error should be a LabelError, got \(error)")
        }
    }

    /// Everything a caller might store or send has to survive a round trip.
    func testTheModelsAreCodable() throws {
        let sheet = Sheets.l7165
        let decodedSheet = try JSONDecoder().decode(LabelSheet.self,
                                                    from: JSONEncoder().encode(sheet))
        XCTAssertEqual(decodedSheet, sheet)

        let content = LabelContent(lines: ["a", "b"], qr: "q", image: "i")
        let decodedContent = try JSONDecoder().decode(LabelContent.self,
                                                       from: JSONEncoder().encode(content))
        XCTAssertEqual(decodedContent, content)

        let style = LabelStyle(fontSize: 9, padding: 4, outline: true,
                               boldFirstLine: false, centred: true)
        let decodedStyle = try JSONDecoder().decode(LabelStyle.self,
                                                     from: JSONEncoder().encode(style))
        XCTAssertEqual(decodedStyle, style)
    }
}
