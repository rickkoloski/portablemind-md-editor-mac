#!/usr/bin/env swift
//
// D24 Phase 1 Spike — validate `byTruncatingTail` multi-line behavior on TK1 cells.
//
// Offscreen / programmatic. No NSWindow, no NSTextView, no NSApplication.shared
// frontmost. Builds NSTextStorage + NSLayoutManager + NSTextContainer directly,
// forces layout at three container widths, dumps per-line fragment info to
// stdout, and renders PNGs via NSBitmapImageRep + NSGraphicsContext.
//
// Run from this directory:
//   swift run_spike.swift > results/run.log
//
// See README.md for the four behaviors this spike is validating and the
// GREEN/YELLOW/RED decision criteria.
//

import AppKit
import CoreText
import Foundation

// ---------------------------------------------------------------------------
// Test fixtures
// ---------------------------------------------------------------------------

struct Cell {
    let name: String
    let content: String
}

let cells: [Cell] = [
    Cell(name: "normal", content:
        "This is ordinary multi-paragraph prose intended to wrap at word boundaries " +
        "across several lines. There are no abnormally long tokens; every word is " +
        "shorter than the narrowest container width tested. We expect TextKit to " +
        "place line breaks between words and never invoke truncation at all."
    ),
    Cell(name: "longUrl", content:
        "https://example.com/very-long-unbreakable-token-with-no-whitespace-or-hyphens-that-textkit-cannot-split-on-word-boundaries-because-it-is-a-single-contiguous-token-of-considerable-length-stretching-well-past-typical-column-widths"
    ),
    Cell(name: "mixed", content:
        "Here is ordinary leading text that should wrap normally. Then comes the " +
        "URL: https://example.com/very-long-unbreakable-token-with-no-whitespace-or-hyphens-that-textkit-cannot-split-on-word-boundaries-because-it-is-a-single-contiguous-token-of-considerable-length-stretching-well-past-typical-column-widths " +
        "and after the URL there is more ordinary trailing text that should also " +
        "wrap normally without being affected by the truncation that may have hit " +
        "the URL line above it."
    ),
]

let widths: [CGFloat] = [600, 400, 280]
let font = NSFont.systemFont(ofSize: 14)

enum Mode: String, CaseIterable {
    case wordWrap        // control: pure multi-line word wrap
    case truncTailInf    // Q8 claim: byTruncatingTail with infinite container height
    case truncTailFinite // variant: byTruncatingTail with a tall but finite container height
}

// ---------------------------------------------------------------------------
// Layout + dump per cell × width
// ---------------------------------------------------------------------------

struct LineInfo {
    let index: Int
    let fragmentRect: CGRect
    let usedRect: CGRect
    let charRange: NSRange
    let text: String
}

func layout(content: String, width: CGFloat, mode: Mode) -> (NSLayoutManager, NSTextContainer, NSTextStorage, [LineInfo]) {
    let paragraphStyle = NSMutableParagraphStyle()
    switch mode {
    case .wordWrap:
        paragraphStyle.lineBreakMode = .byWordWrapping
    case .truncTailInf, .truncTailFinite:
        paragraphStyle.lineBreakMode = .byTruncatingTail
    }

    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .paragraphStyle: paragraphStyle,
        .foregroundColor: NSColor.black,
    ]
    let attr = NSAttributedString(string: content, attributes: attrs)

    let containerHeight: CGFloat
    switch mode {
    case .truncTailFinite: containerHeight = 10_000   // tall but finite
    default:               containerHeight = .greatestFiniteMagnitude
    }

    let storage = NSTextStorage(attributedString: attr)
    let lm = NSLayoutManager()
    let tc = NSTextContainer(size: CGSize(width: width, height: containerHeight))
    tc.lineFragmentPadding = 0
    tc.widthTracksTextView = false
    tc.heightTracksTextView = false
    tc.maximumNumberOfLines = 0   // explicit: no line cap

    storage.addLayoutManager(lm)
    lm.addTextContainer(tc)
    lm.ensureLayout(for: tc)

    var lines: [LineInfo] = []
    var glyphIdx = 0
    var lineIdx = 0
    let glyphCount = lm.numberOfGlyphs
    while glyphIdx < glyphCount {
        var lineGlyphRange = NSRange()
        let frag = lm.lineFragmentRect(forGlyphAt: glyphIdx, effectiveRange: &lineGlyphRange)
        let used = lm.lineFragmentUsedRect(forGlyphAt: glyphIdx, effectiveRange: nil)
        let charRange = lm.characterRange(forGlyphRange: lineGlyphRange, actualGlyphRange: nil)
        let safe = NSRange(location: charRange.location, length: min(charRange.length, (content as NSString).length - charRange.location))
        let text = (content as NSString).substring(with: safe)
        lines.append(LineInfo(index: lineIdx, fragmentRect: frag, usedRect: used, charRange: safe, text: text))
        glyphIdx = NSMaxRange(lineGlyphRange)
        lineIdx += 1
    }
    return (lm, tc, storage, lines)
}

// ---------------------------------------------------------------------------
// Main loop — stdout-only. PNG rendering omitted; per-line fragment data is
// the authoritative evidence and the offscreen NSBitmapImageRep render path
// produced blank bitmaps without further plumbing not worth the spike budget.
// If a visual cross-check is needed, fall back to the documented visual spike
// with NSApp.setActivationPolicy(.accessory) per the spike README.
// ---------------------------------------------------------------------------

print("# D24 phase 1 spike — byTruncatingTail multi-line behavior")
print("# Font: \(font.fontName) \(font.pointSize)pt")
print()

for mode in Mode.allCases {
    print("##############################################################")
    print("## MODE: \(mode.rawValue)")
    print("##############################################################")
    print()

    for cell in cells {
        for width in widths {
            let header = "=== mode=\(mode.rawValue)  cell=\(cell.name)  width=\(Int(width))pt  contentChars=\((cell.content as NSString).length) ==="
            print(header)

            let (lm, _, _, lines) = layout(content: cell.content, width: width, mode: mode)
            print("  numberOfGlyphs=\(lm.numberOfGlyphs)  lineCount=\(lines.count)")

            for line in lines {
                let endsWithEllipsis = line.text.hasSuffix("\u{2026}")
                let lineLen = line.text.count
                print(String(format: "  line[%02d]  fragRect=(x=%.1f y=%.1f w=%.1f h=%.1f)  used=(w=%.1f h=%.1f)  chars=%@  len=%d  endsWithEllipsis=%@",
                             line.index,
                             line.fragmentRect.origin.x, line.fragmentRect.origin.y,
                             line.fragmentRect.size.width, line.fragmentRect.size.height,
                             line.usedRect.size.width, line.usedRect.size.height,
                             NSStringFromRange(line.charRange) as NSString,
                             lineLen,
                             endsWithEllipsis ? "yes" : "no"))
                let preview = line.text.count > 120
                    ? String(line.text.prefix(120)) + "…[+\(line.text.count - 120)]"
                    : line.text
                print("            text=\(preview.debugDescription)")
            }

            print()
        }
    }
}

print("# done")
