# Allocation VFX

Cosmetic effects that play when a skill node changes ownership: allocation,
voluntary deallocation, forced deallocation (single + cascade), plus the modifier
pulses an allocation sends to the core and the blade-pop burst. Lives in
`ui/vfx/allocation_vfx.gd`; `AllocationVFX` is a scene child of `Graph` in
`scenes/game_root.tscn` (`%AllocationVFX`, sibling of `AttackVFX`) with exported
`allocation_system` / `battle_system` that `_ready` binds. It owns no game state
and is safe to remove or mute (`muted`) without affecting gameplay.

## Signals it listens to

| Signal | Source | Fires for | Payload |
|---|---|---|---|
| `allocated(node, entity, forced)` | `AllocationSystem` | every allocation: gated `allocate` (`forced = false`) and primitive `force_allocate` (`forced = true`) | node, new owner, forced |
| `deallocated(node, previous_owner)` | `AllocationSystem` | **voluntary** dealloc only | node, previous owner |
| `force_deallocated(node, previous_owner)` | `AllocationSystem` | every forced dealloc (cascade head + every islanded follow-up) | node, previous owner |
| `cascade_started(layers, defender)` | `BattleSystem` | **before** a forced-dealloc loop runs, once per cascade: a battle event's cascade, or a dying entity's whole board | BFS layers by graph distance from the impact (or the core), defender entity |
| `Events.blade_vertex_popped(defender, attacker, at_pos)` | blade sim | a spike vertex popping | for the pop burst |

`deallocated` and `force_deallocated` stay separate so the VFX plays a graceful
lift-away for voluntary releases and a shatter for kills without sniffing context.
Other consumers connect to the same signals: `VisionSystem`, `HighlightController`,
`AuraOverlay`, `systems/armed/magic_mode.gd`, and `combat/entity_combat.gd` (which
dispatches `_on_node_deallocated`).

`cascade_started` carries `Array[Array[SkillNode]]`: layer `i` holds every cascade
node at BFS depth `i` (layer 0 = `[impact]`). The VFX uses `i * CASCADE_STEP` as the
per-layer delay so same-depth nodes pop in unison and the wave radiates outward.
`_on_cascade_started` runs BEFORE `force_deallocate`, so it snapshots each node's
position, radius, colour and `carve_params()` (the stake collapsing on dealloc
shrinks `inner_radius`) plus its delay slot into `_cascade_snapshot`;
`_on_force_deallocated` consumes the entry and spawns the shatter. A standalone
force-dealloc has no entry and reads live values at zero delay.

## Effects

Every effect is a transient `Node2D` parented to `AllocationVFX`, positioned at the
target SkillNode's `global_position` at spawn time, so the visual survives node
freeing / ownership changes mid-animation. `_ready` sets `z_as_relative = false`
and `z_index = ZLayers.SPELL_VFX` (absolute) so effects render above the
`FogOverlay` and the nodes and edges it promotes, and children inherit that floor.

Effects never touch `NodeVisualsComposite`: ownership-state visuals flip the instant
`owned_by` changes while the effect runs on its own timeline.

### Allocate — "skill point from the heavens"

- A vertical Polygon2D needle (Lorentzian / Breit-Wigner-ish profile,
  see `_build_needle_polygon`) sits flush on the inner disk: base width =
  `2 * SkillNode.inner_radius`, tip pinned to a sharp point, height =
  `radius * SPIKE_HEIGHT_FACTOR` (default 6×).
- Profile tunables: `SPIKE_NEEDLE_GAMMA` (γ in the Lorentzian — lower γ
  → hair-thin needle, higher γ → candle-flame), `SPIKE_SAMPLES` per side.
- Tween (`SPIKE_DURATION`, 0.4 s): `modulate:a` 0 → 1 → 0 (peak at 40%), `scale:y` 1 → 0
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

- `_spawn_shatter` fragments the dying node's own dome into the `ShatterField`
  (`inner_disk_shatter_field.tscn`, a child of `AllocationVFX`): an intact-disc
  crescendo (the crack seams glow) through the cascade `delay`, then the disc comes
  apart at `shatter_flight_start` and the shards bloom, fly and fizzle. The rim is
  untouched; the shards keep the node's carve glyph (`CarveParams`). The real
  SkillNode's InnerDisk hides at `force_deallocate`, and the shard field takes over.
- Tunables are exports on `AllocationVFX` (`shatter_window`, `shatter_flight_start`,
  `shatter_shard_count`, `shatter_fling_speed`, tier exports) plus the shatter
  material's own knobs; `_push_shatter_tuning` forwards them.
- Each cascade node starts at `layer_index * CASCADE_STEP` (0.35 s per ring): the
  impact node immediately, its neighbours one ring later, and so on outward.

The cascade mutates synchronously (all layers inside one beat: wound, core HP loss,
`force_deallocate` calls in `BattleSystem._on_node_depleted`); the layered ripple is
pure animation here. If a second attack force-deallocs more nodes mid-cascade, both
cascades overlap on screen.

### Entity death — one core-first wave

When an entity dies, `AllocationSystem.deallocate_all_owned` strips its whole board
un-staggered, core LAST (island checks). The visual wave is the opposite, core
FIRST rippling outward: `BattleSystem._on_entity_dying` (the pre-cleanup phase, while
the corpse still owns its nodes) BFS-layers the owned set from the core and emits the
same `cascade_started`. The delay map is keyed by node, so the mutation order and the
visual order never have to agree.

A direct hit that empties the core's `health` in one blow bypasses
`_on_node_depleted` (the core never emits `depleted`; see
`.claude/rules/entity-death.md`), but the `entity_dying` wave still covers it.

### Modifier pulses

On a non-forced allocation, `_spawn_modifier_pulses` sends one pulse per leaf
modifier (`StatModifier.flatten_all`) from the node along the entity's owned subgraph
to the core (`_core_route`), `PULSE_STAGGER` (0.07 s) apart, each travelling at
`PULSE_PER_HOP` (0.13 s per graph hop, floor `PULSE_MIN_FLIGHT`). The modifier is
already on the board; the floater (`Events.stat_modifier_changed`) fires on arrival.
Forced allocations (spawn, procgen, scene-authored level setup) get the spike but no
pulses or floaters. Voluntary dealloc fires the floaters immediately; force-dealloc
and death never do, so the death-strip flurry is suppressed by construction.

### Blade-pop burst

`_on_blade_vertex_popped` spawns `_spawn_pop_burst`, a self-freeing one-shot
`CPUParticles2D` spray at the contact point in the defender's colour, radius
`POP_BASE_RADIUS + power * POP_RADIUS_PER_POWER` capped at `POP_MAX_RADIUS`. It is
the only effect that still uses particles.

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

Live as `const`s at the top of `allocation_vfx.gd` (shatter look as exports). Most
touched:

- `CASCADE_STEP` (0.35 s) — crackle (~50 ms) vs. domino (~200 ms) for chain kills.
- `SPIKE_NEEDLE_GAMMA` — needle vs. candle-flame for the alloc spike.
- `SPIKE_HEIGHT_FACTOR` — alloc spike height as a multiple of node radius.
- `LIFT_RISE_FACTOR` — how far the deallocation puff floats up.
- `PULSE_STAGGER`, `PULSE_PER_HOP` — modifier-pulse pacing.
- `shatter_*` exports — shatter intensity.

## Playground

The **Allocation VFX** live tab (`addons/sandbox_host/tabs/40_allocation_tab.tscn`,
embedding `addons/allocation_sandbox/allocation_sandbox_panel.tscn`) runs a
3×3 grid of self-resetting cells, each looping one allocation-flavoured scenario
against the **real** systems (so the modifier pulses and floaters fire for real, unlike
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
