# Writer brief — elements split body pass (#1716)

Work in the checkout you were started in (a git worktree); all paths are relative to it. Other writers are editing sibling files in the same checkout right now: edit ONLY your own file, run no git command that changes state (no add, commit, stash, checkout, restore), and do not reformat.

The design is settled (ADRs 0072, 0075, 0081-0085). Re-decide nothing. If something your body needs is genuinely not decided anywhere, do not invent it: report it as a gap.

Read, in this order, and nothing more than you need:
1. `docs/handoffs/elements-split/DELTA.md` — Part A (the calls) and your row of Part B (quoted in your prompt).
2. Your body file.
3. In `docs/design/elements.md`, ONLY the sections under the headings your Part A items name (find them with `grep -n '^#' docs/design/elements.md`; DELTA's line numbers are approximate).
4. ADRs `docs/adr/0083*`, `0084*`, `0085*` (the ones your items cite).
5. `.claude/skills/spec/SKILL.md` — the body format (the `## Acceptance spec` sections). Your body follows it.

Rules:
- Change content only. Do NOT touch `elements.md` line ranges or drift stamps anywhere in the body, even where they are now wrong; a later pass re-places them. (A new body or wholesale rewrite: write ranges as best you can and keep the stamp format of a sibling body; they will be re-placed too.)
- Quote the owner only verbatim from `docs/design/elements.md` (with the date the doc gives). No paraphrase inside quote marks. Drop a quote the doc no longer holds.
- Cite a call by the ADR that now carries it (DELTA Part A), with its § number.
- Every acceptance item must be testable by a cold implementer who has only the body and its reading list: name the observable, the numbers, the test seam.
- One decision has one owner. If your body needs a call another body owns, point at that unit (as `{name}`, the placeholder style the bodies already use), do not restate it as your own Decision.
- The "Still open" items in DELTA stay open: carry them as a knob with its tentative default or as a NOTES line.

Final message, under 150 words: what changed; what you could not place; any contradiction with another unit; gaps for the owner (if any). Nothing else.
