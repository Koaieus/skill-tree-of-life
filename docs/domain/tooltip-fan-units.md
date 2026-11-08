# Tooltip fan — per-unit contracts

Unit-level detail for `ui/tooltip_fan/`; the system page is `docs/domain/tooltip-fan.md`.

## FanAnchor — the derived trace terminus (`ui/tooltip_fan/fan_anchor.gd`)

`TraceRouter._pcb`'s closing leg is ALWAYS exactly cardinal (one axis lands flush
on `to`). That makes the panel edge a line arrives at fully determined by the
closing leg's direction, rather than something an author places by hand:

```
arriving rightward (closing leg moves +x) -> LEFT edge
arriving leftward  (closing leg moves -x) -> RIGHT edge
arriving downward  (closing leg moves +y) -> TOP edge
arriving upward    (closing leg moves -y) -> BOTTOM edge
```

WHERE along the edge is derived too, off the trunk top (`from + trunk_dir *
trunk_px`, the shared origin every trace in a fan leaves from): a TOP/BOTTOM edge
takes the trunk top's x, so the route runs straight; a LEFT/RIGHT edge takes a
point `TraceRouter.DIAGONAL_SHARE` of the sideways distance ahead of it (at least
`TraceRouter.MIN_SEGMENT_PX`), so the route bends through a real 45 degree
diagonal rather than cutting 90 degrees off the trunk. Either is clamped to
[0.1, 0.9] of the edge (`SLIDE_MIN` / `SLIDE_MAX`) so the closing leg keeps a real
perpendicular run instead of grazing a corner.

So panel POSITION is the only authored quantity: `derive_anchor` recomputes which
edge + where on it every call, from `from`, the panel's rect, the router params on
the `FanTrace` (`trunk_dir` / `bend_start`) and the driver's fan-wide
`FanAnchorDriver.trunk_length`. Move the panel in the editor, call this again next
frame, and the anchor — and its edge — updates with zero re-authoring.

**Self-consistency, not a one-shot guess.** The edge nearest the panel's CENTRE is
only a candidate. Moving `to` from the centre to that edge's point changes `rem`
(the remainder `TraceRouter`'s PCB math travels after the diagonal), which can flip
which axis is dominant once you're AT the edge — the "went too far and the line
still swaps orientation" bug. So `derive_anchor` asks `TraceRouter` itself (never a
re-derived approximation of its math) what the ACTUAL closing leg of the route TO
each candidate looks like, and iterates candidate -> actual -> candidate until they
agree. A centre-only guess was verified wrong against the shipped NodeStats panel.
`_MAX_ITER` bounds this: two edges are ever in play (the tie is between one
horizontal and one vertical candidate), so a fixed point is found within 2 tries;
more only exist to surface a genuine 2-cycle deterministically.

## FanAnchorDriver (`ui/tooltip_fan/fan_anchor_driver.gd`)

Keeps every `FanUnit`'s trace terminus derived live from its panel's CURRENT
position. Attached as the root script of `fan.tscn` so a human dragging a panel in
the editor sees the trace re-route immediately, without opening `TooltipFan` at all.

**Deliberately NOT part of `TooltipFan`**: the coordinator only exists at runtime
(mounted under the HUD), but "drag a panel, watch the line follow" has to work with
just the fan scene open. Panel position is the only authored quantity in EITHER
context.

**Finds its FanUnits by group** (`fan_unit`), never by NodePath — the mount
contract's "bindings resolve by type/group, not authored NodePaths". Every
`FanUnit` instance in the fan scene must carry that group (authored in the
`.tscn`'s `groups=`, not in code).

The clock face is shared out among the PARTICIPATING units only
(`FanUnit.participating`) and each unit's angle is EASED toward its slot rather than
snapped — a panel igniting mid-hover makes its neighbours slide over instead of
teleporting. Standalone in the editor every unit participates, so an author sees
the full spread.

It derives BOTH trace endpoints. The origin end is the clock spread; the terminus
end is `FanAnchor`'s derived anchor — edge AND slide, the point on the edge nearest
the trunk top. A unit's `position` (where its panel RESTS; `FanLayout` solves where
it sits) is the only thing an author places.

**Serialization invariant.** The driver may READ a unit's own authored properties
(`position`) but must never WRITE them. `godot-workflow.md` forbids a `@tool` script
writing a derived value into an `@export`, and the per-frame `from_point` /
`to_point` / `trunk_length` writes don't dirty `fan.tscn` only because `Trace` is a
NON-EDITABLE descendant of an instanced scene, so Godot never serializes them. A
unit's own properties are direct, editable child properties and have no such
protection — which is why derived results live on the trace and the solved layout
on `%Panel` (the same cover), never on the unit.

## FanLayout (`ui/tooltip_fan/fan_layout.gd`)

A pure rect relaxation solver: N bodies spring toward authored rests while position
projection keeps them apart from each other, from fixed obstacles, and inside a
keep-in rect. No nodes; the driver feeds bodies in and reads `position` back each
frame. The solver is bloom-agnostic: `FanAnchorDriver` solves warm and flies a
blooming panel onto its solved spot as a separate visual leg (a lone body, no
obstacles).

**Two forces only.**
1. A critically damped spring toward `rest` clamped into the window — the camera's
   rubber band (`scenes/camera_2d.gd`): `w = 1 / settle_seconds`,
   `accel = (rest - pos) * w^2 - vel * 2w`, semi-implicit Euler, sub-stepped so
   `w * dt <= MAX_STEP_RATIO`; no transcendentals.
2. Position projection: after integrating, up to `relax_iterations` passes push
   every overlapping inflated pair apart — half each for a body pair (a wall's share
   going to the partner), the whole correction against an obstacle — then `keep_in`
   is applied last and absolutely (a body larger than the window pins to its
   top-left).

Contact is INELASTIC: on each axis projection corrected, the velocity driving into
the correction is dropped. A body held off its rest then re-presses its contact by
one frame's spring pull, not by the closing speed it built up — which is what lets
a crowded fan against a wall come to rest instead of reshuffling every frame.

**Jams, not just contacts.** Projection is local: each push is the shallowest one
with room, which a wall, an obstacle or an over-full stack can undo within the same
pass (the pair pass shoves a panel onto the node, the obstacle pass shoves it
straight back, and the fan rests still but overlapping). So (a) a body inside two
obstacles escapes each on its own axis when that lands clear, the merged rect only
when it does not; (b) an obstacle push with no room on its shallow side takes the
shortest far-edge clear that does; (c) when the relax cap runs out with a pair still
overlapping past `JAM_TOLERANCE` (a converging chain's residual is sub-pixel), a
second capped relax separates exactly those pairs along their OTHER axis, pinned for
the whole round so a pair cannot flip back mid-way.

**Inflation.** `padding` is the gap maintained between any two rects: a body-vs-body
test inflates each side by `padding / 2`; body-vs-obstacle inflates the body by the
full `padding`. Pair order is body index order and every sign has a total fallback
chain, so the result is deterministic.

## FanLiveSandbox (`ui/tooltip_fan/fan_live_sandbox.gd`)

The LIVE fan bench: hosts the REAL `fan.tscn` (the same scene `TooltipFan` mounts)
over a real `SkillNode` + `Entity` fixture, and drives its actual inputs instead of
a hand-rolled mock. A second implementation of the fan's layout that no test covers
drifts; this script is a control surface, not a substitute.

What lives here (mirrors the roles `TooltipFan` plays at runtime):

- **mount + anchor**: the fan sits at this node's origin; the fixture `SkillNode`
  renders there too, and `zoom` multiplies its radius into the driver's
  `node_radius` (the stand-in for camera zoom).
- **content binding**: exactly `TooltipFan._bind_content` — every `FanUnit` gets
  `bind(node, graph)` and `participating = has_content()`, `GrantedModifiersRoot`
  gets `bind(node)`. Collected by group, sorted by `FanAnchorDriver.fan_sort_angle`,
  duck-typed on `play_in`/`play_out`.
- **reconciliation**: exactly `TooltipFan._reconcile` — on any fixture change only
  the units whose participation FLIPPED play in (staggered) or out; panels already up
  stay up.
- **presets**: whole-situation fixtures (unallocated / friendly / enemy / core).
- **drive modes**: manual play-in/erase, loop, hover (distance test on fixture node +
  ring), a clock scrub (writes component `progress` directly), and pointer-drag on
  the real units (the driver re-routes live). Grabbing the fixture node drags the
  whole rig.

Its scene `fan_live_sandbox.tscn` has fixture and fan preauthored (`%Graph` /
`%SkillNode` / `%Fan`), the "real node, not a mock" convention of
`node_visuals_panel.gd`'s `%SkillNodeLab`. `fan_live_panel.tscn` instances it (as
`Sandbox`), which also lets `test_fan_live_sandbox.gd` instantiate it standalone.
It is only ever `instantiate()`d at runtime (sandbox-host dock or the test), never
opened as the editor's primary scene, so property writes never round-trip into the
`.tscn`. The two off-screen neighbour nodes (for a real IdChip degree) are
runtime-spawned.

## FanTrace (`ui/tooltip_fan/fan_trace.gd`)

One circuit-board trace connector: a `Line2D` that draws itself in from an anchor
toward a panel, led by a glowing traveling tip, then holds a steady settled state.
Geometry is delegated to the pure `TraceRouter`; this scene owns the *drawing* —
reveal, tip, and the in -> settled -> out lifecycle.

The trace is a single PCB / 45-degree-only family (`TraceRouter.Style.PCB`): a
cardinal trunk, an exact 45 degree diagonal, then a cardinal run into the panel. The
aesthetic knob is `bend_start`, the fraction of the trunk axis covered before the 45
degree break: 0 is a pure 45 degree diagonal from the anchor, phi ~ 0.382 is
trunk+45+leg (the sprout), 1 is a squared 90 degree corner. Seeded at phi, tuned live,
co-varying with the panel anchor and sibling traces.

**Reveal is by point-count / arc-length truncation** of the Line2D, NOT a dimming
brightness ramp: the line keeps a CONSTANT colour and width across in -> settled ->
out — only how much is drawn, and the tip position, change. That satisfies "never
dim the settled/loop state" structurally. Idle life (an animation in `idle_anim`)
pulses the *tip* alone, never the line.

The trace IGNITES rather than starts: the first `ignite_fraction` of `progress` is a
lead-in where the line is zero-length and only the origin pad blooms — a solder-pad
dot at the clock pin that pops bright, then relaxes to a small steady marker while
the line shoots out. With N traces staggered round the node's rim, that reads as the
chip's pins energizing before the callouts fly out.

The pad is folded into `progress` rather than prepended as its own tween leg —
load-bearing: everything stays a pure function of `progress`, so scrubbing,
reversing from a half-open state, and `FanUnit.enter_hidden`'s hard `progress = 0`
all work with no extra bookkeeping and no duration arithmetic in `FanUnit`.

## CorePanel (`ui/tooltip_fan/panels/core_panel.gd`)

Crown, FAR rung (entity-scoped), CORE nodes only, enforced by the panel's own
`has_content` (every unit is mounted for every hover, so the condition is stated,
not assumed). Envelope sized to the worst case: 8 modifier leaves
(`pacifist_core.tres`) + 1 core-HP row = 9, with headroom to 12 rows.

**Deliberate gold skin exception**: a `FusedPanel` child with `FanPanel.glow_tint`
set gold in-scene (there is no separate gold skin scene; the two skins are
`FusedPanel`/`HoloPanel` and this is the fan's one intentional non-default choice),
because the core is the entity's identity and must not read as just another readout.

`bind` renders: `PanelHeader` as the core class's `display_name`, core HP as a
numeric `StatValueRow` (never a bar), then one row per flattened leaf of
`entity.core_class.modifiers` in authored order (composites such as
`ninja_core.tres`'s budget pack flatten to one row per leaf, never one opaque row).

A formula-driven leaf (per-level class bonuses; `value` is just the coefficient)
does NOT render through `StatModifier.format`: reading `core_class.modifiers`
directly means it's never bound to a board, so `get_effective_value()` falls back to
the bare coefficient and `format()` would print a misleading flat "+1" for what is a
per-level scaling bonus. It renders the coefficient plus an explicit "(scales)"
suffix. It is meant to swap to `StatFormula.description` verbatim once that field
exists, behind one small helper.

## EffectReadoutPanel (`ui/tooltip_fan/panels/effect_readout_panel.gd`)

**Hiding rule.** A row hides when its EFFECTIVE value
(`StatModifier.get_effective_value` — never the raw `.value`; a formula-bearing
modifier's coefficient is not what the node is getting) DISPLAYS as its operation's
neutral element: 0 for ADD_BASE/ADD_BONUS/INCREASE, 1 for MULTIPLY. `SET` never
hides — it has no neutral, per `StatModifier.format`'s pipeline doc. "Displays as"
goes through `StatDef.format_number` — the SAME rounding the row renders with — so
a value reading "+0" on screen hides even when its raw float is 0.004, and a value
that reads real never hides for being a hair off neutral. A `x0` MULTIPLY is
annihilation, not the neutral (`x1` is), and is never a hide candidate.

**Rollup (owner comment, 2026-08-27).** Individually-hidden rows are grouped by
`(stat_id, operation)`. If the GROUP's combined contribution — summed for
ADD_BASE/ADD_BONUS/INCREASE, multiplied for MULTIPLY, the composition each op uses
in the live pipeline — displays as non-neutral, ONE rolled-up row replaces the group
instead of it vanishing silently (ten `+0`s that sum to a real `+4`). A single hidden
row is its own "group of one" and degrades to a true hide.

**"Does this affect me"** (mechanism only; no test pins the visual). Per
`SkillNode.ownership_bit` — never `owned_by == entity` — a row whose
`NodeEffectReadout.source_entity` reads HOSTILE relative to the hovered node tints
redder, so an intruding enemy aura reads differently from the territory's own. Kept
minimal: retint an existing `SlabRow`, no new chrome.

**Cap + carousel (owner call, 2026-08-31).** A node can sit under more auras than
the authored envelope fits, and a `ScrollContainer` is unusable HERE BY
CONSTRUCTION: the pointer is captive on the node this tooltip describes, so it can
never reach the panel. The panel caps at `max_rows_per_page` rows and PAGES: fill,
hold, crossfade, next page, loop. Pagination is by whole rows, never pixels, which
makes "no row is ever rendered clipped" structural. Pages are balanced (`paginate`)
so the last is never a lonely leftover.

Under the cap there is NO carousel and no page indicator — one page, no tween, no
subheader rewrite. The indicator rides the authored `PanelHeader` subheader rather
than a new node, because adding a child under an instanced sub-scene is the
`[editable path=]` trap (`.claude/rules/scene-composition.md`).

## GrantedModifiersRoot (`ui/tooltip_fan/panels/granted_modifiers_root.gd`)

The ROOTS: the modifier stack BELOW the node. Deliberately NOT a `FanPanel`: "no
containing panel" by design — a stack of small slabs, unbounded height, growing
downward into uncontested space. So it does not go through `FanAnchor`'s box-edge
derivation (which only applies to panel-shaped things); its own trace, if any, is a
plain vertical trunk.

Still a fan-tier component: self-animating, `play_in()` / `play_out() -> Tween`, a
readable `progress`, driven by `TooltipFan` exactly like a `FanUnit` — these are the
duck-typed contract the coordinator fires uniformly across everything in the
`fan_unit` group.

`bind` renders one `ModSlabRow` per flattened modifier leaf, plus a "Grants <spell>"
line per granted `SpellGrant` (a bare `SlabRow` tinted keystone gold, sorted ABOVE
the modifier slabs — a granted spell is the bigger fact about the node). A BOONS
list, not a "modifiers" list: one grammar, no header, no legend, no frame. No
separate addon-modifier traversal: addon `entity_modifiers` already land in
`SkillNode.modifiers` via `SkillNode._on_addon_added`.

**Deliberately EXEMPT from `FanPanel.has_content` suppression** (`_add_empty_row`): a
node with nothing to show renders one muted "no modifiers" row instead of vanishing —
this root is the common hover's primary readout, and an absence would read as a broken
tooltip. Do not add `has_content()` to this file.

## SlabRow (`ui/tooltip_fan/slab_row.gd`)

One line of text rendered as its own mini slab: a single `Label` on a `SlabPanel`
background tinted by whatever colour the caller hands it (dark fill, bright tint
border reading as glowing, text in the same tint mixable toward pure white — the PoE
prefix/suffix-row reading surface).

This is the generic half of `ModSlabRow`, so the frontmatter's hover tooltip can be
a stack of these without dragging the stat system in behind it. Everything is
content-agnostic: give it a string and a `Color`. `ModSlabRow` is an INHERITED SCENE
of `slab_row.tscn` that adds exactly one thing — resolving those two from a
`StatModifier`.

The row sizes to its label: `_get_minimum_size` is the label's height plus the
scene's vertical insets. **The label does NOT autowrap**, deliberately: a single-line
row's minimum height is known without reference to any width, so there is no
width->height->width path at all. A stack of these widens to its longest row instead
of wrapping within a fixed one.

Reveal is driven externally via `set_progress` against the shared fixed-clock /
progress(0..1) contract — the row owns no Tween, matching `PanelHeader`,
`StatValueRow`, `AddonItem`. It must render correctly the moment `bind_text` is
called, with no assumption about whether or when `set_progress` is invoked.

## TooltipFan — the coordinator (`ui/tooltip_fan/tooltip_fan.gd`)

Owns N fan-tier members (`FanUnit`s, plus `GrantedModifiersRoot`, which duck-types
the same `play_in()` / `play_out() -> Tween` contract), anchors to the hovered
node's on-screen position, and fires the members with a per-index start delay.
Nothing else. See also `.claude/rules/tooltip-fan.md`.

It owns NO Tween and no fan-wide progress variable — the per-index delay is a
`SceneTreeTimer` wait. Members animate themselves (a `FanUnit` sequences two
components that animate themselves); this class only decides WHEN each one starts.

**One fan scene, per-unit gating.** `fan.tscn` carries every unit and each gates
itself through `FanPanel.has_content`. (A per-occupancy variant picked by
`is_allocated()` / `is_core()` would make allocating the node you are hovering
invalidate the whole mounted scene, forcing a re-fan from scratch.) Allocation
makes Owner (and Core) eligible, they fan out on their own, and the panels already
up are left alone.

**Screen-space anchoring.** `global_position` tracks the hovered `SkillNode`'s
`get_global_transform_with_canvas().origin` every frame — Control-space,
camera-zoom-independent, like `floater_toaster.gd`'s HUD-anchor case (no
`affine_inverse()`: this node has no camera transform of its own, it lives directly
in the HUD's canvas).

**Two-tier gate.** Hover alone shows only the ROOTS — `GrantedModifiersRoot`'s
mod-slab stack, the hover's primary readout. The `FanUnit` members (traces + panels)
are bonus info and stay HIDDEN until the `ui_more_info` action (Shift) is held. The
action state is polled every frame while hovering, so pressing or releasing Shift
mid-hover fans the units in or out through the same `_reconcile` path live updates
use. `participating` still means "has content" (the driver's clock spread depends on
it); the gate is applied HERE, at the play decisions, via `_should_up`.

Members are found by GROUP (`fan_unit`), never by NodePath — the mount contract's
"bindings resolve by type/group, not authored NodePaths". Whether a fan shows 2
members or 6 changes nothing here but how many delays get computed.

## TraceRouter._pcb (`ui/tooltip_fan/trace_router.gd`)

True PCB / 45-degree-only route: a cardinal trunk out of `from`, then an exact 45
diagonal, then a cardinal run into `to` — every turn is 0/45/90 degrees, and no
trunk ever cuts straight into a 90 degree corner.

`params.trunk_dir` (default up, `(0,-1)`) is the cardinal direction the trunk leaves
along; `params.trunk` (default 0.382, phi) is the fraction of the trunk axis' span
covered before the 45 degree break:

```
trunk == 0     a pure 45 diagonal straight from `from`, then a cardinal leg
trunk ~ phi    trunk, 45 diagonal, cardinal leg (the classic sprout)
trunk == 1     the longest trunk that still leaves a MIN_SEGMENT_PX diagonal
               (the fraction is capped at `span - MIN_SEGMENT_PX`)
```

`params.trunk_px` (default 0 = off) overrides `trunk` with a FIXED trunk length in
pixels, never shortened: a fraction gives near panels short trunks and far panels
long ones; a fixed length makes every trace in a fan leave its origin in a uniform
bundle before diverging (and lets `FanAnchorDriver.trunk_top_of` compute the trunk
top by formula).

The diagonal consumes `min(|rem.x|, |rem.y|)` on both axes, which snaps one axis onto
`to`, so the closing leg is exactly cardinal. Consecutive duplicate points are
removed so the polyline carries no zero-length segment.

**Two families share this entry**, chosen by the target's along-trunk remainder past
the trunk top: at least `MIN_SEGMENT_PX` AHEAD takes the trunk -> diagonal ->
cardinal route above, so the diagonal is never `0 < diag < MIN_SEGMENT_PX`; anything
nearer (level with the trunk top, or behind it) takes the **gable** — trunk, 45
shoulder out, a run perpendicular to the trunk, the 45 shoulder back, then a
cardinal closing leg back along `-trunk_dir` into `to`. The gable's trunk is
`trunk_px` if set, else `trunk` x the PERPENDICULAR span. Its shoulder `a` is
`min(params.shoulder, avail / 3)` (`shoulder` defaulting to the trunk length) floored
at `MIN_SEGMENT_PX` — a third each for two shoulders and the run; an `avail` under
`3 x MIN_SEGMENT_PX` drops the run and splits it between the shoulders. A target
level with or just past the trunk top LIFTS the gable: the outward shoulder runs
longer than the return so the return lands `MIN_SEGMENT_PX` past `to` and the closing
leg comes back down onto it; `avail` is the perpendicular span minus that lift.

**The invariant both families keep**, for every target outside the degenerate zone:
every segment heading is on the 45 grid, no bend exceeds 90 degrees (never a 135
double-back), no two consecutive segments are both cardinal, every segment but the
closing leg is at least `MIN_SEGMENT_PX`, and the closing leg is cardinal — a gable's
at least `MIN_SEGMENT_PX`, an ahead route's the leftover `||rem.x| - |rem.y||` (zero
on an exact 45 target, where the route ends on its diagonal). A fraction-mode trunk
floors at `MIN_SEGMENT_PX` too, save `trunk == 0`, which draws none; a `trunk_px`
under the minimum is the caller's call. Degenerate: `|perp|` under
`2 x MIN_SEGMENT_PX` (the trunk's own column, which the fan layout keeps panels out
of), or a lifted gable whose `avail` is under that — the route still returns
`first == from` and `last == to`, with shoulders or a diagonal under the minimum,
tolerated rather than special-cased.
