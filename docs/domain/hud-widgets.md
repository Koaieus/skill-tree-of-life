# HUD widgets — per-unit contracts

Contracts for the self-contained `ui/` units that `HudRoot` composes. The shell
is `ui/hud/hud_root.gd`; the tooltip fan is `docs/domain/tooltip-fan.md`.

## GainedModifierToast (`ui/gained_modifier_toast/`)

"You just got these." When the player allocates a node, shows the node's actual
`ModSlabRow` slabs beside the Hero avatar — staggered in, held long enough to
read, then slid INTO the avatar while fading (absorption). Allocation-only by
design (loot and level-up gains are out of scope); batch-per-allocation, not
per-modifier.

**Its own layer, deliberately NOT routed through `FloaterDirector` /
`FloaterToaster`**: different dwell (much longer, meant to be READ), anchor (the
avatar, not the event position) and exit (directional absorb, not
drift-and-fade). Sharing the floater queue would force its timing model onto a
surface that exists to be slower.

**Standalone**: instantiate, set `float_anchor`, call `show_gains`. No HUD or
`AllocationSystem` wiring is baked in.

**Reuse contract.** Rows are bare `ModSlabRow` instances — this layer BINDS them
(`bind(m)`) and DRIVES their reveal (`set_progress(t)`) itself, per the "content
rows take set_progress, driven by their panel" rule (`docs/domain/tooltip-fan.md`).

**Mount** (a composer does this; the scene does not wire itself):

- Add an instance under `HudRoot` (wherever the Hero avatar lives) as a sibling
  of `HeroSigilCard`, so it draws on top.
- Set `float_anchor = hud_root.hero_sigil_card.float_anchor` — the same DI pattern
  as `scenes/game_root.gd`'s `floater_director.player_anchor`.
- Connect `AllocationSystem.allocated(node, entity, forced)` and call
  `toast.show_gains(node.modifiers)`, gated on `entity ==` the player entity (NPC
  allocations must not fire it) and `not forced` (the existing convention for
  cosmetic gain reactions: a forced spawn/procgen allocation is not a player
  choice and has nothing to "just get").

**Concurrent batches, never replace.** A rapid second allocation must NOT cut off
the stack still being read. Each `show_gains` spawns an independent batch — its
own reveal, dwell and absorb timeline — appended BELOW the rows on screen. Batches
absorb independently, in whatever order their dwell finishes; `_reflow` slides the
remaining rows up to a contiguous stack. Nothing assumes batches finish in spawn
order.

## MagicBody (`ui/hud/command_tray/bodies/magic_body.gd`)

Magic tab content: the crucible. The vessel (`%SpellButton`, the equipped spell
full-bleed at `vessel_px`, an `ArcaneCircle` turning behind it) on the left, its
`InfusionSockets` fanned on an arc hugging its bottom edge, a circuit trace from
each filled socket down then right into its own line of the always-on
`CrucibleReadout` in the middle, and Launch bottom-right. Traces are
`CrucibleTraces.route` over the laid-out rects: socket 0 sits rightmost
(`InfusionSockets.right_to_left`) and the readout lists its line topmost, so they
nest without crossing.

The readout owns its hover, wheel-preview and Shift state; the body only forwards
socket hovers and wheel-wedge hovers to it. It scrolls inside `%ReadoutScroll`, so
its Shift expansion never grows the tray.

**The picker floats.** Pressing the vessel toggles `SpellPickMode` on the seat's
`ArmedStack` (`MagicMode.toggle_picker`). The spell bar lives in `%PickerPanel`, a
`top_level` panel whose bottom edge sits `picker_gap_px` above the body's top edge
and which grows upward over the graph. It is outside the body's layout, so it adds
nothing to the body's combined minimum size, shown or hidden. The STACK decides
visibility — shown iff a `SpellPickMode` is on the branch — so the body keeps no
open/closed state and every close (a pick, a hotkey, a graph click, right-click, a
launch) hides it for free.

**The spell bar is bounded, not merely wide.** A `Control` is clamped UP to its
combined minimum size, so a row of N fixed 96px buttons would set this body's min
width, and the spellbook grows through loot without bound. Two load-bearing
halves: `SpellPickerBar` is an `HFlowContainer` (min width = ONE button, overflow
wraps), and rows past `MAX_VISIBLE_ROWS` live inside `%SpellScroll`. A 20-spell
book costs the same width and height as a 3-spell one that already wrapped.

`%SpellScroll` uses `ScrollContainer.SCROLL_MODE_RESERVE`, NOT `AUTO`. Under
`AUTO` the scrollbar takes its 8px only once it appears, narrowing the bar at the
moment content overflows; a narrower flow container can wrap to one MORE row, so
the row count is not a pure function of spell count. `RESERVE` keeps the gutter
whether or not the bar shows: a single-pass fixed point for 8px of permanent
width. Verified on 4.7.1: inner width 292/292 under `RESERVE` where `AUTO` gives
300/292.

## HeroSigilCard (`ui/hud/hero_sigil_card/`)

Left column, top card: class emblem (spinning ring + glyph), level badge, entity
name + class subtitle, Health as a `PoolGauge` with a dimmed "+N/t" regen caption.
Also the floater-anchor origin for entity/core stat-change toasts
(`float_anchor`; `GameRoot` wires `FloaterDirector.player_anchor`).

**XP is not this card's business.** The gauge, its "+N XP" chip and the
level-replay state machine live in `XpTrack`. `XPRow` survives only as hidden,
deliberately UNBOUND scenery: a second binder on the same `xp` pool would run its
own sequencer and emit a second `level_reached`, which `LevelUpFlourish` would
stamp as "x2" for a single level. The level badge stays — `HudRoot` drives it from
`XpTrack.level_display_changed` via `show_level`, so badge, flourish and bar beat
together.

Root is a 0-margin `MarginContainer` (not a plain `Control`) so its reported
minimum size aggregates its children's — a plain `Control` reports (0,0), which
collapsed this card to zero height inside `HudRoot`'s `LeftColumnSlot`
`VBoxContainer` (shared bug across all HUD cards; see `combat_readout_card.gd`).

**The inner ring's door.** A left click anywhere on the card emits `ring_requested`
(`HudRoot` decides what opens); `%RingBadge` shows the hero's unspent
`ring_points.current` while it is > 0 and pops on `Events.ring_point_minted` for
that hero. The root STOPs mouse so a click never falls through to the board; every
decorative `Control` under it IGNOREs so the click reaches the root.

**The build it wears.** `%RingSilhouette`, a `read_only` `AspectWheel` over the
emblem (under the badges, so its hub names a hovered wedge over the sigil), shows
the hero's bought ring cells; it PASSes the mouse (hover names a wedge) and never
accepts a click. The emblem rim takes the most-invested sector's hue, the hero's
colour until a cell is bought. The cell table comes from `ring_system`, injected by
`HudRoot`; without one the wheel stays empty.

## MinimapPanel (`ui/hud/minimap_panel/`)

Bottom-left cluster: the whole board at a fixed scale, with fog, a live viewport
outline, and click/drag to move the camera.

**Three layers, split by redraw cadence** — the entire performance story at
500-2500 SkillNodes:

- `MinimapGraphLayer` — dots + edges. Rebuilt on topology/ownership change only,
  drawn in two batched calls. It self-shades against the vision field
  (`minimap_graph_fog.gdshader`), so a fogged node is drawn at alpha zero rather
  than relying on the fog quad above it.
- `FogLayer` — a `ColorRect` running `minimap_fog.gdshader`, sampling the same
  GLOBAL vision field `FogOverlay` writes each vision tick. Zero CPU: the minimap
  asks `VisionSystem` nothing.
- `MinimapViewportRectLayer` — the outline. The only thing that moves with the
  camera, and the only thing a pan invalidates.

**Extent** is the raw SkillNode AABB plus a few percent of breathing room, held
FIXED. It is NOT the camera's effective bounds (those rescale on every zoom step,
so the board would breathe under an outline that is itself resizing: the board
must hold still), and NOT the AABB grown by `GraphCamera.pan_margin_base` (pan
SLACK; at 400 world units a side it nearly tripled a typical extent and the board
drew at a third of the panel). The minimap frames the graph, not the camera's
freedom of movement.

The outline can therefore run off the board's edge when the camera is panned into
the slack (~350 world units), and at low zoom the view is simply wider than the
graph; `MapArea` clips the overhanging sides. **Owner call, 2026-08-24**, choosing
that over clamping the box or widening the board: *"Leave it clipped."* The box
tells the truth — you really are looking past the graph, and the side that goes
missing is which way you overshot.

Out of v0: sensed-only blips, archetype fill + ownership ring, per-entity
territory boxes, combat pings, minimap zoom levels. Each is an added layer or a
swapped colour helper, not a rewrite.

### MinimapViewportRectLayer — device-pixel snapping

The white outline of what the main view covers. Split out of `MinimapGraphLayer`
because its cadence is the opposite: it moves on every pan and breathes through
every zoom tween while the graph is static for whole turns. It holds a rect in
MINIMAP-LOCAL space, not a camera — `MinimapPanel` owns the world mapping.

**The box is four filled spans, snapped to DEVICE pixel boundaries.**

1. A stroked `draw_rect` centres its hairline on the path, so an edge on a pixel
   boundary covers half of each neighbouring column and reads as nothing.
2. Snapping to whole LOCAL pixels does not fix that: `project.godot` sets
   `stretch/mode = "canvas_items"` against a 1440x960 base, so at any other window
   size the HUD is scaled by a non-integer factor.
3. Nor does a span one device pixel WIDE: Godot's 2D canvas does not antialias
   filled geometry — a pixel is covered iff its CENTRE falls inside the span, and
   a span landing halfway between two centres contains neither. This produced
   "fault lines" at a fixed set of screen positions per axis, same x for left and
   right edges, unaffected by panning: a property of the coordinate, not the edge.
4. Snapping against `CanvasItem.get_global_transform_with_canvas` is the wrong
   grid: it stops at the canvas and excludes the viewport's stretch (a 1440x960
   canvas in a 1440x932 window reports scale (1, 1) while the screen scales by
   ~0.971). `CanvasItem.get_screen_transform` goes all the way to the screen.

So the box is transformed into device space, snapped to integers there, and the
spans are transformed back (`_draw`): each covers exactly one full pixel column or
row and contains its centre by construction, at any window size and camera
position.

## SpellPickerBar / SpellPickerButton (`ui/spell_picker_bar/`)

The bar renders the player `SpellBook` as a row of `SpellPickerButton`s;
selecting one routes through `spell_selected`, which UIRoot forwards to
`MagicMemory.selected_spell`. It self-syncs two independent gates on each button:
the bar-wide act gate (not your turn / no AP: grey AND unclickable), and whether
ANY owned node clears the spell's `min_degree`. The latter goes grey but STAYS
clickable so the press can float its own denial.

**`min_degree` is a territory question, not a source question.** There is no
pre-picked cast-from node, so the gate asks `SpellBook.eligible_sources` — the
predicate `SpellTargetUnion` builds its source set from — so the picker and the
highlights can never disagree about whether a spell is castable.

**`HFlowContainer`, not `HBoxContainer`.** A `Control`'s rect is clamped UP to
`get_combined_minimum_size`, so anchors lose to content min size. An HBox of N
fixed 96px buttons has min width `N * 96 + (N - 1) * sep` (824px at 8 spells),
which shoves the Command Tray out from under its slot. A flow container's min
width is ONE button; overflow becomes rows, and the owning body caps rows at two
and scrolls past them (see MagicBody).

**No layout feedback loop.** `_relayout` picks the button size from the bar's
*available* width (`size.x`, handed down by the tray) versus what the book needs at
full size — never from the bar's own minimum size. The `.tscn` pins
`custom_minimum_size.x` at `FULL_BUTTON_PX`, a constant the chosen size cannot
move, so the decision is a pure function of (available width, spell count), not a
fixed-point search.

**Number keys.** Tile N carries the keycap for `ui_select_spell_N`, derived from
its POSITION via `PlayerInputController.spell_keycap` — the book is loot-driven and
reorders. Spells past the ninth get no chip and stay mouse-only; key handling is in
`PlayerInputController`, gated on MAGIC being the live mode.

### SpellPickerButton

A toggle button (radio-managed by the bar's `ButtonGroup`) rendering a spell card:
top inset with one tick per `SpellDef.min_degree`; the spell icon full-bleed in its
square (or the noun letter via `IdentityBadge.letter_of`; the tile is identity
enough, so no `IdentityBadge` frames it); the name label; one `IdentityChip` per
innate intake (aspect glyph + count; a non-1 ingest rate is named only in
`tooltip_text`, e.g. `poison x2`).

Same shader scaffolding as `AttackModeButton` — the bg shader does rounded-rect
rendering, mouse-proximity glow, rim, breathing pulse when active, and a
desaturated/dimmed disabled state; the text shader gives the name a soft halo +
tint blend. Hover / pressed / disabled route into shader strength uniforms via
tweens. On hover it emits `Events.spell_hovered` / `spell_unhovered` so the
floating `SpellTooltip` (mounted in `HudRoot`) shows.

**Two independent gates.** Both grey the same shader term, but only one flips the
engine `Button.disabled`: `set_actionable` (bar-wide "your turn, AP left"; truly
disabled — the whole bar is dimmed, nothing to explain) and `set_has_caster` (any
owned node clears `min_degree`; grey but CLICKABLE). The caster gate stays
clickable because a disabled `Button` swallows the very click its denial toast
needs.

`spell_picked` is the gated report of a press: `SpellPickerBar` connects to THAT,
never to the raw `BaseButton.pressed`, because two independent listeners on one
native signal can't have one veto the other, and only this button knows whether
its own press counts as a pick or a denial.

## StatusOverlay (`ui/status_overlay/status_overlay.gd`)

Every status readout on a bar: the projected-damage segment and the icon row, for
ONE host's rows. Composed as a full-rect child of the bar it annotates; the bar
owns the wiring.

- **Host.** `bind` takes a `NodeCombat` or an `EntityCombat` (both answer
  `get_statuses()` and `projected_status_damage()`) plus the signal announcing a
  row change (`SkillNode.statuses_changed` / `Entity.statuses_changed`). A node bar
  binds its node, a core bar the entity — two overlays, never merged.
- **Fill.** The bar pushes the fill it is DRAWING through `set_fill` (its animated
  `value`, not the pool), so the band stays glued to the fill tip while a damage
  tween runs.
- **Model, then draw.** `refresh` rebuilds `segments` and `icons` from the live
  rows; `_draw` only paints. A consumer adds segments to the model, never draws
  status on a bar outside this scene. Zero rows -> hidden, so a clean node costs no
  `_draw`. Colour is the row identity's `tint`, unlifted; icons share textures and
  tint through `modulate`, so the row batches.
- **Corruption layer** (node hosts only: an entity row has no threshold). A
  `SandpileSpread` row of a `CorruptionStatus` at `N` stacks against the node's live
  `T` (`SandpileSpread.threshold_of`) draws N blips above the icon row and N pending
  chunks back from the tip, worth what a degree-loss pop deals
  (`CorruptionStatus.burst_amount` at `N`). While critical (`N == T - 1`) a ghost
  chunk follows, worth the extra a landing stack's pop deals at `T`. `N` is drawn as
  read: a transient `N >= T` mid-settle is legal. `T` moves with no row change (a
  neighbour's owner, an incident edge or gate flip), so while a pile stands the
  overlay also listens to those. The pulse reads one global clock in `_draw`.
