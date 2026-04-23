import AppKit
import Foundation

/// Custom `NSTextLayoutFragment` that renders one row of a GFM table
/// as part of a visual grid. Reads its drawing data from the
/// `TableRowAttachment` attached to the row's source range via
/// `TableAttributeKeys.rowAttachmentKey`.
///
/// Separator rows (`|---|---|`) render as a header/body divider rule
/// with ~2pt height. Header and body rows render their cells using
/// the shared `TableLayout`'s pre-rendered attributed strings.
final class TableRowFragment: NSTextLayoutFragment {
    private let attachment: TableRowAttachment

    init(textElement: NSTextElement,
         range: NSTextRange?,
         attachment: TableRowAttachment) {
        self.attachment = attachment
        super.init(textElement: textElement, range: range)
    }

    required init?(coder: NSCoder) {
        fatalError("TableRowFragment does not support NSCoder")
    }

    /// Height claim — TextKit 2 uses this to flow subsequent content.
    override var layoutFragmentFrame: CGRect {
        let base = super.layoutFragmentFrame
        let h: CGFloat
        switch attachment.kind {
        case .separator:
            h = 3 // just enough for the divider rule
        case .header, .body:
            let idx = attachment.cellContentIndex ?? 0
            h = idx < attachment.layout.rowHeight.count
                ? attachment.layout.rowHeight[idx]
                : 0
        }
        return CGRect(x: base.origin.x, y: base.origin.y,
                      width: attachment.layout.totalWidth, height: h)
    }

    override var renderingSurfaceBounds: CGRect {
        CGRect(origin: .zero,
               size: layoutFragmentFrame.size)
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        let frame = CGRect(origin: point, size: layoutFragmentFrame.size)
        context.saveGState()
        defer { context.restoreGState() }

        switch attachment.kind {
        case .separator:
            drawSeparator(in: frame, context: context)
            drawVerticalDividers(in: frame, context: context)
        case .header, .body:
            drawCells(in: frame, context: context)
            drawVerticalDividers(in: frame, context: context)
            drawRowDivider(in: frame, context: context)
        }
        if attachment.isFirstRow { drawTopBorder(in: frame, context: context) }
        if attachment.isLastRow { drawBottomBorder(in: frame, context: context) }
    }

    // MARK: - Drawing

    private func drawSeparator(in frame: CGRect, context: CGContext) {
        context.setFillColor(attachment.layout.separatorColor.cgColor)
        let lineRect = CGRect(x: frame.origin.x,
                              y: frame.origin.y + 1,
                              width: attachment.layout.totalWidth,
                              height: 1)
        context.fill(lineRect)
    }

    /// Thickness for the four outer borders (top, bottom, leading,
    /// trailing).
    private static let outerBorderThickness: CGFloat = 1.25
    /// Thickness for inter-column dividers.
    private static let innerDividerThickness: CGFloat = 1

    private var outerBorderColor: CGColor {
        NSColor.labelColor.withAlphaComponent(0.6).cgColor
    }

    private var innerDividerColor: CGColor {
        attachment.layout.separatorColor.withAlphaComponent(0.35).cgColor
    }

    private func drawVerticalDividers(in frame: CGRect, context: CGContext) {
        let layout = attachment.layout
        let outerT = Self.outerBorderThickness
        let innerT = Self.innerDividerThickness

        // Leading outer edge.
        context.setFillColor(outerBorderColor)
        context.fill(CGRect(x: frame.origin.x,
                            y: frame.origin.y,
                            width: outerT,
                            height: frame.height))

        // Inter-column dividers (skip leading and trailing edges).
        context.setFillColor(innerDividerColor)
        var x = frame.origin.x
        for (i, width) in layout.contentWidths.enumerated() {
            x += layout.cellInset.left + width + layout.cellInset.right
            if i < layout.contentWidths.count - 1 {
                context.fill(CGRect(x: x,
                                    y: frame.origin.y,
                                    width: innerT,
                                    height: frame.height))
            }
        }

        // Trailing outer edge.
        context.setFillColor(outerBorderColor)
        context.fill(CGRect(x: frame.origin.x + layout.totalWidth - outerT,
                            y: frame.origin.y,
                            width: outerT,
                            height: frame.height))
    }

    private func drawTopBorder(in frame: CGRect, context: CGContext) {
        context.setFillColor(outerBorderColor)
        context.fill(CGRect(x: frame.origin.x,
                            y: frame.origin.y,
                            width: attachment.layout.totalWidth,
                            height: Self.outerBorderThickness))
    }

    private func drawBottomBorder(in frame: CGRect, context: CGContext) {
        context.setFillColor(outerBorderColor)
        context.fill(CGRect(x: frame.origin.x,
                            y: frame.origin.y + frame.height - Self.outerBorderThickness,
                            width: attachment.layout.totalWidth,
                            height: Self.outerBorderThickness))
    }

    private func drawRowDivider(in frame: CGRect, context: CGContext) {
        // Subtle horizontal line at the bottom of every body row
        // (and the header row). The final row's explicit bottom
        // border overdraws this same line at full opacity.
        context.setFillColor(attachment.layout.separatorColor
            .withAlphaComponent(0.25).cgColor)
        context.fill(CGRect(x: frame.origin.x,
                            y: frame.origin.y + frame.height - 1,
                            width: attachment.layout.totalWidth,
                            height: 1))
    }

    private func drawCells(in frame: CGRect, context: CGContext) {
        guard let idx = attachment.cellContentIndex,
              idx < attachment.layout.cellContentPerRow.count
        else { return }

        let layout = attachment.layout
        let cells = layout.cellContentPerRow[idx]
        let inset = layout.cellInset

        // Faint background for header row so it stands apart.
        if attachment.kind == .header {
            context.setFillColor(NSColor.secondaryLabelColor
                .withAlphaComponent(0.08).cgColor)
            context.fill(frame)
        }

        for (col, cell) in cells.enumerated() where col < layout.contentWidths.count {
            let columnWidth = layout.contentWidths[col]
            let columnX = frame.origin.x + layout.columnLeadingX[col]
            let cellOrigin = CGPoint(x: columnX,
                                     y: frame.origin.y + inset.top)
            // Align cell text within its column.
            let drawX = cellOrigin.x + horizontalOffset(for: cell,
                                                       column: col,
                                                       width: columnWidth)
            let drawSize = CGSize(width: columnWidth, height: frame.height - inset.top - inset.bottom)
            let drawRect = CGRect(origin: CGPoint(x: drawX - cellOrigin.x + cellOrigin.x,
                                                  y: cellOrigin.y),
                                  size: drawSize)
            // Push a graphics context so cell.draw can use AppKit.
            NSGraphicsContext.saveGraphicsState()
            let gc = NSGraphicsContext(cgContext: context, flipped: true)
            NSGraphicsContext.current = gc
            cell.draw(with: drawRect,
                      options: [.usesLineFragmentOrigin, .usesFontLeading],
                      context: nil)
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    private func horizontalOffset(for cell: NSAttributedString,
                                  column: Int,
                                  width: CGFloat) -> CGFloat {
        guard column < attachment.layout.alignments.count else { return 0 }
        let alignment = attachment.layout.alignments[column] ?? .none
        switch alignment {
        case .none, .left:
            return 0
        case .center:
            let size = cell.size()
            return max(0, (width - size.width) / 2)
        case .right:
            let size = cell.size()
            return max(0, width - size.width)
        }
    }
}
