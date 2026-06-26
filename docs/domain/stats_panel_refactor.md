# StatsPanel refactor — composition + icon-tab bug

> Status: **planned, not started.** Written as a resumable brief so a token
> crunch mid-implementation doesn't lose the analysis. Engineering doc
> (distinct from `docs/design/`).

## The problem

`ui/stats_panel.gd` (`StatsPanel extends VBoxContainer`) builds its entire UI
**imperatively in `_rebuild()`**: it `new()`s a `TabContainer`, loops `_TABS`
to `new()` a `VBoxContainer` per tab, then per stat `new()`s an `HBoxContainer`
+ two `Label`s (`_build_basic_row`) or a `LabeledProgressBar`. The only thing
that *is* a scene today is `LabeledProgressBar` (`ui/labeled_progress_bar.tscn`).

Two things are wrong with that:

1. **Manual composition that should be scene instantiation.** Rows, tabs, and
   the container are hand-assembled in code. This is the same anti-pattern the
   rest of the UI avoids (`%NodeName` unique-name scene composition, see
   CLAUDE.md "Godot conventions"). It should instead instantiate scenes.
2. **Tabs are stacked in a `TabContainer` (one visible at a time).** The user
   wants the **4 content tabs side by side** — they all fit. So the
   `TabContainer` (single-pane, tab-switch) model is wrong; we want 4
   simultaneously-visible panels (an HBox/Grid of tab-scenes), not a tabbed
   pager.

### The icon-tab bug (the concrete fix the user called out)

`_TABS` titles are glyph **+ text**: `"♥  Body"`, `"⚔  Combat"`, `"🧠 Mind"`,
`"👁 Sense"`, `"···"`. These strings become the `TabContainer` tab labels (and
also, note, `VBoxContainer.name` — line 66 `vb.name = tab_def["title"]`, which
is a separate smell: the title doubles as the node name).

**Desired behaviour:** each tab header shows **only the icon**, and **hovering**
it shows a **tooltip** with the tab name ("Body", "Combat", …). Today the text
still renders next to the glyph and there's no tooltip.

Root locus: `_TABS` (lines 21-27) carries a combined `title`; the
`TabContainer` renders that string verbatim. Fixing requires separating
`icon` from `name`, rendering icon-only headers, and setting
`tooltip_text`/hover on each header.

## Proposed shape

Decompose into scenes (names indicative):

- `stats_panel.tscn` — root container. Lays out the 4 stat-group panels **side
  by side** (HBoxContainer or GridContainer), plus the misc/`···` catch-all
  (hidden when empty, as today line 79-83).
- `stat_group_panel.tscn` (+ `.gd`) — one per `display_group` (`body`,
  `combat`, `mind`, `sense`, `misc`). Owns its icon-only header with
  `tooltip_text`, and a VBox of rows. Replaces the per-tab `VBoxContainer` +
  the header-string coupling.
- Row scenes — promote `_build_basic_row()` to a `stat_row.tscn`
  (`Name`/`Value` labels). `LabeledProgressBar` already a scene; keep it.

Keep the **metadata-driven** contract intact (the genuinely good part): which
stats render and in what order still comes from `StatDef.display_type` /
`display_order` / `display_group` (`_collect_visible_defs`, sort, dispatch).
Adding a stat stays a one-`.tres` change. The refactor is about *how the tree
is built* (scenes vs `new()`), not *what drives content*.

Tab metadata should split `glyph`/`icon` from the human `name`:

```gdscript
const _TABS := [
    { "id": &"body",   "name": "Body",   "icon": "♥" },   # or a Texture later
    ...
]
```

Header renders `icon` only; `tooltip_text = name`.

## Watch-outs (carried from the rules)

- `@tool` script — runs in editor (`_ready` early-returns on
  `Engine.is_editor_hint()`). New scenes must behave under `@tool` too.
- After introducing new `class_name`s (e.g. `StatGroupPanel`, `StatRow`),
  refresh the class cache (`godot --headless --editor --quit`) then
  `git status`/`git diff scenes/ '*.tres'` — the editor pass can mutate
  touched scenes/.tres (see `.claude/rules/godot-workflow.md`).
- Signal wiring (`_connect_board` / `_refresh`) and the `_rows` dict are reused
  as-is; just retarget at the new row scene instances. `_disconnect_board` is
  still a no-op (documented leak note lines 180-186).
- The misc/`···` tab is the fallback for unknown `display_group`; preserve the
  hide-when-empty behaviour.

## Acceptance

- 4 group panels visible side by side; misc hidden when empty.
- Tab headers show icon only; hovering shows the group name as a tooltip.
- Panel still populates from `StatBoard` + `StatDef` metadata with no per-stat
  code change (drop a `.tres`, set `display_group`/`display_order`/`display_type`).
- No regression in PROGRESS (pool) vs BASIC (scalar) row rendering.
