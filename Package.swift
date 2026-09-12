// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "swift-label-pdf",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "LabelPDF", targets: ["LabelPDF"]),
    ],
    dependencies: [
        .package(url: "https://github.com/arraypress/swift-text-pdf.git", from: "0.3.0"),
    ],
    targets: [
        .target(
            name: "LabelPDF",
            dependencies: [
                .product(name: "TextPDF", package: "swift-text-pdf"),
            ]
        ),
        .testTarget(name: "LabelPDFTests", dependencies: ["LabelPDF"]),

        // Plain `import`, no @testable. Everything a caller outside the package is meant to
        // reach has to be reachable here, and nothing in the other target can prove that —
        // @testable makes internal declarations visible, so a visibility regression passes
        // every test in it.
        .testTarget(name: "LabelPDFAPITests", dependencies: ["LabelPDF"]),
    ]
)
