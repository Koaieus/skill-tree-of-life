# Handoff — TODO sweep of the 2026-08-07 WIP commit

Sweep of the TODOs left in `c996185` ("wip: many TODOs, add healing spell,
partial healing impl, card refactor, etc") plus the surrounding ~2 weeks.
Everything below is either shipped, filed, or explicitly deferred with a reason.
**Delete this file once the two open issues are picked up.**

## State of master

Clean tree. Suite went **23 failing → 14** across the session (1322 tests). The
14 are all pre-existing families from the WIP commit: tooltip-fan / id-chip,
core-class WIS placeholder (#268), inner-disk uniform, tooltip-cutover, and
`test/unit/ui/test_tmp_debug_fan.gd`.

The 9 recovered were "Unexpected Errors" failures caused by `%Title` failing to
resolve on the Magic and Defense cards — fixed structurally by `a21cac0`.

## Open — needs a decision or a body

- **#381** (`Ready`, M) — collapse `AttackOutcome.hits`/`heals` and
  `PropagationEvent.damage`/`heal` into `Array[HitInstance]`; a *system* applies
  outcomes rather than the instance applying itself; crit facts move onto the
  instance. Full design research and rationale are in the issue body — read it
  rather than re-deriving. Blocks any further work on
  `magic_bounce_coordinator.gd`.
- **#382** (`Needs design`, P1) — the magic channel's `spell_dpa` regenerates 5x
  below the committed `tools/balance/snapshot.md`, and no invariant catches it
  because `spell_dpa_over_melee_dpa` is still `TBD`. **Not attributed** — the
  issue has the one-command check to settle whether it predates this session.
  `snapshot.md` was deliberately left reverted, not committed.

## Shipped

| Commit | TODO closed |
|---|---|
| `2f328b4` | `HealingEffect` appended a `HealingInstance` to `Array[DamageInstance]` — runtime type error on every heal cast. Routed to `heals`; resolver now stamps `PropagationEvent.heal`. |
| `6c2396c` | Defense/Melee cards overrode public `bind()` instead of the `_bind()` hook; `bind(board, entity)` → `bind(entity)`. |
| `3f612fb` | `NodeTargeting` docstring was copy-pasted from `SingleAlliedNodeTargeting`. Ownership logic verified sound (`&` binds tighter than `==` in GDScript — checked in-engine). |
| `8c1854d` | Same file: ownership filter is **orthogonal** to the effect's sign. `healing_beam.tres` is `Any` on purpose. |
| `ac7141b` | `spell_damage × power` had **three** drifting copies → `SpellResolver.seed_damage(spell, source, board)`. |
| `f48b3b1` | Healing end-to-end: `healing_beam.tres`'s `on_hit_effects` held a single `null`; headless path ignored `heals`; coordinator's `elif` dropped a heal on any landing that also damaged. |
| `769a962` | Radar axis colours from `StatDef.tint_color` via `AxisSpec.for_stat`. Both panels had drifted copies of the derive dance. |
| `aafb76b` | `StatDef.abbrev` authored, not `substr(0, 3)`. |
| `fc81b37` | `Entity.get_spellbook()` — every entity has a book, empty if it knows nothing. |
| `a21cac0` | Magic + Defense as inherited scenes of `combat_card.tscn`; Ranged got its missing title. |
| `08f0c5b` | `SpellRangeRules` owns the `spell_range` rule; folded in `SpellTooltip`'s divergent board-vs-node-local copy. |

## Deliberately deferred, with reasons

- **`skill_node/visuals/inner_disk.gdshader:16,18,19`** ("might be a real
  uniform") — verified: the values come from a shared `LightingStyle` and never
  vary per node. But `inner_disk.gd:330-333` actively pushes them via
  `set_instance_shader_parameter`, and `inner_disk.tscn` authors
  `instance_shader_parameters/*` overrides that a plain `uniform` would orphan.
  Three inner-disk tests are already red. Real but low-value; not worth the
  attribution noise.
- **`test/unit/ui/test_tmp_debug_fan.gd`** — in the failing set. It is a live
  repro of the fan arrival-axes warning, not spent scratch. Left in place.
- **`ui/tooltip_fan/fan_live_sandbox.gd`** (8 TODOs) — #309 follow-through in a
  file under active edit; high collision risk.
- **`ui/vfx/coordinator/magic_bounce_coordinator.gd:85,88`** (decompose
  `waves`/`beats`/`pending`) — wait for #381, which rewrites part of that file.
- **`effects/effect_context.gd:12`** ("carefully review all these splits") — a
  review marker, not a task; needs the author.
- **`archetypes/archetype.gd:18`** (#246), **`skill_node/skill_node.gd:45`**
  (#336), **`rim_ring.gdshader:248`** (#371) — issue-bound.
- **`addons/spell_playground/playground_panel.gd:186`** — pre-authored-scene
  rant; no action implied.

## Naming thread left open

`seed_damage` reads as propagation vocabulary ("the seed of a wave") when at the
primary target it is the *impact*. Lobbing a pyroblast and calling the primary
hit "the seed" undersells it. Two concepts are conflated in one name: the number
the primary target takes, and the number hops scale from.

Not renamed — the term reaches `CastSpell.damage`, `HopDamageProgression`,
`ExpressionProgression`'s documented `seed_damage` formula input,
`TrailBlazerStep`, and **design doc D-32**, so it is a docs change as much as a
code one. Worth doing as its own pass; `impact_damage` for the value the primary
hit lands, leaving "seed" only where the prose genuinely means "where the wave
starts", is the shape I'd suggest.
