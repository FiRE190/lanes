import AppKit

/// One line of a two-row cell: a coloured symbol (e.g. an arrow) followed by text.
struct IconRow {
    let symbol: String
    let symbolColor: NSColor
    let text: String
}

/// One block in the menu bar icon.
struct IconCell {
    enum Layout {
        case labeled(label: String, value: String)   // tiny coloured label above a bigger value
        case twoRows(top: IconRow, bottom: IconRow)  // two equal lines (e.g. read / write)
    }
    let layout: Layout
    let color: NSColor                 // value text colour
    /// Strings used to reserve a fixed width, so the icon doesn't jitter as numbers change.
    let widthSamples: [String]
    var labelColor: NSColor = .secondaryLabelColor
}

/// Draws the menu bar icon as real readable values, not abstract bars.
enum IconRenderer {
    private static let height: CGFloat = 22
    private static let gap: CGFloat = 9
    private static let labelFont = NSFont.systemFont(ofSize: 7.5, weight: .bold)
    private static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
    private static let rowFont = NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .medium)

    // The icon is redrawn only when its content changes (idle drives often show the same text).
    private static var cachedKey = ""
    private static var cachedImage: NSImage?

    static func image(cells: [IconCell]) -> NSImage {
        // Nothing selected in settings: show a small placeholder so the item stays clickable.
        let cells = cells.isEmpty
            ? [IconCell(layout: .labeled(label: "", value: "Lanes"), color: .labelColor, widthSamples: ["Lanes"])]
            : cells

        let key = cells.map { "\($0.layout)|\($0.color)|\($0.labelColor)" }.joined(separator: ";")
        if key == cachedKey, let cachedImage { return cachedImage }
        let image = render(cells)
        cachedKey = key
        cachedImage = image
        return image
    }

    private static func render(_ cells: [IconCell]) -> NSImage {
        let widths = cells.map(width(of:))
        let total = widths.reduce(0, +) + gap * CGFloat(cells.count - 1) + 4

        let image = NSImage(size: NSSize(width: total, height: height), flipped: false) { _ in
            var x: CGFloat = 2
            for (cell, w) in zip(cells, widths) {
                draw(cell, x: x, width: w)
                x += w + gap
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func width(of cell: IconCell) -> CGFloat {
        let font: NSFont
        switch cell.layout {
        case .labeled: font = valueFont
        case .twoRows: font = rowFont
        }
        var w = cell.widthSamples.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        if case .labeled(let label, let value) = cell.layout {
            w = max(w,
                    (label as NSString).size(withAttributes: [.font: labelFont]).width,
                    (value as NSString).size(withAttributes: [.font: valueFont]).width)
        }
        return ceil(w)
    }

    private static func draw(_ cell: IconCell, x: CGFloat, width: CGFloat) {
        switch cell.layout {
        case .labeled(let label, let value):
            let labelAttrs: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: cell.labelColor]
            let valueAttrs: [NSAttributedString.Key: Any] = [.font: valueFont, .foregroundColor: cell.color]
            if !label.isEmpty {
                let s = (label as NSString).size(withAttributes: labelAttrs)
                (label as NSString).draw(at: NSPoint(x: x + (width - s.width) / 2, y: 14), withAttributes: labelAttrs)
            }
            let s = (value as NSString).size(withAttributes: valueAttrs)
            (value as NSString).draw(at: NSPoint(x: x + (width - s.width) / 2, y: label.isEmpty ? 4 : 1),
                                     withAttributes: valueAttrs)
        case .twoRows(let top, let bottom):
            // Centre the ink inside the reserved width, so the icon's visual middle matches its
            // geometric middle (and the popover arrow) even when the numbers are short.
            let topString = rowString(top, textColor: cell.color)
            let bottomString = rowString(bottom, textColor: cell.color)
            let inkWidth = max(topString.size().width, bottomString.size().width)
            let inset = max(0, (width - inkWidth) / 2)
            topString.draw(at: NSPoint(x: x + inset, y: 11.5))
            bottomString.draw(at: NSPoint(x: x + inset, y: 0.5))
        }
    }

    private static func rowString(_ row: IconRow, textColor: NSColor) -> NSAttributedString {
        let result = NSMutableAttributedString(string: row.symbol + " ",
                                               attributes: [.font: rowFont, .foregroundColor: row.symbolColor])
        result.append(NSAttributedString(string: row.text,
                                         attributes: [.font: rowFont, .foregroundColor: textColor]))
        return result
    }
}
