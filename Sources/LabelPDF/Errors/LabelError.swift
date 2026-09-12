//
//  LabelError.swift
//  LabelPDF
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// What can go wrong making a sheet of labels.
public enum LabelError: Error, Equatable, Sendable {

    /// No stock is known by that code.
    case unknownSheet(String)

    /// The geometry does not fit the page it claims — a transcription error in a custom sheet.
    case geometryDoesNotFit(String)

    /// There was nothing to print.
    case nothingToPrint

    /// More labels were skipped than the sheet holds.
    case startsPastTheSheet(startAt: Int, perSheet: Int)

    /// An image could not be read.
    case unreadableImage(String)
}

extension LabelError: LocalizedError {

    public var errorDescription: String? {
        switch self {
        case .unknownSheet(let code):
            return "no stock known as \"\(code)\""
        case .geometryDoesNotFit(let code):
            return "the geometry for \"\(code)\" does not fit its page — check the dimensions"
        case .nothingToPrint:
            return "nothing to print"
        case .startsPastTheSheet(let startAt, let perSheet):
            return "cannot skip \(startAt) labels on a sheet that holds \(perSheet)"
        case .unreadableImage(let path):
            return "could not read the image at \(path)"
        }
    }
}
