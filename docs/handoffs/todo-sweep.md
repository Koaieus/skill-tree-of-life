# Handoff — TODO sweep of the 2026-08-07 WIP commit

Second pass, 2026-08-07 evening: folded in the TODOs added during playtesting.
**Everything below now points at an issue. Delete this file once #381 is picked
up** — nothing else here is load-bearing.

## Open — needs a decision or a body

- **#381** (`Ready`, M) — collapse `AttackOutcome.hits`/`heals` and
  `PropagationEvent.damage`/`heal` into `Array[HitInstance]`; a *system* applies
  outcomes rather than the instance applying itself. Full design research is in
  the issue body — read it rather than re-deriving. Blocks further work on
  `magic_bounce_coordinator.gd`. **Untouched by both passes.**

## Closed — #382 (magic-channel `spell_dpa` drift)

**Closed by the user 2026-08-07, unfixed and deliberately.** One measurement
landed on it first: c996185 regenerates the committed 40/20/40/10, so the drift
is *forward* of the WIP commit rather than predating it. The issue comment goes
on to name `ac7141b` as the sole remaining suspect — **treat that as unproven.**
It leans on the body's four-commit list, but the c996185..47ebc5e window holds
25 commits, and "the seed alone, unmultiplied" is the signature of lost *hop*
contributions rather than of the seeding consolidation `ac7141b` performed. A
bisect was started and abandoned when the issue was closed.

`tools/balance/snapshot.md` stays **reverted, not committed** — the suite
regenerates it on every run, so check `git status` before committing anything
near it.

## Filed this pass

| Issue | What |
|---|---|
| **#396** | `seed_damage` → `impact_damage` naming split. This was the "naming thread left open" section of the previous handoff; it now has a durable home, which is why that section is gone. |
| **#397** | TrailBlazer design forks sketched in the WIP docstring but never implemented: unbounded trail walk, degree-1 tip behaviour, slam AoE. |
| **#377** (2 comments) | The four `SkillNode` clone ledgers, and the **StatModifier statelessness** question — raised in three separate sessions, answered nowhere. `StatFormula` is stateless by design; `StatModifier` is stateful by implementation and that is the defect #377 exists to fix. Its stated unpark trigger (one granted modifier recalculating on every holding entity's board) has now been reached, so what's left is a *scheduling* call. |
| **#326** (comment) | Acceptance 4 amended: debuff pools ladder their refund (`-TierLadder.cost(t)`), they are not single-tier. |

## Landed this pass

| Commit | What |
|---|---|
| `4fc31f9` | `get_entity_degree` stays a loop. Both proposed "fixes" regress it — the self-loop +2 already falls out of `Graph._adjacency`, and `entity.navigator` returns -1 for the unowned-node reading the accessor must serve. `docs/domain/degree.md` gained the section that would have prevented both. |
| `66e60e8` | TrailBlazer walks **entity** degree (it always should have). The step-level tests missed it by leaving nodes unowned; the end-to-end ones by giving one entity the whole string. Added `test_foreign_neighbour_is_not_a_junction`, verified to be the only test that discriminates. |
| `134cb07` | CON + mobility playtest retune. |
| `c3ef1f5`, `9f8...` | Both procgen tests stopped pinning tuning magnitudes and now assert shape/invariants. |
| InnerDisk | `tint_mix` 0.6 → 1.0, killing a white wash found by scrubbing the slider. `allocated = true` was eyeballing state and was not kept. |

## Suite state

**15 failing of 1323.** 14 are the pre-existing families (tooltip-fan /
id-chip ×10, core-class WIS placeholder #268 ×2, inner-disk uniform ×2). The
15th is `test_first_level_preset` — caused by an *uncommitted* `count = 10 → 5`
in `procgen/presets/first_level/first_level.tres` belonging to another agent's
live session, not by anything in this pass.

## Still deliberately deferred

- **`inner_disk.gdshader:16,18,19`** ("might be a real uniform") — verified: the
  values never vary per node, but `inner_disk.gd:330-333` pushes them via
  `set_instance_shader_parameter` and the scene authors
  `instance_shader_parameters/*` overrides a plain `uniform` would orphan. Real
  but low-value.
- **`test/unit/ui/test_tmp_debug_fan.gd`** — a live repro of the fan
  arrival-axes warning, not spent scratch. Left in place.
- **`ui/tooltip_fan/fan_live_sandbox.gd`** (8 TODOs) — #309 follow-through in a
  file under active edit; high collision risk.
- **`ui/vfx/coordinator/magic_bounce_coordinator.gd:85,88`** — wait for #381.
- **`effects/effect_context.gd:12`** — a review marker, not a task; needs the author.
- **`archetypes/archetype.gd:18`** (#246), **`skill_node/skill_node.gd:45`**
  (#336), **`rim_ring.gdshader:248`** (#371) — issue-bound.
