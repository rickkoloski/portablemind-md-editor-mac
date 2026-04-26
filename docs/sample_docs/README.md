# Sample documents

Hand-curated markdown samples for manual testing of md-editor-mac.
Open any of these via **File → Open** or:

```bash
./scripts/md-editor docs/sample_docs/sample-NN-thing.md
```

| Sample | Exercises | D-deliverable |
|---|---|---|
| `sample-01-headings.md` | H1–H6 hierarchy, heading-cursor reveal | D1, D2 |
| `sample-02-inline.md` | Bold / italic / inline code / link rendering + delimiter reveal | D2 |
| `sample-03-lists.md` | Bulleted + numbered lists | D2 |
| `sample-04-code.md` | Fenced code blocks (D8 Finding #4 — fence reveal) | D2, D8 |
| `sample-05-large.md` | Render performance + scrolling on a real-world doc (40 KB+) | D9 (scroll-to-line), D10 (line numbers) |
| `sample-06-tables.md` | GFM tables, per-cell caret editing, double-click reveal | D8, D8.1, D12 |

## Adding a sample

Keep samples small and focused on a single feature where possible.
Use clear inline instructions ("click here", "press Tab", "select
across cells") so manual testers know what to verify. Cross-reference
the manual test plan in `docs/current_work/testing/dNN_*.md` for
formal validation steps.
