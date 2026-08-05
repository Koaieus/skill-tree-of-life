# Circuit-fan node tooltip (V2)

Epic #159: replace the old single-card `SkillNodeTooltip` with panels that
sprout from a hovered `SkillNode` along circuit-trace lines. This doc records
the design decisions from the #215 prune session — they only lived in GitHub
issue comments before this — plus the components built so far.

## The #215 prune session (2026-07-18)

The original brainstorm (issue #159) sketched a large tunable surface (a
`TooltipFanConfig` resource with ~28 exported knobs: `fanRadius`, `fanSpread`,
per-unit sync modes, four entry-anim styles, three trace styles, ...). #215
pruned that down. **Locked decisions:**

1. **Hand-authored variant scenes, not programmatic fan geometry.** Panel
   positions, line attach points, and line targets are authored in-scene with
   `@tool` live preview, not computed from `fanRadius`/`fanSpread` math.
2. **Build one variant now** (tree-sprout, parallel-start), clone for a radial
   variant later. Shared contract across variants: `line in → card in → card
   out → line out`, plus idle-while-open.
3. **Trace: one style only** — PCB / 45°-elbow family (`straight` dropped;
   `elbow == tree`). `corner`/`bend`/`bend_start` are exports on the line scene
   (`FanTrace`, #222). Idle-while-open is a [FanAnimation] resource (#234):
   assigned → the settled element idles, `null` → it stays steady-lit.
4. **`sync_in`/`sync_out` baked to sequential** — line draws in → glowing tip
   arrives → card unfurls at the tip (the "sprout" read). The 3-way
   sequential/simultaneous/reverse enum from #224 is dropped.
5. **HP is just a panel** placed in the fan with keep-open-when-damaged
   retraction logic — no dedicated geometry system.
6. **Skin / mod-row = "which packed scene to instantiate"** (glass vs. holo;
   mod-row variants). Keep swappable while ≥2 options exist — not a
   monolithic enum baked into one scene.
7. **`TooltipFanConfig` (#216) deferred.** Don't build the 28-prop resource
   now; let it emerge from authoring the first variant.

**Knob reclassification** (from #215's raw brainstorm comment, pruned):

| Bucket | Knobs |
|---|---|
| Hand-authored in-scene | panel positions, line attach/target, per-unit stagger |
| Exports on the line scene (`FanTrace`) | `corner`, `bend`, `bend_start`, `idle_anim` (a [FanAnimation] resource, `null` = off) |
| "Which packed scene" | `panelSkin` (glass/holo), `modRowStyle` |
| Owned by the animation setup — the [FanAnimation] resource (#234) | `idleAnim` realized; `entryAnim`/`leaveAnim`/`loopAnim` still TBD but the same resource type can carry phase knobs later |
| A concrete panel's own job | `statChart`, `coreDetail` |
| Dropped entirely | `fanRadius`/`fanSpread`, `simpleCore`, `playMode`, `sprout`, `straight` trace style, the sync enum |

## Three tiers of composition (settled #226, #303)

The fan is **components composed into a unit, composed into a coordinator**.
Each tier does exactly one job, and each tier is a scene you can open and watch
on its own.

| Tier | Job | Contract |
|---|---|---|
| **Component** — `FanTrace`, `FanPanel` | Animate itself | `play_in()` / `play_out() -> Tween`, plus a **readable `progress`**. Knows how to reveal itself, how to reverse itself, and how long that should take. |
| **Unit** — `FanUnit` | Sequence two components | `await _trace.play_in().finished` then `await _panel.play_in().finished`; OUT is the reverse read. Owns **no** Tween of its own — it holds ordering and state, nothing else. |
| **Coordinator** — `TooltipFan` | Fire N units | A per-index start delay, and nothing else. Whether the fan shows 2 units or 6 changes only the delays. |

Below the components sit the **content rows** — `ModSlabRow`, `PanelHeader`,
`StatValueRow`, `AddonItem`. These are *not* fan participants: they take
`set_progress(t)` and are driven by the panel they live in, from inside that
panel's own reveal tween. Rest state is `t = 0`, set at bind — never as a side
effect of an entry call.

**There is no fan-wide clock.** Independent components with a variable start
delay are the simple form of exactly the choreography wanted, and they keep the
sequence readable as a chain of completions rather than as arithmetic on a
normalized `t`. An earlier phrasing here ("one fixed clock … never a
per-component Tween chain") was read as mandating a single fan-wide timeline and
got #224's `FanUnit` flagged as violating it. That reading was wrong, and the
rule that produced it is gone.

**Interrupt = kill and reverse.** A hover→unhover mid-reveal kills the running
tweens; each component then plays OUT **from its own current progress**. A
half-drawn trace retracts from half-drawn — it never pops to full first and
never hard-cuts. Because a component owns its `progress`, it also owns the
arithmetic: **each scales its reverse duration by how far it actually got**, and
a component sitting at `progress == 0` yields a zero-length leg, which *is* the
"skip the panel fade when the panel never opened" rule — no `if`, and no cache
of someone else's state. Floor each leg at ~0.03s so a near-zero one still
yields a frame.

`FanUnit._generation` stays: a tween that finishes on the same frame as the
interrupt would otherwise resume a stale continuation.

### Why `FanPanel` gained `play_in`/`play_out` (#303)

It shipped (#223) as a pure sink — `set_progress(t)` and no getter — while
`FanTrace` shipped self-animating. That asymmetry meant `FanUnit` sequenced one
component and *puppeted* the other, holding a tween on the panel's behalf and
caching `_panel_progress` so it could compute the reverse. The cache existed only
because the panel could not answer "how far in am I?". Making the panel a peer
deletes the cache, the puppet tween, and the duration arithmetic from `FanUnit`
in one move. `set_progress(t)` survives as the content-row contract, where a
pure sink is the right shape.

`fan_trace_sandbox.gd` drives its five trace+destination pairs off one `_clock`
var. That is a **preview scrubber**, not the shipped drive model — it exists so
an author can drag a slider and see any frame of the reveal, and it does not
contradict the table above.

## Components so far

- **`FanTrace`** (`ui/tooltip_fan/fan_trace.gd`, #222) — one circuit-trace
  connector: `Line2D` + glowing `Sprite2D` tip, geometry from `TraceRouter`
  (PCB-elbow only, per decision 3). `progress` (0..1) truncates the drawn
  arc-length. `play_in()`/`play_out()` return a `Tween` to `await` (named
  `play_draw_in`/`play_erase` until #303 unified the component contract).

  **Ignition.** A trace doesn't start, it ignites. The first `ignite_fraction`
  (default 0.22) of `progress` is a lead-in where the line is still zero-length
  and only an **origin pad** — a solder-pad dot at the clock pin — blooms past
  its steady size, then relaxes as the line shoots out of it. Staggered across
  the rim, that reads as the chip's pins energizing before the callouts fly out,
  and it gives every trace a visible *somewhere* to come from instead of a line
  materializing out of the node's edge.

  The pad is folded **into `progress`**, not prepended as its own tween leg.
  That's the load-bearing part: the whole reveal stays a pure function of one
  scalar, so editor scrubbing, reverse-from-half-open, and `enter_hidden()`'s
  hard `progress = 0` keep working with no extra state and no duration
  arithmetic leaking into `FanUnit`. `play_in`/`play_out` split into two tween
  legs at the band edge purely so each band keeps its own easing — total
  duration is unchanged, and the split is invisible to the tier above.

  **The tip is an arrival head — IN only.** It is lit while the line draws in and
  suppressed for the entire retraction (`_erasing`), including the frame an
  interrupt catches it mid-flight. On the way out there is nothing to arrive at:
  the line retracts into its pad, and the pad extinguishing is the closing beat.
  Nothing replaces it. Direction is set by the two entry points rather than
  inferred from a `progress` delta, so the sandbox scrubber still shows the tip
  in both directions — deliberately, since it is an authoring surface, not the
  shipped read.
- **`FanPanel`** (`ui/tooltip_fan/fan_panel.gd`, #223 + #303) — thin wrapper
  around a hand-placed skin child (`GlassPanel` or `HoloPanel`, swapped by
  editing which scene is instanced under it — decision 6, not a runtime enum).
  Forwards a single `glow` (0..1) to whichever skin is present. Since #303 it is
  a **peer of `FanTrace`**: owns a readable `progress`, and `play_in()` /
  `play_out()` returning a `Tween` — the scale+fade reveal (cubic ease-out) it
  already had, now self-driven. Drives its content rows' `set_progress` from
  inside its own tween.
- **`fan_trace_sandbox.gd`/`.tscn`** (#233) — in-editor preview harness,
  reachable from the sandbox host's "Fan Trace" tab. Five `FanTrace`s sprout
  from a mock node to four corner `FanPanel` destinations (mixed glass/holo
  skins, demonstrating the swap) plus a top row of `ModSlabRow` tiles. Drives
  everything off one clock (`_clock`), matching the contract above.

- **`FanUnit`** (`ui/tooltip_fan/fan_unit.gd`, #224) — pairs one `FanTrace` +
  one `FanPanel` under a `HIDDEN → IN → LOOP → OUT → HIDDEN` state machine;
  trace→panel ordering is baked sequential per decision 4. Owns **no** Tween
  since #303 — it sequences its two components and holds state. Forwards
  `trace_idle_anim` / `panel_idle_anim` ([FanAnimation] resources) to its two
  components; both default `null`.
- **`FanAnimation`** (`ui/tooltip_fan/fan_animation.gd` + example presets in
  `ui/tooltip_fan/idle/`, #234) — the self-contained idle-loop settings object,
  one per element rather than one for the whole fan: [FanTrace] reads `period` +
  `pulse_scale`, [FanPanel] reads `period` + `float_amplitude` +
  `glow_amplitude`, the other element's knobs are ignored. It is a settings
  bag, not an animator — the components keep the tween choreography so the
  constant-brightness rule stays structural (idle only ever adds above the
  settled floor; `play_out` kills the loop before the fade reads from it).
  **The resource is the unit of swap and of removal**: assign a different
  `.tres` to change the idle, set the export to `null` to turn it off. Shipped
  off by default, opt-in per unit; the components floor `period` (≥ ~0.05s) so
  a stray 0 can never spin a looped tween per-frame (the original `panel_idle`
  bug class — `core_panel.tscn` shipped `idle_period = 0.0`).
- **Shared rows** (`panel_header`, `stat_value_row`, `addon_item`, #293) —
  content rows on the `set_progress(t)` contract, driven by their panel. `AddonItem.bind()` takes an
  optional `icon` override and carries a real `GradientTexture2D` placeholder
  (never `PlaceholderTexture2D`, per `.claude/rules/godot-workflow.md`).

## One fan scene, gated per unit (#314 — reverses #226 Decision 2)

#226 shipped **three occupancy-class variant scenes** — `unowned.tscn`,
`owned.tscn` (adds Owner), `owned_core.tscn` (adds Core), an inheritance chain —
selected on hover by `TooltipFan._pick_variant` branching on `is_allocated()` /
`is_core()`. #314 collapsed them into one `fan.tscn` carrying every unit.

**What forced it.** `owner_changed` — the signal V1's tooltip used to keep its
owner line live — *flips `is_allocated()`*, which is the very predicate the
variant was chosen by. So the single most ordinary live-update case, **allocating
the node you are already hovering**, invalidated the whole mounted scene rather
than one panel's contents. Under a variant design the only available response is
to tear the fan down and re-fan, which is exactly the visual the fan exists to
avoid. Gating per unit means the panels already open stay open and the
newly-eligible ones sprout alongside them.

**What replaced the variant branch.** `FanPanel.has_content()` is now the fan's
only gate, re-answered on every live update rather than once per hover, and
cached per unit in `FanUnit.participating` (written by `TooltipFan._bind_content`
in the same pass that binds the panel, so the flag can never lag the content by a
frame). `OwnerPanel` and `CorePanel` gained the overrides they had never needed —
their old docstrings said outright that being mounted in the right variant *was*
their gate.

**The pin rule reversed with it.** Pre-#314 a suppressed panel kept its clock pin,
on the theory that a present panel's trace should land in the same place
regardless of its neighbours — "absence leaves the fan balanced, never
gap-toothed". That is now inverted: pins redistribute over the participating units
only. A fan with a hole in it reads as *a panel failed to load*, not as a
deliberate omission, and positional constancy isn't worth buying with that.
Stagger indexes over the same participating set, because the sweep would otherwise
visibly skip positions the fan isn't using.

**Deferred, deliberately:** authored per-panel clock pins, which would let a panel
arrive from an arbitrary angle (the #292 procgen debug panel entering from 3
o'clock, say) instead of taking the next auto-flowed slot. Revisit only if the
auto-flow proves insufficient; until then panels flow neatly and nobody authors an
angle.

**One consequence worth knowing:** panel *positions* are now fixed per panel
rather than re-authored per occupancy class. `owned_core`'s layout was adopted
wholesale, since it was the only one that had to accommodate all six members. An
unowned node's three panels therefore sit where the six-member layout put them —
further out than `unowned.tscn` placed them. That is a real trade (the common case
pays for the crowded case) bought for a real gain: a panel is always in the same
place, so you learn where Addons lives. Retuning is now a single-scene job.

## Fan geometry: what is derived vs. what is authored (#307)

**Exactly one quantity is authored per unit: where its panel sits.** That is the
`FanUnit`'s own `position` in `fan.tscn` — drag it and everything else
re-derives. Two smaller knobs sit on top (`anchor_slide`, `bend_start`); both
have defaults that need no attention.

### The origin end — clock pins

The skill node is a **chip** and the trace origins are its **pins**.
`FanAnchorDriver` spreads them on an analog clock face: a uniform step between
neighbours, symmetric about 12 o'clock. Three traces sit at 11/12/1, four at
10:30/11:30/12:30/1:30, five at 10 through 2. Past `max_arc_degrees` the *step
compresses* rather than the arc widening — beyond roughly ±60° a straight-up
`trunk_dir` starts reading wrong, and squeezing beats tilting the trunks.

Slots are handed out in **angular order around the node, never tree order**.
Tree order is authoring order and says nothing about where a panel sits, so
assigning by it would start two traces on each other's side of the node and force
them to cross. `TooltipFan` staggers on the same sort key, so the fan sweeps
across the arc instead of popping in scene order.

**Slots are shared out among the PARTICIPATING units only, and slot changes are
eased (#314).** `n` in `pin_angle(i, n, …)` is how many panels currently have
content, not how many are authored — so an unowned node's three live panels sit
at 11/12/1 rather than at three of five wider slots with holes between them. When
a panel becomes eligible mid-hover, every neighbour's target slot moves and each
one *slides* to it (`pin_slide_rate`, exponential decay, no Tween — the fan's
"nobody holds a shared clock" rule holds). `refresh()` snaps instead of easing,
which is what makes the geometry assertable and what the editor uses.

### How the fan reacts to camera zoom

**Pins ride the node's screen-space rim; panels stay screen-constant.** The fan
lives in the HUD canvas, so its anchor was always zoom-independent — what made
zooming feel broken was the camera stepping `zoom` by a hard ±0.25, since the
anchor teleported. That is fixed at the camera (`scenes/camera_2d.gd` tweens to
a `_target_zoom`), not here.

`TooltipFan` already reads `get_global_transform_with_canvas()` for the anchor
origin; **the same transform's `get_scale()` carries the zoom factor**, so the
coordinator feeds `node.radius * scale.x` to the driver without ever knowing a
camera exists. Pins then sit on the node's *visible* rim at every zoom while the
panels keep their pixel size (they are UI, and at `MIN_ZOOM = 0.25` a
world-scaled panel is unreadable). Trace length changes as a *consequence* of
the origin moving — not as a rule of its own.

The plain editor has neither a camera nor a hovered node, so the driver falls
back to `preview_pin_radius`. That fallback is load-bearing: without it, opening
the fan scene standalone renders every trace from (0,0), which is exactly the
authoring problem this design exists to fix.

The fan is **not** dismissed on camera motion. With the zoom tween, tracking is
smooth, and dismissing would read as twitchy.

### Order by ANGLE, not by x

The sort key is the clock angle of a panel's centre around the node — the same
convention `pin_offset` uses — so the panel sitting at 10 o'clock gets the
10 o'clock pin.

Sorting by **x** looks equivalent and isn't. A panel can be further left while
being *angularly* nearer to vertical, because it also sits much higher: Owner at
`(-320,-340)` is 43° west of vertical, NodeStats at `(-195,-150)` is 52°.
NodeStats is the NWW one and must take the outer pin, but x-order hands it to
Owner — so the two outermost traces start on each other's side and have to cross
to reach their panels. Switching to angular order removed both structural
crossings (3 → 1).

What remains is placement, not structure: IdChip's panel sits ~17px right of
centre while its pin is at 12 o'clock, so its closing diagonal clips Core's
trunk. That closes with a hand-authored pass — nudge the panel, or tune that
unit's own `bend_start` (it is a per-unit `@export` on `FanTrace`, authored in
each unit scene). Meanwhile `test_route_crossings_do_not_increase_on_the_full_fan`
caps the six-member fan at 1, and
`test_an_unowned_nodes_fan_is_genuinely_crossing_free` requires zero for the
common case — the participation subset an unowned node actually shows.

### The terminus end — derived edge, authored slide

`FanAnchor` derives **which** panel edge a trace lands on, from the closing leg
of the route `TraceRouter` would actually draw (see the self-consistency note in
`fan_anchor.gd`). That derivation is what guarantees the arrival leg is
**perpendicular** to the border it meets — a horizontal leg running alongside a
panel's bottom edge and simply stopping is the failure mode it prevents.

`FanUnit.anchor_slide` (0..1, default 0.5 = edge centre) picks **where along**
that edge. Top→bottom on a vertical edge, left→right on a horizontal one; 0 and
1 are the corners, which are legal precisely because a corner belongs to both
edges. Because the edge still flips automatically when a unit crosses the fan's
centreline, a slide stays meaningful wherever it lands — so dragging a unit
across the fan needs no re-authoring. This is why the panel offset is one
scalar and not a hand-tuned `Vector2`.

### The serialization invariant

`FanAnchorDriver` writes derived values into `@export`s from `_process` in a
`@tool` script — which `.claude/rules/godot-workflow.md` forbids outright. It
gets away with it for exactly one reason: `Trace` is a **non-editable descendant
of an instanced scene**, so Godot never serializes those writes back into the
`fan.tscn`. Verified empirically — open the fan scene, save, `git diff` is clean
but for format churn.

A unit's `position` has no such cover: it is a direct, editable child property of
`fan.tscn`. **The driver reads it and must never write it.** Any future derived
quantity has to land on the non-editable side of that line, or be split into an
authored `@export` plus a getter-only `var` per the workflow rule.

The same rule is why `FanUnit.participating` and `FanUnit.pin_angle` (#314) are
plain runtime `var`s and not `@export`s: both are derived per hover. Storing the
eased angle on the unit rather than in a driver-side Dictionary also means it dies
with the instance — fans are created and freed on every hover, and a keyed cache
would either leak entries or hold freed references.

## What's still open

- `TooltipFan` coordinator (#226) — the real node-anchored fan, driving
  `FanUnit`s from a hovered `SkillNode`; this is where the tree-sprout variant
  actually gets authored (decision 2), and where `TooltipFanConfig` (#216)
  should be revisited once real knobs emerge.
- The **z-sandwich** (HoloPanel `z=-1` / content `z=0` / ScanlineOverlay `z=+1`)
  is pinned but has never been verified to render as intended. #226 confirms it
  in the sandbox and reports back either way.
- Entry-anim *style* — which reveal a panel plays is still the "owned by the
  animation setup" bucket of decision 7. *Who owns the Tween* is no longer open.
- Panel/unit scene duplication — #380: six concrete panels each hand-recompose
  the same chrome (skin + content + header + padding), and the six unit scenes
  differ only by which panel they instance (their Trace child is always a bare
  `fan_trace.tscn`, and per-unit tuning lives at the `fan.tscn` level).
  Investigating inherited scenes / a unit base — see the issue.
