# Table samples

This file exercises the GFM table rendering and per-cell editing
behavior shipped in D8, D8.1, and D12.

---

## A simple 2-column table

| Field | Value |
|---|---|
| Name | Avery |
| Role | Builder |
| Status | Active |

Try clicking inside any cell — the caret should land at the click
position inside the cell. Tab moves to the next cell; Right Arrow at
the end of a cell jumps to the start of the next cell.

---

## 3-column with mixed content widths

| Item | Description | Status |
|---|---|---|
| Build | Compile + link the Swift package | ✅ Pass |
| Format | Run swift-format on `Sources/` | ⚠️ Warnings |
| Lint | Run SwiftLint with default rules | ❌ Fail |
| Deploy | Sign + notarize + upload to Sparkle | ⏸ Pending |

Test: select across two cells; the highlight should appear in BOTH
cells with the inter-cell pipe character not highlighted.

---

## Empty cells

| Column A | Column B | Column C |
|---|---|---|
| filled | | filled |
| | filled | |
| | | |
| filled | filled | filled |

Click into an empty cell and start typing — content appears in that
cell. The cell's column widens dynamically based on its widest
content (per `TableLayout.contentWidths` cap).

---

## Wider table — 5 columns

| ID | Name | Email | Role | Updated |
|---|---|---|---|---|
| 1 | Alice Anderson | alice@example.com | admin | 2026-04-22 |
| 2 | Bob Brown | bob@example.com | editor | 2026-04-23 |
| 3 | Carol Carter | carol@example.com | viewer | 2026-04-24 |
| 4 | Dave Davis | dave@example.com | editor | 2026-04-25 |

Test: Tab through every cell of a row. At the last cell, Tab moves to
the next row's first cell.

---

## Column alignment

| Left aligned | Centered | Right aligned |
|:---|:---:|---:|
| Plain text | mid | trailing |
| Anchored left | x | 100 |
| Two words here | y | 99 |

---

## Special-character content

| Symbol | Description |
|---|---|
| `pipe-escape` | Some \| escaped pipe inside a cell |
| `bold` | Looks like **bold** in source |
| `code` | Looks like `code` in source |
| `unicode` | A few emoji — 🚀 ✅ ⚠️ 🌱 |

Note: D12's V1 cell renderer shows source characters verbatim — bold,
italic, inline-code, and link styling inside cells are not rendered
yet. Cell text remains plain.

---

## Reveal mode (D12 secondary trigger)

Double-click any cell above to drop the whole table to pipe-source
mode. Click outside the table to return to grid rendering. Single-
click does not trigger reveal — that's per-cell caret editing.

---

## Tables sandwiched between body text

Some prose before the table. Just so we can verify scrolling and
positioning work when tables aren't the first thing in the document.

| A | B | C |
|---|---|---|
| 1 | 2 | 3 |

More prose after the table. The cursor should be able to leave the
table cleanly via arrow keys (Up arrow at top row → exits to the
prose above; Down at bottom row → exits to the prose below).

---

## Two adjacent tables

| Q1 | Q2 | Q3 | Q4 |
|---|---|---|---|
| Plan | Build | Test | Ship |

Some text between.

| Phase | Owner |
|---|---|
| Discovery | Rick |
| Design | Rick |
| Build | CC |
| Validate | CC + Rick |

Test: double-click reveal on the first table should NOT reveal the
second; the two tables track reveal state independently.

---

## Long single-cell content

| Heading | Text |
|---|---|
| Wrapping test | This is a long string of text that should exceed the natural single-line width and force wrapping inside the cell, which exercises the multi-line cell content path in `TableLayout.rowHeight`. |

The row height adjusts to accommodate wrapped content per column.
