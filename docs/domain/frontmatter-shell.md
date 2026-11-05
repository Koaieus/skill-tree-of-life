# Frontmatter shell — the menu as a skill tree

The frontmatter is a skill tree with a moving camera (`docs/GDD.md`); the units
under `ui/frontmatter/` compose it. Per-screen panels are in
`docs/domain/frontmatter-panels.md`. This page holds the per-unit contracts.

## BackAffordance (`back_affordance.gd`)

**There is no edge to add.** Owner call, 2026-08-24, verbatim: *"the 'hero' node also still has its edge connected to the left of it going off-screen, it's lit and all given the hero is active ('allocated')"*. The hero's incoming edge is already real: it joins
the focused node to its actual parent (off-screen left), and
`FrontmatterRoot._sync_allocation` lights it because both ends are on the focus
path. The affordance is the LABEL and the HIT AREA sat on a line something else
renders; an affordance that minted its own stub would be a second thing claiming
to be that edge.

Pressing it emits `back_requested`; the shell answers with
`FrontmatterRoot.back`. It never calls `back()` itself — the scene holds no
navigator, which also lets a live tab mount it with nothing behind it.

**At the root there is no parent, so there is no affordance** — absent, not
disabled (`back()` at the root is already a no-op).

**It is a `Control` in screen space**, not a `Node2D` under the camera. Owner call, 2026-08-26: *"Back button is a UI element, should be a Control root."* It still
sits on the hero's incoming edge visually, because `FrontmatterLayout.camera_for`
docks the hero at `hero_slot` in VIEWPORT PIXELS at every depth and fan zoom; the
visible run of that edge is a fixed screen rectangle, and `anchor_for` collapses
to a screen-space point. A screen-space `Control` renders at 1.00x, so the
supersampling `MenuNodeView`'s caption needs for graph-space text
(`_CAPTION_SUPERSAMPLE`) does not apply and is deliberately not ported.

## FrontmatterInput (`frontmatter_input.gd`)

**The menu is a graph, so the input is directional.** The focused node is the
hero; its children are the fan to its right. `ui_up`/`ui_down` move a CURSOR
through that fan, `ui_accept`/`ui_right` commit to the cursor, `ui_cancel`/
`ui_left` go back. Every one ends in a call `FrontmatterRoot` already exposes —
a second thing that moves the camera could disagree with
`FrontmatterRoot.navigation_state`.

**The cursor is not the focus.** Focus is where the camera IS; the cursor is
which sibling a commit would take (at `single_player` the camera sits on Single
Player while the cursor picks between New Game and Load Game). Conflating them
would make merely looking at an option navigate to it.

**MOVING the cursor counts as hover; SEATING it does not.** `step` calls
`FrontmatterRoot.set_hovered`, so a keyboard player raises the same peek and
tooltip the mouse would (no new ring colour: an existing focus treatment is
reused). `_seat_cursor` deliberately does NOT: `FrontmatterRoot.focus` clears the
hover and then emits `focus_started`, which would re-raise it on the new fan's
first option — merely ARRIVING would peek ahead. A commit still works from an
unmoved cursor; only the broadcast is withheld. `MenuNodeView`'s
`MenuNodePickRegion` raises the same hover for the mouse through the same seam.

**Mounting.** Child of `FrontmatterRoot` with `frontmatter_path` pointing at it,
or `bind` from a composer. Input arrives through `_unhandled_input`, so anything
a focused `Control` in the panel layer consumes first (the seed field, a button
press) never reaches here.

## FrontmatterLayout (`frontmatter_layout.gd`)

Where every menu node sits, and where the camera has to be for one of them to
read as "the hero". Pure and static — no scene, no `Node`, no frame — so the
geometry is unit-testable (`test/unit/ui/test_frontmatter_layout.gd`).

**The split is the design.** "No detaching, ever" is discharged as one
persistent graph, nodes never move, the `Camera2D` moves:

```
solve(tree)                -> {id: world position}   focus is NOT a parameter
camera_for(tree, focus_id) -> Transform2D            the ONLY thing focus moves
```

`solve` taking no focus is the machine-checkable form of "nodes never move"; the
test asserts its output is identical across a run of `camera_for` calls.

**Geometry is AUTHORED, not derived.** `solve` reads the fan harness scenes in
`ui/frontmatter/layout/` — one inherited scene per menu, each a
`MarginContainer` + `HBoxContainer` + `VBoxContainer` of invisible `MenuSlot`
spacers tuned in a full-screen editor preview. A container authors the sibling
pitch; deriving it as well would be two sources for one coordinate set.

**There is exactly one size.** The harness is authored at the project viewport,
so `viewport_size` is the only size in the file and `screen_to_world` is the
genuine inverse of the real viewport transform. `project.godot`'s
`stretch/mode = "canvas_items"` + `stretch/aspect = "keep"` is what makes ONE
authored geometry correct at every window size.

**The LOOK is authored in the same place.** The pass that measures a fan lifts
each seat's caption, joke slab, archetype and radius off it into a
`MenuSlot.Look` (`look_of`). `MenuGraph` keeps topology and routing and carries
no display string at all.

### charged_camera — the BOOM's pose

The splash advances in two legs and `charged_camera` is the seam: leg 1 zooms out
from `splash_camera` to here; leg 2 is `FrontmatterRoot.focus` on the root,
travelling from here to `camera_for`.

**Leg 1 does NOT finish the zoom, deliberately.** `end_zoom` is an INTERMEDIATE
zoom, not `TREE_ZOOM` — the remaining zoom-out rides leg 2's pan, so the needle
flashes while the camera is still opening. Owner, 2026-09-03: *"we could keep it
closer a bit longer... then more so / faster so when the alloc vfx has just
started (its a short flash anyway)"*. Easing alone cannot buy this: ending leg 1
at `TREE_ZOOM` means the camera is fully out at the instant of the flash.

**Nothing pins the needle's framing.** The needle is
`radius * height_factor` (`alloc_spike.tscn`) in WORLD units (264 at the root's
authored radius 44) against the `CHARGE_SLOT_Y_RATIO` slot's 653px of headroom,
so it sat wholly on screen only below zoom 2.47. Owner, 2026-09-03: *"looks can
differ, and it's a matter of taste, having the thing entirely on screen or
partially off screen, is not something we should be pinning with tests. the
orchestration as a whole is more important."* `SplashScreen.charge_end_zoom`
follows whatever the scene authors; `test_splash.gd` pins the orchestration only.

**The horizontal slot is READ, never written** — the parked pose's own, so "the
root does not drift sideways through leg 1" is true by construction. The
vertical is this file's own ratio south of the hero slot, so leg 2 rises back up
and is a DIAGONAL rather than a pure slide (owner-accepted, 2026-09-03).

## FrontmatterLiveSandbox (`frontmatter_live_sandbox.gd`)

The LIVE frontmatter bench: the real `frontmatter_root.tscn` in a bloom
`SubViewport`, with a control column for every knob the motion notes flag as
eyeballed.

- **It benches the shipped scene, not a mock.** A hand-rolled copy of a layout
  drifts uncovered (the tooltip fan's first live tab did). The `SubViewport`
  instances `frontmatter_root.tscn` itself; a knob with no visible effect is a
  finding about the menu, not the bench.
- **Why a bloom viewport.** Glow is one `WorldEnvironment` pass PER VIEWPORT
  (`.claude/rules/hdr-color.md`); `meta_root.tscn`'s pass does not reach a
  `SubViewport`. `ui/theme/bloom_viewport.tscn` is the shared HDR-2D viewport the
  other live benches use.
- **The clock is driven, never watched.** Every animated unit exposes
  `set_progress(t)` and owns no `Tween`; the scrub slider writes `t` onto
  `FrontmatterRoot.set_progress`.
- **Knob state lives in one dictionary, re-pushed wholesale.**
  `FrontmatterRoot.build` is idempotent (clears and rebuilds), so Rebuild is a
  real cold boot; the panel holds the knobs and pushes them again via
  `_apply_all`.
- It satisfies `SandboxLiveTab`'s loader contract with `noop` — no inspected
  resource.

## MenuFanHarness (`ui/frontmatter/layout/menu_fan_harness.gd`)

One menu's geometry, AUTHORED. The base scene is `menu_harness.tscn`; every fan
is an inherited scene of it that adds its own slots and tunes its own separation
and margins in a full-screen editor preview.

```
MenuFanHarness (MarginContainer, the project viewport)
  %Row          (HBoxContainer)
    %HeroSlot   (MenuSlot)  — where the focused node docks
    %OptionsVBox(VBoxContainer)
      MenuSlot x N          — one per child of hero_id
```

**It is never ALIVE while the menu is.** This is a `Control` tree in SCREEN
space; the menu is `Node2D` views under a `Camera2D` in WORLD space. A live
harness would re-lay-out on window resize under a camera that already baked its
numbers — a second layout system racing the first. So `FrontmatterLayout`
instances it, calls `measure`, and frees it. `measure` drives the container sort
by hand rather than waiting for a frame, which keeps the whole geometry a pure
static function with no `await`. It parents itself for the length of that one
synchronous call (`ControlMeasure.parent_for_measuring` explains why), but is
never in the tree across a frame.

**Never a `RemoteTransform2D` between the two**: it pushes GLOBAL transform and
would double-apply the camera.

## MenuEdgeView (`menu_edge_view.gd`)

One edge of the menu tree, drawn through the REAL edge shader.

**It reuses `graph/edge_mesh.gdshader` + `edge_mesh_material.tres`, NOT
`graph/edge.tscn`** (owner correction, 2026-08-24). Two independent reasons the
scene cannot be used: `Edge`'s endpoints are typed `SkillNode` and really
dereferenced on the render path, and `Edge` does not render itself —
`_push_transform()` / `_push_colors()` both hand off to a `Graph`-level batched
renderer, so the scene needs a `Graph` host as well as real endpoints. The menu
forbids both classes.

So this is a thin menu-owned renderer over the same shader, with the transform
convention copied from `Edge._push_transform()` exactly — the shader expands a
unit `QuadMesh` whose local X spans the segment and whose Y carries a
screen-constant width, so a wrong convention draws a hairline in the wrong place
rather than nothing.

**One instance per edge, not one batch.** In game that would be wrong
(`.claude/rules/rendering-performance.md`: `Graph` batches every edge into one
shared `MultiMesh`). The menu has nine edges; a view per edge gives an ordinary
`Node2D` that can be tweened, shown and hidden, at the cost of nine draw calls in
a menu that draws nothing else.

**Not carried over from `Edge`:** `render_vis_state` (the menu has no
`VisionSystem`, so every edge is fed a constant `Edge.VIS_VISIBLE`, which
`vision_field_dim` passes through while `vision_field_enabled` is false) and
`_clamp_code` (the Clamp addon, gameplay).

**The shape is a sigmoid**: a cubic Bezier whose two control points are pulled
purely horizontally off their own endpoint, so the curve leaves the parent
heading right and arrives at the child heading right, the vertical travel folded
into the middle. Drawn as `curve_segments` straight `QuadMesh` instances chained
along that curve — still one `MultiMesh` (`curve_point`).

## MenuGraph (`menu_graph.gd`)

The menu tree as menu-local data. **Deliberately NOT a `Graph`.** Owner call
2026-08-24: *"special menu local model for sure, if we did our composibility
right we could steal just the *visuals* of the real elements involved iff not
using the real ones directly"*. Nothing here touches `Graph`, `SkillNode`,
`Entity`, `StatBoard`, `AllocationSystem` or `TurnManager` — the menu borrows the
node VISUALS (`skill_node/visuals/node_visuals_composite.tscn`) and none of the
machinery that drives them.

**It carries topology and routing, and no look at all.** Every display string,
tint and radius is authored on a `MenuSlot` in `ui/frontmatter/layout/`, where it
can be seen at full-screen scale (`FrontmatterLayout.look_of`). What stays is the
half that is not visual and already has a net: `test_meta_routing_parity.gd` pins
`Item.panel` and `Item.route` against the live `meta_root.gd`.

**It is a tree, not a graph**, despite the name: every item has exactly one
parent, the root none, no cycles. `FrontmatterLayout` turns it into world
positions once, at build time; navigation moves the camera, never a node.

**The tree mirrors the routing `scenes/meta/meta_root.gd` ships**, including the
config panels HOST and JOIN raise before a lobby. `Item.route` records, per leaf,
the `RunConfig.Mode` and `NetworkConfig.Role` that leaf has always produced.

## MenuNodeView caption supersample (`menu_node_view.gd`)

The caption is rasterized `_CAPTION_SUPERSAMPLE` (3x) larger than it is drawn. A
`Label` rasters its glyphs at `font_size` and the canvas stretches that bitmap;
this menu draws text at every scale there is (peek nodes at
`FrontmatterLayout.PREVIEW_SCALE` 0.42, fans at `TREE_ZOOM` 1.0, the splash at
`SPLASH_ZOOM`), and each is a resample of a 16px raster — aliased, mushy text
(owner called it out 2026-08-26).

Rastering at 3x and drawing at 1/3 puts the raster ABOVE every scale, so
magnifying is a downsample. Minifying is covered by the font's mipmaps, which is
why the scene authors `texture_filter = 4` (LINEAR_WITH_MIPMAPS) on the caption:
Godot's default canvas filter has no mipmap stage, so the imported mipmaps would
never be sampled and peek captions would fragment.

**Scoped to this Label, not the font import.** `oversampling` in
`Cinzel-VariableFont_wght.ttf.import` is the same trick globally and measurably
THINS the HUD's own `CinzelHeader` labels (screen-space, zoom 1, want native
raster). `generate_mipmaps` is safe globally because it is inert until a
CanvasItem asks for a mipmap filter.

**Applied on the node in `menu_node_view.tscn`.** `%Title` authors
`scale = (0.333333, 0.333333)`, a `font_size` override of 48 and
`size = (660, 72)` — static, none vary per node. The constant documents WHY
(`16 * 3 = 48`, `_CAPTION_BOX * 3 = (660, 72)`, `1 / 3`); nothing at runtime
reads it.

## MenuTooltip (`menu_tooltip.gd`)

The slab stack a menu node shows when you point at it: a centred column of
`SlabRow`s directly under the node — its title (or `GRANTED ON SELECT`), a
one-line description for most, and for SINGLE PLAYER / MULTIPLAYER the
`PLAYERS +1` / `PLAYERS +8` joke, rendered like a real granted modifier.

**A stack of rows, not a panel with a body.** A `Slab` + `Margin` + `Body` +
autowrap `Description` structure carries a layout cycle: the tooltip's minimum
read `%Body`'s combined minimum, `%Body` was anchored to the tooltip, and an
autowrap `Label` derived its height from that width (it settled at ~470px for two
lines). The stack deletes the cycle: every row is a child of a real `Container`
(so it shrinks when its minimum drops), the stack authors its own
`custom_minimum_size.x`, and no row derives a width from the stack's size. This
is `AddonItem`'s shape.

**It reuses the tooltip-fan's own row.** `SlabRow` is the base extracted from
`ModSlabRow`: the same slab, any text, any tint, no `StatModifier` and no
`StatRegistry` behind it. `PLAYERS` is a string in the menu's own data and
reaches nothing.

**What is shown is decided by the content, not the topology.** A node gets a
tooltip iff it carries a slab or a description: SINGLE PLAYER and MULTIPLAYER get
their joke (they have children) and the ROOT (children, no content) gets nothing.

**The slab's text comes from the authored slot** (`MenuSlot.subtitle`, authored as
`"+1 PLAYERS"` in `root_menu.tscn`), split here rather than restated — one source
for the joke, the one the node is captioned from.

**It fades, it never hides.** Nothing writes `visible = false`: a hidden
`Control` skips layout, which breaks size convergence. "Nothing to say" rests at
`modulate.a = 0` via `set_progress`, the contract `SlabRow` follows. Reveal is
driven externally against the shared fixed-clock / progress(0..1) contract; the
node owns no `Tween`.

## SplashScreen (`splash_screen.gd`)

The attract state — not a screen at all, but the frontmatter's own camera parked
hard on the root node.

**"Press any key" IS allocating the first node.** The motion notes: *"The splash
'press any button' prompt is really just allocating the very first node of the
run."* So press any key -> allocate root -> allocate Single Player -> allocate
New Game must read as the same action four times, which only works if the splash
and the tree are the same picture at two zoom levels. No cut, no cross-fade.

**Advancing is a CHARGE and a BOOM, across two camera legs.** Owner, 2026-09-03:
*"it should ramp up the ring. a bespoke effect, not part of the regular
skillnodes. just for this one. the idea is this: click it, and it starts glowing,
until BOOM allocation vfx (which is some power needle spike thingy)."*

- **Leg 1, the charge, in TWO beats.** For the first `charge_camera_fraction` of
  `charge_duration` the camera crawls out from `FrontmatterLayout.splash_camera`
  to `charged_camera` ("slow slow", a little zoom, a tiny pan up). Then it STOPS;
  for the remaining fraction the frame is perfectly still while the `ChargeGlow`
  ramps from `Emissive.INERT` toward `Emissive.PEAK`. The ring stays UNLIT
  throughout — the stillness is what reads as a wind-up rather than more camera
  motion.
- **The BOOM**, into that stillness. The root reads allocated, the charge
  detonates into a shockwave, and the allocation needle drops, all in one frame
  with nothing else moving. Owner, 2026-09-03: *"crescendo: stop zooming/panning
  (the whole node+spike would still be taking the majority of the screen), the vfx
  + vfx + vfx all hit."*
- **The settle**: `settle_pause` of dead air so the crescendo lands before the menu
  pulls away.
- **Leg 2**: `FrontmatterRoot.focus` on the root — the slide into the hero slot,
  carrying the LAST of the zoom-out. Leg 1 stops at `charge_end_zoom`, short of
  tree zoom, so the flash lands while the camera is still opening.

The needle is `radius * height_factor` (`alloc_spike.tscn`) in WORLD units (845px
at `SPLASH_ZOOM` on a 960px screen), so the BOOM happens at `charge_end_zoom` with
the root pushed south to `CHARGE_SLOT_Y_RATIO`. That containment is NOT a guard
(owner, 2026-09-03: *"looks can differ, and it's a matter of taste, having the
thing entirely on screen or partially off screen, is not something we should be
pinning with tests. the orchestration as a whole is more important."*): framing
follows whatever the scene authors; `test_splash.gd` pins the orchestration.

**This scene paints no background.** The tree is meant to be visible behind the
title, hugely magnified — that is the whole effect.

**It parks the camera rather than being asked to.** `FrontmatterRoot.build` ends
on `focus(root, true)`, so by the time this node is ready the camera is at tree
zoom and the root reads allocated. Undoing both in `_ready` keeps the splash
concern in one file instead of threading a start-up mode through the shell — and
is why this node must be ordered AFTER the frontmatter in `meta_root.tscn`.

Gamepad input belongs to `FrontmatterInput`; keep new input handling there.
