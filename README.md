# swift-label-pdf

Rows of data onto a sheet of blank label stock, as a PDF.

```swift
import LabelPDF

let sheet = Sheets.named("L7160")!          // 21-up A4 address labels
let labels = rows.map { LabelContent(lines: [$0.name, $0.street, $0.city], qr: $0.url) }
let pdf = try LabelRenderer.render(labels, on: sheet, startAt: 6)
try pdf.save(to: url)
```

## Not a shipping label

The one with the postage barcode is issued against a paid postage account, carries a tracking
number the carrier assigned, and comes from Etsy, eBay or whoever you bought the postage from.
A PDF that merely looks like one is worse than useless — refused at the counter, or accepted
and lost. This library will never produce one.

**What it is for** is everything you print on blank stock yourself, which is the part nobody
hands you: return address labels, product and ingredient labels, care and batch labels, jar
and bottle labels, thank-you stickers, name badges, folder and shelf labels, QR asset tags.

## Pitch is not label size

The distance from one label's left edge to the next includes the gap between them, and on most
stock that gap is not zero. Laying out by label width is the classic error: the first column
looks perfect and the last is half a label off the page.

All of the placement is arithmetic and none of it touches a PDF, which is deliberate. The
expensive failure here — a run that creeps off true one column at a time, discovered after a
box of stock has gone through the printer — is a sum, and a sum can be asserted to the tenth
of a point without rendering anything.

## The margins are derived, not transcribed

Label sizes, column counts and gaps are the published dimensions for each code. **Left margins
are computed**, because sheet stock is die-cut in a press with the die centred on the web: the
space left over on the right equals the margin on the left, so the margin follows from the page
width and the grid.

That is not a shortcut — it is a correction. Four of the ten catalogued geometries were
transcribed *wrong* at first, and the symmetry test caught every one.

Vertical margins are **not** symmetric and are not derived: a printer needs more clearance at
the leading edge than the trailing one.

```swift
sheet.fits          // does the grid actually fit the page it claims?
sheet.gapX          // pitch minus label — the bit that gets forgotten
sheet.perSheet      // columns × rows
```

`fits` proves a geometry is self-consistent, which catches a transposed digit. It cannot catch
a wrong number that happens to fit. **Print one sheet on plain paper with `outline` on and hold
it against the real stock before committing a box.** That is cheap; a box is not.

## Stock

Ten codes, A4 and US Letter: address (L7160, L7163, 4450, 5160), product (L7165, L7159), small
and price (L7651), round stickers (L7780), large (5163) and name badges (5395). Any geometry
can be built by hand in millimetres or inches.

## Nothing is cut

Text is never shortened to fit a label. It is set as large as twelve points allows,
shrinks half a point at a time to six with each line kept whole, and only then wraps
onto more lines — a long URL breaks mid-word rather than running over the die cut.
When a label cannot hold its text even wrapped at six points, the text is printed whole,
hung from the top so the first line stays on the label, and you are told:

```swift
let pdf = try LabelRenderer.render(labels, on: sheet)
for warning in LabelRenderer.warnings(labels, on: sheet, verifying: pdf) {
    print(warning)   // Label 3 (Ada Lovelace): the text does not fit L7651 even wrapped at 6 pt; …
}
```

`warnings(_:on:style:)` checks the layout: text that does not fit, and barcodes, QR codes
and images that could not be drawn. `verifying:` also asks the finished document — every
line of every label is looked for on the drawn page, in order, and characters the fonts
cannot draw (printed as `?`) are reported. An explicit `fontSize` is honoured: it wraps
if it must, and is reported if it still cannot fit.

A Cyrillic or Greek address needs a font that has it — `render(…, font:)` takes a
TrueType file, used only for the lines that need it:

```swift
let font = try EmbeddedFont.load(URL(fileURLWithPath: "/System/Library/Fonts/Supplemental/Arial Unicode.ttf"))
let pdf = try LabelRenderer.render(labels, on: sheet, font: font)
```

## Part-used sheets

The thing anybody with a drawer of half-used stock actually wants:

```swift
LabelRenderer.render(labels, on: sheet, startAt: 6)   // the first six are gone
```

Counted left to right and top to bottom, the way you count them holding the sheet.

## Requirements

macOS 14+ / iOS 17+, Swift 6.2. Built on
[swift-text-pdf](https://github.com/arraypress/swift-text-pdf) — no other dependency, no
network, no keys.

## Installation

```swift
.package(url: "https://github.com/arraypress/swift-label-pdf.git", from: "0.1.0")
```

## The CLI

[`label`](https://github.com/arraypress/swift-label-cli) is this library as a command-line tool.

## License

MIT
