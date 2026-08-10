# Allocation VFX

Cosmetic effects that play when a skill node changes ownership: allocation,
voluntary deallocation, forced deallocation (single + cascade). Lives in
`ui/vfx/allocation_vfx.gd`, mounted alongside `AttackVFX` from `GameRoot`.

## Signals it listens to

| Signal | Source | Fires for | Payload |
|---|---|---|---|
| `allocated(node, entity)` | `AllocationSystem` | every allocation (gated `allocate` + primitive `force_allocate`) | node, new owner |
| `deallocated(node, previous_owner)` | `AllocationSystem` | **voluntary** dealloc only (player/AI spent a DP) | node, previous owner |
| `force_deallocated(node, previous_owner)` | `AllocationSystem` | every forced dealloc (cascade head + every islanded follow-up) | node, previous owner |
| `cascade_started(layers, defender)` | `BattleSystem` | **before** the force-dealloc loop runs; one emission per battle event | BFS layers ordered by graph distance from impact, defender entity |

The split between `deallocated` and `force_deallocated` exists so the VFX can
play a graceful "lift-away" for voluntary releases and a shatter for kills
without sniffing context. Pre-split, both used the same `deallocated` signal.
Existing consumers (currently only `VisionSystem`) connect to both.

`cascade_started` is the orchestration hook for the ripple. It carries
`Array[Array[SkillNode]]` — layer `i` holds every cascade node at BFS depth
`i` from the impact node (layer 0 = `[impact]`). The VFX uses `i * step` as
the per-layer delay so same-depth nodes pop in unison and the wave radiates
outward from the kill site. Each cascade node *also* gets its own
`force_deallocated` emission (preserving the old behaviour for any other
listener); the VFX coordinator de-duplicates by remembering which nodes were
"already scheduled by a cascade".

## Effects

Every effect is a transient `Node2D` parented to the `AllocationVFX` node
(itself a sibling of `AttackVFX` under `Graph`), positioned at the target
SkillNode's `global_position` at spawn time — so the visual survives node
freeing / ownership changes mid-animation. The `AllocationVFX` node sets
`z_index = 2000` (absolute, `z_as_relative = false`) in `_ready` so effects
always render above the `FogOverlay` (z=1000) and the visible/sensed nodes
+ edges it promotes to z=1001 — without this the spike sometimes ends up
*under* a fog-promoted node, since visible nodes get z-promoted to render
above the fog.

Effects never touch `NodeVisualsComposite` itself — that means ownership-state
visuals (`allocation_level`, disk/rim fill color) flip the instant `owned_by`
changes, while the cosmetic effect runs on its own timeline.

### Allocate — "skill point from the heavens"

- A vertical Polygon2D needle (Lorentzian / Breit-Wigner-ish profile,
  see `_build_needle_polygon`) sits flush on the inner disk: base width =
  `2 * SkillNode.inner_radius`, tip pinned to a sharp point, height =
  `radius * SPIKE_HEIGHT_FACTOR` (default 6×).
- Profile tunables: `SPIKE_NEEDLE_GAMMA` (γ in the Lorentzian — lower γ
  → hair-thin needle, higher γ → candle-flame), `SPIKE_SAMPLES` per side.
- Tween (~180 ms): `modulate:a` 0 → 1 → 0 (peak at 40%), `scale:y` 1 → 0
  cubic-ease-in so the needle collapses down into the node center.
- The polygon's own `color` stays opaque (alpha 1); only `modulate.a`
  animates visibility. Polygon2D multiplies the two, so setting
  `Polygon2D.color.a = 0` would zero everything regardless of modulate.
- Fire-and-forget. Does not block input.

### Voluntary deallocate — "lift away into a holy puff"

- Snapshot the *just-deallocated* inner disk: spawn a coloured circle of
  radius `SkillNode.inner_radius` at the node center, owner color
  preserved from the signal payload.
- Tween (~300 ms, all parallel):
  - `position.y` rises by `inner_radius * LIFT_RISE_FACTOR` (sine ease-out)
  - `scale` shrinks to `LIFT_END_SCALE` (default 0.6)
  - `disk_color` shifts owner → `Color.WHITE` over the first 70% (sine
    ease-out) — the "holy puff" bloom
  - `modulate:a` fades 1 → 0 (quad ease-in) — comes in late so the white
    bloom registers before the disk vanishes
- Fire-and-forget.

### Forced deallocate — "shatter"

- Snapshot disk as above (owner color from `previous_owner.color`).
- **Phase 1 — vibrate (~120 ms):** position jitters via a sine-driven
  offset (small amplitude, ~2.5 px) at ~60 Hz.
- **Phase 2 — burst (~400 ms):** snapshot disk hides; a one-shot
  `CPUParticles2D` emits `SHATTER_PARTICLE_COUNT` (default 24) glowy
  particles distributed inside an `inner_radius` sphere, outward radial
  velocity (`SHATTER_OUTWARD_SPEED`), no gravity, owner-color gradient
  fading to 0 alpha over `SHATTER_PARTICLE_LIFETIME` (~350 ms).
- Each cascade node animates on its own timeline, started at
  `layer_index * CASCADE_STEP` (default ~90 ms per ring). The impact node
  fires immediately; one ring later its neighbours; one ring after *their*
  neighbours; until the outermost dying nodes pop.

The cascade is purely cosmetic — the underlying `force_deallocate` calls and
stat-board mutations (wound + core HP loss) all run synchronously inside
`BattleSystem._on_node_depleted` regardless. The VFX layer just paces the
visuals; if a second attack force-deallocs more nodes mid-cascade, both
cascades will overlap on screen, which is fine.

## Why ripple closest-to-impact first

It reads as "the wound spreads outward". The alternative (furthest-first)
implies the periphery is rotting away independently and the impact site is
the last to die, which is the wrong story — the impact *is* what severed
the bridge to the core.

## Sizing: `SkillNode.inner_radius`

All disk-shaped effects (lift, shatter, alloc-spike base) read
`SkillNode.inner_radius` rather than computing `radius - some_inset`.
SkillNode owns the value as a designer-exposed `@export var` and pushes it
down to `NodeVisualsComposite.geom_inner_r` in `_sync_visuals`. The
coordinator has no inset policy of its own — change `inner_radius` on a
node and every effect resizes in lockstep.

## Tunables

Live as `const`s at the top of `allocation_vfx.gd`. Most-touched levers:

- `CASCADE_STEP` — crackle (~50 ms) vs. domino (~200 ms) for chain kills.
- `SPIKE_NEEDLE_GAMMA` — needle vs. candle-flame for the alloc spike.
- `SPIKE_HEIGHT_FACTOR` — alloc spike height as a multiple of node radius.
- `LIFT_RISE_FACTOR` — how far the deallocation puff floats up.
- `SHATTER_OUTWARD_SPEED`, `SHATTER_PARTICLE_COUNT` — shatter intensity.

## Future texture swap

When the central fill becomes a texture, the only change needed is in the
snapshot disk used by lift + shatter: replace `_SnapshotDisk._draw` with a
`Sprite2D` using the same texture. `disk_radius` and `disk_color` already
parameterise it; callers stay valid. The alloc spike has no shape coupling
to the disk and is unaffected.

## Implementation seam

Mounting follows the `AttackVFX` pattern (see
`scenes/game_root.gd:_mount_allocation_vfx`): the coordinator is added as a
child of `Graph` once `AllocationSystem` + `BattleSystem` exist, and its
`bind(allocation_system, battle_system)` wires the signal connections. The
coordinator owns no game state; safe to remove or disable globally without
breaking gameplay.

## Playground

The **Allocation VFX** live tab (`addons/sandbox_host/tabs/40_allocation_tab.tscn`,
embedding `addons/allocation_sandbox/allocation_sandbox_panel.tscn`, #260) runs a
3×3 grid of self-resetting cells, each looping one allocation-flavoured scenario
against the **real** systems (so #71 pulses + #70 floaters fire for real, unlike
the old faked-signal loop). Cells: single-node alloc / dealloc / shatter;
`O-0-0-0-X` allocate → three modifiers travel to core; `X-O-O-O-O` bulk allocate
from core; and on a fully-allocated row — voluntary dealloc, forced-dealloc,
mid-row force-dealloc → islanding cascade, and core death → full cascade. Each
cell renders its entity's live STRENGTH so the gap between the resolved value
and the trailing visuals is visible. The old played showcase's infinite
SETUP→PLAY loop is now one explicit **▶ Play beat** click (auto-tick = played;
explicit-step = live — see `sandbox-framework.md`); **⟲ Reset** re-arms without
playing. Systems are composed + wired in code exactly as `GameRoot._ready` wires
them (via `SandboxWorld`); the grid is generated procedurally. No play step, no
`godot --path` — the tab runs live in the editor.
