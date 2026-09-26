# Tunables — knobs, not questions

Owner, 2026-09-26, on a pass that picked two numbers itself, marked them
tentative and said "they're easy to change": *"that's excellent. leaving
design knobs while not harking over details, just put sensible defaults and
enable enough DX that tweaking them is easy in the godot editor. most often an
exported variable, ideally with instant editor view feedback (if it's a visual
thing)."*

## Knob or fork?

**If changing it would move a file, a class, or which class owns a fact, it is
a decision — ask (in `/swarmify`) or follow the spec. If it changes a number on
something that already exists, it is a knob.** "Is there a cap?" is a
decision; "what is the cap?" is a knob. A number the owner already stated is
still a knob: their value is the default.

## What a knob gets

1. **A sensible default**, checked at both ends of its range (one node and
   two hundred, level 1 and 100). Say it is tentative and easy to change —
   in the Ready comment's **Knobs** section, or the drone's report.
2. **An `@export` on the owner of the value** — the `@tool` node or the
   `.tres` resource it belongs to. `@export_range(min, max, step)` when
   bounded (`'or_greater'` when the bound is soft). Not a `const`: a const is
   easy to change in code and invisible in the editor.
3. **Instant feedback, for a visual knob.** A setter that re-applies:

   ```gdscript
   @export_range(0, 12, 1) var h_padding: int = 5:
       set(v):
           h_padding = v
           _repaint()
   ```

   (`ui/common/key_chip.gd`, `ui/theme/glass_panel.gd`). The script is
   `@tool` so the setter runs in the editor. When the effect only shows in
   motion or in a composed scene, the knob is reachable from the relevant
   sandbox-host live tab (`docs/domain/sandbox-framework.md`).
4. **Tests assert what the knob parameterises** — the invariant, the ratio, a
   sweep over the range — never the literal default, so retuning never reds a
   test.

## Knobs with their own home

- **A stat rate** → a modifier's `value`, then a stat
  (`docs/domain/stat-knobs-and-bins.md`).
- **A glow** → a named tier (`Emissive.at()` / a `Tier*` variation), never an
  exported HDR float (`docs/domain/hdr-color.md`).
- **Per-instance shader variation** → `modulate` / UV / `INSTANCE_CUSTOM`,
  never a per-node uniform (`docs/domain/rendering-performance.md`).
- **A value several consumers must agree on** (a router and the thing that
  rebuilds its params by hand) → one owner exports it and the others read it
  from there; a second copy is the drift, not the knob.
