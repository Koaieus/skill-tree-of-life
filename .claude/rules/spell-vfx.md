---
description: Spell VFX explanation
paths:
  - "attack/spell/defs/**"
  - "ui/vfx/**"
---

# Spell VFX

The catalogue, coordinators, clocks and the visual contract live in
[docs/domain/spell-vfx-kit.md](../../docs/domain/spell-vfx-kit.md); the verb
vocabulary is [docs/domain/spell-propagation.md](../../docs/domain/spell-propagation.md).
The gotchas:

- **Never gate a wave on a projectile finishing.** `MagicBounceCoordinator` runs a
  fixed cadence clock (beat N at `N * beat_interval`); visuals render into a window
  and may not hold up the next wave.
  **Why:** a slow fork would stall the whole propagation.
  **How to apply:** assert on `wave_started`, never on projectile-finished timing;
  no `await previous-projectile-finished` between waves.
- **Seconds are presentation; ORDER is structure.** Landing order and `CritRoll`'s
  stream key off `HitInstance.schedule_index`, never `arrival_time` (tempo-dependent,
  per-peer). **Why:** sorting on the float is a desync with a green suite.
  **How to apply:** retune timing in the `PresentationTempo` `.tres`, never in code
  or a coordinator export.
- **Batch of ~60: never a per-instance `ShaderMaterial` or animated per-instance
  uniform** (it breaks the draw batch); per-instance variation goes in `modulate`,
  transform, UV or `INSTANCE_CUSTOM`.
- **`EdgeEnergize` paints on top of an edge** — it never touches `Edge`, `Graph` or
  the edge MultiMesh.
- **Guard the coordinator on `timeline.is_empty()`, not `hits.is_empty()`.**
  **Why:** a pure-utility spell (`power` 0) has events and no hits, and must still
  render its path.
