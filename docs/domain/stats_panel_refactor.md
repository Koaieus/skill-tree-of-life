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

## Decision (2026-06-26): KEEP TABS, fix the icon header

The current `TabContainer` is "cursed": each tab title is glyph **+ text**
(`"♥  Body"`), so the tab row overflows and collapses to ~2 visible tabs with
left/right **pagination arrows** — effectively tabs-inside-tabs. The fix that
the user wants (and that was prototyped in the AskUserQuestion) is **keep the
tabbed control** (one group visible at a time) but render **icon-only tab
headers with a hover tooltip** naming the group. With glyph-only titles all
tabs fit in one row — the pagination cursedness disappears. Panel may widen
slightly.

### Phase A — ship now (decided, low-risk)

1. Split `_TABS` into `{ id, name, glyph }`; render the `glyph` as the
   `TabContainer` tab title and set `set_tab_tooltip(i, name)`. (Glyphs stay
   unicode stopgaps — "swap to textures later" via `set_tab_icon`.)
2. Scene-ify the row construction: promote `_build_basic_row()` to a
   `stat_row.tscn` instantiated per basic stat (the bulk of the imperative
   `new()`-ing). `LabeledProgressBar` is already a scene; keep it.
3. Keep the **metadata-driven** content contract intact (the good part): what
   renders + order still come from `StatDef.display_type` / `display_order` /
   `display_group`. Adding a stat stays a one-`.tres` change.

### Phase B — design direction (OPEN, do NOT bake in yet)

The tab **taxonomy** is undecided. Options the user floated:
- Current 4 groups (≈ STR / DEX / INT / PER buckets).
- Transposed by niche: one tab listing all attributes, tabs split by how niche
  a stat is (**main | sub | rare**).
- 5 tabs, one per base attribute (STR / DEX / INT / WIS / PER).

User leans toward a small **2–3 tab** set:
- **Tab 1 — Overview (in order):** health, mana, movement, level, XP, XP/turn,
  SP, DP, AP, then the five base attributes.
- **Tab 2 — Combat:** max blade size, blade damage, ranged damage, ranged
  range, armor, …
- **Tab 3 — Magic / niche:** magic stats; and very niche stats that sit at
  default 99% of the time (e.g. `magic_hop_count_bonus`) — candidates to
  **hide unless non-default**.

Deeper considerations to spin into follow-ups (NOT in Phase A):
- **`*_per_turn` joining:** render a per-turn stat *under* its parent as a
  right-aligned, dimmed `+X / turn` (the `/ turn` more dimmed) — clean visual
  pairing. (Alt: keep all per-turn stats in one group.)
- **Turn-budget stats (SP/DP/AP/Movement)** likely deserve *specialized* UI
  outside the panel (gameplay variables, not just stats) — possibly *both* a
  specialized widget AND a panel entry. May warrant a **custom display scene**
  per stat (XP, SP) — the `StatDef.widget_scene` escape hatch noted in
  `.claude/rules/stats-system.md` "Display contract".
- **`level`:** the not-yet-implemented level (whose +1 replenishes the XP pool)
  — make it an internal stat on XP exposed as a `StatBoard` getter? (open: is
  that clean?)
- **Derived `blade_damage` stat:** today melee damage is inlined in the damage
  calc. Promote it to a real stat with a formula modifier (e.g. `+1 per 10
  STR`) so it decouples logic AND gives a clean buff interface — e.g. a node
  with a spike addon raises its *local* `blade_damage`. (Aligns with the
  LocalStat pattern; see stats-system rule.) Strong candidate, but it's a
  stat-system change, not a panel change → its own issue.

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
