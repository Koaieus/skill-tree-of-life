# VFX units — coordinators and the shard field

Per-unit contracts for the `ui/vfx/` pieces that are not in the shared kit table
(`docs/domain/spell-vfx-kit.md`). Clocks: `docs/domain/presentation-clock.md`.

## ArrowVolleyCoordinator (`ui/vfx/coordinator/arrow_volley_coordinator.gd`)

Ranged-attack volley: one `Projectile` per entry of `AttackOutcome.hits` — literally
every one, per scheduled shot — all converging on the same target. Each shot's launch
is staggered by `RangedAttackPlan`'s authored ramp, recovered from the shot's own
`ScheduleEntry` window, not a per-index constant — so a wide volley reads as a flurry
of arrival impacts rather than one monolithic THWACK. (The ramp is metric, so leaves
at the SAME distance genuinely fire together; a perfectly symmetric firing ring
collapses back to one THWACK by construction.)

**Pure observer** — it never calls `take_damage`; it only renders. It runs
CONCURRENTLY with the mutation loop: `BattleSystem` starts `play` un-awaited and
`OutcomeApplier` lands each hit at that hit's own `arrival_time`, so the arrow is in
flight while its damage is still pending. The HP bar, shatter, fog and damage number
all move as the arrow strikes because they read the model. The applier waits on its
own timer, never on this animation, so dropping every frame here leaves the applied
world identical.

Uses the `LightArrow` visual by default — an oriented glowing arrow that sticks into
the target node and fades. A typed shot flies its own `AmmoType.visual_scene`, picked
PER SHOT off `HitInstance.ammo_type_id` through `ammo_roster` — so a rebuilt record
draws what the host drew — and is stamped the type's status colour as `status_tint`
beside the attacker `tint`. Arrows are tinted by the attacker's `Entity.color`, read
off `HitInstance.attacker` (the record round-trip drops `HitInstance.source`, so tint
must never read it).

**Every scheduled shot flies and arrives, whatever it did** — no filter on outcome,
by owner call (see `play`). A shot the land-time gate vetoes (target overkilled
mid-volley) lands INERT, and a shot that mitigated to zero or flipped to a heal still
draws its arrow: see `_on_arrow_arrived`.

### The arrival beats (`_on_arrow_arrived`)

`hit` is the SAME `HitInstance` `OutcomeApplier` just landed (or vetoed):
`HitInstance.gated` is the model telling this arrow how it resolved, read at the
arrow's own arrival rather than predicted at launch (the gate is only knowable once
the model re-checks it live, per `docs/domain/attack-timeline.md`).

- A live hit needs nothing: `_resolve_tint`'s launch-time stamp already stands.
- A **gated** one desaturates (the dud beat): no damage number follows (the applier
  never called `take_damage`, so `Events.skill_node_damaged` never fires), so the
  arrow itself carries "this overkilled". Named-tier only
  (`.claude/rules/hdr-color.md`); `Emissive.INERT` is the "visible, never blooms"
  reading.
- `_on_dud()` is part of the duck-typed visual contract beside `_on_launch()` /
  `_on_progress(t)` / `_on_arrival()` — the visual owns what a dud looks like, because
  only it knows which tiers its own `_draw` applies. `LightArrow` desaturates and
  drops to `Emissive.INERT`. A visual without the hook renders no dud; the
  coordinator does NOT reach in and retint it, which would couple this file to that
  visual's emissive choices.
- The same read picks the **absorb** beat, `_on_absorbed(gained)`, for a landing that
  went through mitigation and changed nothing hostile: `gained = true` when it flipped
  to `HitInstance.Kind.HEAL` (the shot fed the defender), `false` when it mitigated to
  exactly zero (the armour held). The gate is checked first: a gated hit never reached
  mitigation and its `effective_amount` is 0.0 by construction, so it must never read
  as "held". Only the impact beat differs — the flight never anticipates the outcome.
- Every landing that was not a dud then gets `_on_impact(ctx)` with its
  `impact_context_for`, after the absorb beat, so the visual decides with the whole
  verdict in hand (`StatusArrow` plays its impact parts).

## MagicBounceCoordinator (`ui/vfx/coordinator/magic_bounce_coordinator.gd`)

Plays a multi-hop spell's visual sequence. Walks `AttackOutcome.timeline`
(`PropagationEvent`s), groups it by `PropagationEvent.beat`, and fires one wave per
beat on a fixed clock read off the cast's compiled `OutcomeSchedule`: beat N impacts
at `lead_in + N * beat_interval` relative to `play`.

**The clock is the ground truth.** Animations do NOT gate the clock. Each spawned
`Projectile` is given `flight_time` as its flight budget so the visual lands roughly
when the next wave fires — but a visual that lingers past its window (long trail, slow
fade) keeps playing in parallel with the next hop's projectiles. That parallel
stacking IS the look for branchy spells (fork lightning). Awaiting "previous
projectile finished" would let a slow fork hold up the propagation.

**Impact is pinned to the beat, not to launch.** Projectiles are spawned early (one
`OutcomeSchedule.lead_in` ahead of the beat) so they arrive exactly at the beat. The
visual's windup/linger is free to start before and outlive impact — the coordinator
only gates on the wave clock.

**Both numbers come from the schedule, not from an export here.** `PresentationTempo`
is their single home and `OutcomeSchedule.compile` their only reader, so the
mutation clock and the picture cannot drift apart.

**Verb -> ProjectilePath mapping.** Each `PropagationEvent.Verb` can carry its own
path and visual: `jump_path`/`jump_visual` (JUMP, the seed), `edge_path`/`edge_visual`
(EDGE), `self_loop_path`/`self_loop_visual` (SELF_LOOP), `cancel_visual` (CANCEL
dissipate, no path). Unset slots fall back to `projectile_path` / `visual_scene`, then
to built-in defaults.

**Pure observer.** `PropagationEvent.hits` have ALREADY landed by the time `play`
runs — `BattleSystem` applies the whole `AttackOutcome` synchronously before any VFX
await starts. This coordinator never calls `take_damage`/`heal_damage`; it only renders.

## ShatterField (`ui/vfx/shatter/shatter_field.gd`)

The pooled, scrub-driven shard field a dying object fragments into. Blade pops and
node deaths both spawn into one of these instead of each rolling their own particle
sphere.

**The operation:** take an object that is dying, replace it with pieces that inherit
its momentum, and let them coast and fizzle. The owner's rule for how far a piece
travels is the whole motion model — *"how far they travel depends on their momentum
at disconnection + simulation time left, that's all really"* — so a shard's position
is its seed velocity integrated over elapsed window time. No drag, no authored travel
distance.

**What lives here vs. in the consumer.** This node owns the shard *field*: the one
shared quad every shard is drawn as, the per-instance packing, the pool, and the
motion/fade curve in `ui/vfx/shatter/shatter_motion.gdshaderinc`. The consumer owns
what a shard *looks like* — a `ShaderMaterial` whose shader `#include`s that file (see
`shatter_shard.gdshader`, the flat-tint reference look) and decides the fragment's
colour inside the cell the include hands it. GLSL has no inheritance; the include IS
the reuse.

**One draw call, by construction.** A single `MultiMeshInstance2D` over ONE unit
`QuadMesh`, oversized `OVERSIZE`x the source radius so a shard can spin about its own
pivot (and rays can leak) without leaving the quad. Every shard is that same quad; its
*shape* is decided in the fragment shader (analytic Voronoi: a fragment belongs to
cell K iff seed K is its nearest, `discard` otherwise). Per-shard variation rides
`COLOR` + `INSTANCE_CUSTOM` and the instance transform, never `instance uniform`s (a
MultiMesh's instances share one CanvasItem) and never per-shard uniforms. Same idiom
as `graph/edge.gd` + `graph/edge_mesh.gdshader`.

**Progress is supplied, never self-timed** (`.claude/rules/presentation-clock.md`).
No `Tween`, no wall clock, no `_process`. The consumer sets `elapsed` on *its* clock
(trajectory time for blade pops, the cascade clock for node deaths) and the shader
derives every shard's progress from that one uniform against the shard's own spawn
time. Seeking backwards just sets a smaller number: nothing on the CPU accumulates, so
`elapsed = t1; elapsed = t0; elapsed = t1` leaves every pushed value byte-identical.
The one caveat is the pool — see `spawn_shatter`.

**Packing** (must match `shatter_motion.gdshaderinc`'s `shatter_unpack`):

```
COLOR             = tint lifted by spawn_tier via Emissive.at()
INSTANCE_CUSTOM   = (velocity.x, velocity.y, spawn_time - time_base, pack_shard())
shatter_carve_tex = per slot, the source's CarveParams as CarveParams.TEXELS RGBAF
                    texels at INSTANCE_ID (32-bit, NOT half: a texture, not the
                    instance buffer)
transform         = origin at the source, uniform scale 2 * radius * OVERSIZE, never
                    rotated
```

Never rotated: `radial_kick`'s angle for cell K and the shader's seed placement for
cell K agree only while local axes equal world axes. The shader also hashes the
fracture pattern's seed from this origin, so the field must sit under a parent that
does not move.

**Everything packed is exact in a HALF float.** The compatibility renderer stores a 2D
MultiMesh's colour and custom data as 16-bit halves (probed 2026-09-10: `custom.w =
2049` reads back as 2048 under opengl3), which is why cells are capped at `MAX_CELLS`
(`cell + count * 32 < 2048`), the fracture seed is not a channel at all, and spawn
times are stored relative to `time_base` — a run-long clock would otherwise lose the
whole window to half-float spacing after a few thousand seconds.

Headless Godot cannot read a MultiMesh's buffer back
(`docs/domain/rendering-performance.md`), so every push is mirrored in the
`_origins`/`_sides`/`_colors`/`_customs` arrays — the pool needs the spawn time per
slot anyway, the rest makes the field testable and repopulates the buffer after a
capacity growth (which discards it; see `Graph._grow_edge_mesh_capacity`).
