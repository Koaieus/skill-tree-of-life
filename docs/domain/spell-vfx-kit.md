# The shared spell-VFX primitive kit (#670)

Five composable primitives that every per-spell VFX unit (#671-#678) assembles
from, so eight spells share one vocabulary instead of authoring eight. The
always-on pointer lives in [`.claude/rules/spell-vfx.md`](../../.claude/rules/spell-vfx.md);
this is the catalogue and the reasoning.

Everything here is previewable from the sandbox host's **VFX tab**, left column
(`addons/sandbox_host/tabs/20_vfx_primitives.gd`): body x path x ease x crit
tier, on its own stage. That gallery's catalogues are the shopping list — if a
primitive is not in them, a per-spell unit will not find it.

## The catalogue

### ProjectilePath — the seven shapes

| Path | File | Use |
|---|---|---|
| `BezierArcPath` | `ui/vfx/projectile/path/bezier_arc_path.gd` | Quadratic arc through apex. Default for JUMP. |
| `LinearPath` | `ui/vfx/projectile/path/linear_path.gd` | Straight lerp origin→target. Canonical for EDGE. |
| `SelfLoopPath` | `ui/vfx/projectile/path/self_loop_path.gd` | Cubic Bezier teardrop loop. For SELF_LOOP (origin == target). |
| `CubicBezierPath` | `ui/vfx/projectile/path/cubic_bezier_path.gd` | General cubic with launch/arrival tangents. |
| `Curve2DPath` | `ui/vfx/projectile/path/curve2d_path.gd` | Authored `Curve2D` sampled and mapped. Used by AllocationVFX. |
| `WavePath` | `ui/vfx/projectile/path/wave_path.gd` | Lerp + transverse sine (#670 P3). "This propagates" rather than "this was thrown". Reverberator / Resonator. |
| `JitterPath` | `ui/vfx/projectile/path/jitter_path.gd` | Lerp + perpendicular hash noise (#670 P4). Unstable arcing electricity. Spark / the lightning family. |
| **Bounce** | `ui/vfx/projectile/path/bounce_path.tres` | The pre-#663 house look, as an authored `.tres` rather than a class (#684). A `BezierArcPath` at `apex_height = 420` — a high lob **over** the edge rather than a traversal along it. Reverberator. |

**Bounce is the catalogue's one authored entry, and that is the point.** Every
other row is a shape you get by `new()`-ing a script; Bounce is a *tuning* of
`BezierArcPath` — no new geometry, so a `BouncePath extends BezierArcPath`
would be a second name for one shape. Before #684 that tuning lived as an
anonymous `SubResource` inside `magic_bounce_coordinator.tscn`'s legacy
`projectile_path` slot: it was the fallback every spell fell through to, and
when #663 gave all eight their own coordinators it stopped being rendered by
anything. A named `.tres` is composable into any per-verb slot on any
coordinator; a `SubResource` is reachable only from the scene that owns it.

It is a **shared, live** resource — the shared coordinator's fallback slot and
Reverberator's `jump_path`/`edge_path` all reference the same instance. That is
safe because `evaluate` is pure and nothing mutates a path at runtime, but it
means anything that *does* want to retune it must `duplicate()` first (the
sandbox gallery does, for exactly this reason).

| Primitive | Files | What it is |
|---|---|---|
| `BoltBody` | `ui/vfx/projectile/visual/bolt_body.tscn` + five inherited configs (`bolt_small` / `_blunt` / `_streak` / `_packet` / `_soft`) | The workhorse body. Supersedes `GlowingDot` **for spell use** — `GlowingDot` is not deleted, it has non-spell callers. `MAX_TRAIL_SEGMENTS` is **8** (#663, was 4); `_TAPER_SPAN` stays pinned at 4 so raising the cap re-spread nothing, and segments past the fourth extend the tail at tail values. |
| `ImpactRing` | `ui/vfx/projectile/visual/impact_ring.tscn`, `impact_ring_absorb.tscn` | Punctuation, and the **sole home of the crit grammar**. `OUT` = impact, `IN` = absorb/gather. |
| `WavePath` | `ui/vfx/projectile/path/wave_path.gd` | Lerp + transverse sine. "This propagates" rather than "this was thrown". Reverberator / Resonator. |
| `JitterPath` | `ui/vfx/projectile/path/jitter_path.gd` | Lerp + perpendicular hash noise. Unstable arcing electricity. Spark / the lightning family. |
| `EdgeEnergize` | `ui/vfx/projectile/visual/edge_energize.tscn` + `edge_energize.gdshader` | A travelling front of light **painted on top of** an edge. Composed one-per-bolt by Resonator (`resonator_edge_visual.tscn`, #678) and N-per-closure by Cyclone (`cyclone_ring_flash.tscn`, #710 — one front laps the whole closed ring in walk order over a fixed `lap_seconds`, wraparound edge included). Both are spell-specific compositions deliberately **not** catalogued here; `CycloneRingFlash` takes a plain polyline, so promoting it to a kit `RingFlash` when a second spell has a ring to light is a rename plus a gallery entry. |
| `GhostLoopBody` | `ui/vfx/projectile/visual/ghost_loop_body.tscn` | A body wearing TWO heads — a lead plus a `ghost_alpha`-dimmed twin sampled `GHOST_T_OFFSET` behind it, off the lead's own recorded `(t, position)` history rather than a second copy of the path. "An echo chasing itself." Drop-in for any `body_scene` slot; worn by Reverberator (#677) and Resonator (#678). |

### `ComposedProjectileVisual` — how a spell gets a body AND a ring

A `Projectile`'s `visual_scene` slot takes **one** scene per verb, but nearly
every spell wants a flying `BoltBody` *and* an arriving `ImpactRing` (the crit
grammar). `ui/vfx/projectile/visual/composed_projectile_visual.gd` is the shared
wrapper that composes them, authored for #671/#672 and **intended for every
per-spell unit after them — compose with it, do not re-invent it.**

- `body_scene` — the flight body, instantiated up front, lives the whole flight.
- `arrival_companions` — spawned **only at `_on_arrival`**, in order. Not as
  static children, and this is load-bearing: `ImpactRing` autoplays on `_ready`
  unless its DIRECT parent is a `Projectile`, so a ring authored one level deeper
  would defeat that guard and fire a full flight early.
- `forward_crit_to_body` (default true) — set false when the body must not
  escalate on a crit while the ring still does (Bruiser, which must never read
  as lethal).
- `tint` — forwarded down to the body only, never to companions. See below.

It forwards the whole duck-typed visual contract to the body, and to each
companion as it spawns. Its own `finished` fires deferred once every child that
has one has fired — deferred because a zero-length fade would otherwise emit
before `Projectile`'s `await finished` is listening, which hangs forever.

### The caster tint reaches the body through the wrapper (#663 D4)

`MagicBounceCoordinator` resolves the caster **once per cast** and stamps the
projectile's visual right after `launch`, mirroring `ArrowVolleyCoordinator`.
Once per cast, not per event, because a spell has one caster and a
CANCEL/pure-utility event carries no hit to read an attacker off.

This did not exist until #671/#672: ranged had stamped since #507, magic never
had, and **this document already described the stamp as though it were
there.** Nothing caught it because no magic body read `tint` (`GlowingDot`
ignores it) and no test asserted the colour arrives. Every spell rendered
neutral-white. Pinned now by `test/unit/vfx/test_caster_tint_stamp.gd`.

The wrapper sits BETWEEN the projectile and the body, so it must forward the
stamp down — a stamp that stops at the wrapper is invisible in exactly the
composed case every spell uses. It is **not** forwarded to arrival companions:
`ImpactRing` is punctuation owning its own tier colour, and tinting it with the
caster's would make "where it fired" read as identity rather than as placement.

**The crit grammar is authored once, in `ImpactRing`** (#663 D6): tier 1 = one
ring at `Emissive.ALERT`; tier 2+ = a second concentric ring plus a
**single-frame** `Emissive.PEAK` core flash. **It is the IMPACT punctuation
first and the crit grammar second** — it plays on *every* arrival, with
`crit_tier = 0` meaning one plain ring at rest, and the grammar *"overrides this
upward; it never overrides it downward"*. So a crit reads as an **escalation** of
a ring that was already there, never as the ring's mere existence; spec an
acceptance criterion as "a non-crit rings at tier 0", not "a non-crit spawns no
ring" (#709 was written to the wrong one first). A spell gets its crit look by
*configuring that scene*, never by writing a second one — that is what keeps
"where it fired" reading as placement rather than as three different effects.

**Identity is motion and heat, never hue** (#663 D3). The body colour is the
**caster's** tint, stamped by the coordinator after `proj.launch()` (the same
stamp `ArrowVolleyCoordinator` already makes on `LightArrow`).

#### Per-arc weight: `BoltBody.arc_weight` (#708)

A spell that **splits its damage across a fan** needs each drawn bolt to say how
much it is carrying. Cyclone's rank-1 arc takes 0.70 of the incoming damage and
its rank-3 offshoot 0.20, and before #708 they were the same picture.

The value rides the **per-projectile stamp**, next to `tint`, and it has to:
`_on_context(entry)` is the surface every visual reads, but a `ScheduleEntry` is
**one landing moment**, and a convergence is one entry holding several arcs. It
structurally cannot carry a per-arc number.

- `MagicBounceCoordinator` stamps `arc_weight` on `proj.get_child(0)` right after
  `launch()`, under the same `in` guard `tint` uses, from
  `PropagationEvent.incident_shares[i]` — where `i` is the arc's index, which is
  why `_arc_indices_for` returns indices rather than nodes. Resolving to nodes
  first and looking the weight up afterwards is exactly how the two arrays drift.
- `ComposedProjectileVisual` forwards it with the **setter + `_ready` re-push**
  pair `tint` has, because the stamp can land before the body exists. Body only,
  never the arrival companions: a weak offshoot must still punctuate at full
  strength, and dimming an `ImpactRing` by its share would undo the crit grammar.
- **`arc_weight_influence` defaults to 0**, so the channel is opt-in and the eight
  spells that do not split are untouched by construction. Cyclone's own
  `cyclone_body.tscn` sets it to 1 (direct proportion) and raises `head_size`, so
  a 0.20 offshoot is scaled down and still visible.

Direct proportion rather than a softened curve, because *"bolt size means current
damage"* is already learned vocabulary from #663 D3's Lightning/Leafblower
teaching pair. A splitting spell is saying the same sentence about the same
quantity, one hop earlier.

#### Per-landing weight: `BoltBody.magnitude_influence` (#663)

The same sentence again, one granularity out: `arc_weight` splits ONE wave across
a fan, `magnitude` ranks the waves against each other. `ScheduleEntry.magnitude`
is this landing's authored hit amount as a fraction of the largest landing in the
same outcome, normalized 0..1 by the compiler because it is the only thing that
sees a whole outcome at once. It rode `_on_context` from #543 and was read by
nothing until now.

Deliberately the same opt-in shape as `arc_weight_influence` — default 0.0, so
all nine configs provably take the old path — so there is one idiom to learn
rather than two. It only ever **shrinks**: magnitude tops out at 1.0 on the
biggest entry, so opting in cannot inflate a spell past its authored silhouette.
`_magnitude` defaults to 1.0, not 0.0 — an opted-in body that never receives an
entry must draw at full size rather than vanish.

**`SpellDef.power` is NOT the hook for this, and the mistake is inviting.** Power
is a coefficient, not a damage: `spell_def.gd` is explicit that the seed hit is
`spell_damage(cast-from node) x power`, so a power-3 spell from a weak caster
lands softer than a power-1 spell from a strong one. Sizing off power would
contradict D3's lesson every time the caster and the coefficient disagree.

**Cross-SPELL loudness has no derived answer and stays authored** in each
config's `head_size`. Nothing in a resolved outcome carries an absolute,
comparable "how loud is this spell" — magnitude is normalized *within* one cast —
so "Lightning should read bigger than Spark" is a designer's judgement, made by
eye against the spell playground's Loop toggle.

**Never put per-arc weight on the wrapper's `modulate`.** `ComposedProjectileVisual`
is a `Node2D`, so `modulate` cascades to the `ImpactRing` too.

### `WavePath.handedness` — which side the bow rides (#708)

`amplitude` is *how wide*; `handedness` (+1/-1) multiplies the perpendicular and
is *which side*. Two knobs rather than a signed amplitude, because a negative
amplitude held only at runtime is invisible to whoever opens the `.tscn` — and
widening the amplitude range would re-label the knob for Reverberator and
Resonator, which share the class and leave `handedness` at 1.0.

The coordinator resolves the cast's `turn_sign` **once per cast** (in `play()`,
beside the caster tint) and caches one flipped `duplicate()` **per verb**, cleared
per cast. Paths are shared live resources, so the sign can never be written onto
the authored one — and a whole hex wheel costs at most two duplicates, never one
per bolt. A `+1` or absent sign hands back the shared resource and allocates
nothing.

## Two things that will silently cost 60x

1. **Never a per-instance `ShaderMaterial`, and never animate a per-instance
   shader uniform.** Batching breaks on a different texture *or* a different
   material. All `BoltBody` instances share one texture + one `CanvasItemMaterial`;
   all `EdgeEnergize` overlays share one `ShaderMaterial`. Per-instance variation
   goes in `modulate`, transform, UV offset or `INSTANCE_CUSTOM` — nowhere else.
   `test_bolt_body.gd` and `test_edge_energize.gd` pin this at 60 instances.
2. **`EdgeEnergize` paints on top; it never touches `Edge`, `Graph` or the edge
   MultiMesh** (#670, settled — do not "optimize" it in there). All 8 per-instance
   floats of `edge_mesh.gdshader` are spoken for, and going that route would make
   the VFX layer a third writer into a two-writer buffer *and* need
   interrupt-restore semantics, which is the stuck-state bug class the
   presentation-clock arc spent five issues killing. Its width comes from the
   `edge_camera_zoom` global the edge itself reads, plus a one-time push of the
   edge material's own `width` — no CPU mirror. Concurrency is bounded by
   **linger, not hop count**: `EdgeEnergize.max_live_overlays(linger, beat)`.
   (#663 D7 removes Trail Blazer's `max_hops`, so any "at most 20" reasoning is
   wrong.)

Opt-in needs no new knob: the coordinator's per-verb `edge_visual` / `jump_visual`
/ … slots already express it. A bool on the def or the tempo resource would be a
second parallel opt-in channel for something the slot system already says.

> `docs/domain/spell-propagation.md` was checked against this and needs **no**
> #670 change: the rule cross-references it for the *verb vocabulary*, and #670
> adds no verb — it only widens the vocabulary of paths and visuals the existing
> verbs resolve to.
`docs/domain/spell-propagation.md` was checked against #670 and needs **no**
change: `.claude/rules/spell-vfx.md` cross-references it for the *verb
vocabulary*, and #670 adds no verb — it only widens the vocabulary of paths and
visuals the existing verbs resolve to.

## The ease knob on `ProjectilePath`

Every path carries `ease_curve` (a named enum: `LINEAR`/`IN`/`OUT`/`IN_OUT`/
`OUT_IN`) plus `ease_strength` (0..1). `Projectile` feeds a strictly **linear**
`t` — it is a clock and has no business deciding pacing — so per-spell motion
personality had nowhere to live except a bespoke subclass. Each path now runs
its incoming `t` through `eased()` as its first line.

**It remaps time, not shape.** `eased(0) == 0`, `eased(1) == 1`, monotonic — so
a path's endpoints are untouched and the coordinator's impact-on-the-beat
alignment survives any curve. `LINEAR` (the default) and strength 0 are the
exact identity, which is why adding the knob moved nothing already shipped.
Pinned in `test/unit/vfx/test_projectile_paths.gd`.

`JitterPath`'s randomness is **unseeded on purpose**, and its class docs say so
at length so a future reader does not "fix" it. No peer reproduces a
projectile's wiggle — it is not a result, nothing downstream reads it, and two
machines drawing two different squiggles between the same two nodes is not a
desync. So `.claude/rules/multiplayer-sync.md`'s unseeded-roll prohibition does
not reach it. Once resolved the seed is fixed, so `evaluate` stays a pure
function of `t` and a shared path resource cannot drift between two visuals.

## Design decisions behind it (settled on #663/#670 — do not re-open)

- **Identity is motion and heat, never hue** (#663 D3). Do not add colours to
  tell two spells apart; change the silhouette, the trail, the size ramp, the
  path.
- **The baseline body is the caster's identity tint** (#663 D4), stamped by the
  coordinator after `proj.launch()` — the same stamp `ArrowVolleyCoordinator`
  already makes on `LightArrow`. `GlowingDot`'s old gold default is in the
  reserved band and does not carry forward.
- **`GlowingDot` is not deleted.** It has non-spell callers; `BoltBody`
  supersedes it *for spell use* only. Retiring it is separate cleanup.
- **`_on_context(entry)` takes a `Variant`**, not a `ScheduleEntry`. The visual
  contract is duck-typed ("any subset, all optional"), and a visual should keep
  working when a coordinator hands it a shape it does not read. `VfxContext`
  (`ui/vfx/projectile/visual/vfx_context.gd`) is the one careful accessor for
  those reads, so there is not a defensive `if field in obj` at every call site.
  A visual that genuinely needs a field may tighten its own parameter type once
  #543 has landed.

## Why `EdgeEnergize` paints on top rather than riding the edge MultiMesh

The tempting route — stash energize state in a spare `INSTANCE_CUSTOM` channel
of `graph/edge_mesh.gdshader` — **is not available**, and this is worth writing
down because it looks free:

- All 8 per-instance floats are spoken for. `COLOR.rgb` is endpoint-A colour
  with the HDR lift baked in, `COLOR.a` is the shared alpha,
  `INSTANCE_CUSTOM.rgb` is endpoint-B colour, and `INSTANCE_CUSTOM.a` is a
  **three-digit packed field** (vis state + 10x self-loop + 100x clamp code)
  whose constants are mirrored in lockstep across `graph/edge.gd` and the
  shader — and which has already produced one decode-order bug.
- Taking it would make the VFX layer a **third writer** into a buffer
  `Graph`/`Edge` own under a strict two-writer discipline.
- It would need interrupt-restore semantics: a cast cut short by teardown
  (`BeatClock.drain()` inside `_exit_tree`) would leave edges stuck energized.
  That is the exact stuck-state bug class the presentation-clock arc spent five
  issues killing.

Paint-on-top is self-cleaning: the overlay frees itself and the edge was never
touched. `test/unit/vfx/test_edge_energize.gd` pins it at the source level,
because by the time the symptom shows up (a stuck-energized edge after a
teardown) no unit test would catch it.

Two further properties worth not breaking:

- **Width has no CPU mirror.** The shader reads the same
  `global uniform float edge_camera_zoom` that `graph/edge_mesh.gdshader` reads
  (pushed by `GraphCamera` on every zoom step), and `EdgeEnergize._sync_width()`
  pushes the *edge material's own* authored `width` onto the shared overlay
  material once at load. Retune the edge and the overlay follows.
- **The front's heat is expressed in EV stops**, and the shader does the lift in
  linear space through the exact sRGB transfer pair — so "one stop" means the
  same thing there that it means to `ui/theme/emissive.gd`. Resting tier is
  `VALUE` (a lit edge already carries a baked `VALUE` lift, and
  additive-on-lifted goes white fast); only the moving front reaches `ALERT`.
  See [hdr-color.md](hdr-color.md).

**Fog-oblivious, on purpose** (owner call 2026-08-30), matching every existing
spell visual: `GlowingDot` bolts already fly over `FogOverlay`, and
`AllocationVFX` z-promotes to `ZLayers.SPELL_VFX` specifically to win over it. A
fog-aware overlay sitting next to fog-oblivious bolts would read as a bug.
Fog-awareness is a one-line upgrade whenever fog-gating arrives — `#include`
`ui/vision_field.gdshaderinc` and multiply alpha by `vision_field_dim(world_pos)`,
the reader role #413 designed that file for.

## Tuning knobs, and where they live

The kit ships with authored defaults that have **not** been verified in a real
frame. The named constants an owner is most likely to want to move:

| Knob | Home | What it does |
|---|---|---|
| `front_gain_stops` (default 1.0) | `ui/vfx/projectile/visual/edge_energize_material.tres` | EV stops the moving front sits above the body. 1.0 = the VALUE→ALERT step. |
| `width_scale` (1.6) | same | How much wider than the edge the overlay sits. |
| `tail_level` (0.45) | same | Body brightness at the trailing end. |
| `front_width` (0.28) | same | Fraction of the quad the hot front occupies. |
| `linger_seconds` (2.5) | `edge_energize.tscn` / per-spell override | The burn-in fade — **and the thing that sets peak overlay count**, via `EdgeEnergize.max_live_overlays(linger, beat)`. Read #663's load table before raising it. |
| `head_size`, `trail_length`, `hop_scale_start/end` | the five `bolt_*.tscn` configs | Per-config silhouette and the #663 D3 size ramp. `head_size` is also the ONLY cross-spell loudness lever — see the magnitude section above for why nothing derives it. |
| `trail_alpha_head` (0.7) / `trail_alpha_tail` (0.05) | the `bolt_*.tscn` configs | Trail alpha ramp, previously hardcoded. Lifting the tail is what turns the segments past `_TAPER_SPAN` into a *flurry* (several arcs of comparable weight) rather than a fade. |
| `stretch_along_velocity` (0.0) | the `bolt_*.tscn` configs | Squash-and-stretch along travel — the disc-to-arc knob. Needs a stable facing; on a jagged path pair it with `facing_smoothing_seconds`. |
| `magnitude_influence` (0.0) | the `bolt_*.tscn` configs | Opt-in per-landing sizing. See above. |
| `facing_smoothing_seconds` (0.0) | `MagicBounceCoordinator`, forwarded to every `Projectile` | Low-passes `face_velocity`. `JitterPath`'s hard corners throw the snapped facing ~24 degrees off the travel line for one frame at each noise boundary — invisible on a symmetric disc, a wobble on a stretched one. 0.0 snaps, as before. |
| `radius`, `expand_radius`, `thickness`, `squash` | `impact_ring.tscn` / `impact_ring_absorb.tscn` | Ring geometry. |
| the `0.12` convergence widening coefficient | `ui/vfx/projectile/visual/impact_ring.gd` `_on_context` | How much each extra converging predecessor widens the ring. In code rather than on the scene, because it is a *rate*, not a per-config silhouette — Resonator is the only spell that will exercise it. |

Emissive values are **never** hand-picked floats: everything routes through
`Emissive.at` / `.tint` / `.tint_peak` with a named tier.
