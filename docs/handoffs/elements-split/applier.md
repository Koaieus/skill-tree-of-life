Child 3 of the #1716 elements split (design home `docs/design/elements.md`): a pure refactor of the outcome applier so the two-stage resolver has somewhere to put the hits a landing produces. `OutcomeApplier` drains an open worklist; one stamping callable replaces the two post-compile stamp loops; the landing-to-hit stampers fold into one. No behaviour changes: every existing test stays green unedited except where re-pointing is named below.

Blocked by: none
Blocks: #{resolver}

## Acceptance spec

**Decisions** (owner, 2026-11-09)
- The applier drains an open worklist (owner picked it over the head landing its own copies). The settled doc text: *"Landing a gather head appends its entries' hits to the applier's queue, compiled through one stamping callable the landing site hands in (replacing the spell and ranged post-compile stamps); the three status, detonate and paired-damage stampers fold into one."* (`docs/design/elements.md:748-752`)
- *"Applier refactor — `OutcomeApplier` drains an open worklist, one stamping callable replaces the spell and ranged post-compile stamps, the three landing-to-hit stampers fold into one; no behaviour change."* (`docs/handoffs/elements.md:413-415`) — reviewed, taken as settled.
- Land order is keyed on `(schedule_index, original index)`, never on `arrival_time` (#543 D2, `attack/outcome/outcome_applier.gd:143-169`) — existing law, kept.

**Knobs** — none. A refactor with no numbers.

**Composition**
- **The worklist** (pass pick, tentative — names are proposals): a small `RefCounted` queue in `attack/outcome/` that holds the unlanded hits in `(schedule_index, insertion order)` order and a cursor. `push(hit)` slots a hit into the *unlanded tail* by that key, never ahead of the cursor, and also appends it to the outcome's `hits` so the record holds every hit that landed. `OutcomeApplier.apply` builds one from `in_arrival_order(outcome.hits)` and drains it with the clock (await per hit, `flush_removals` on each `schedule_index` change, `_announce_blast`, all as today). The crit stream is drawn in land order (`land_one` → `CritRoll.decide`), so the order the queue yields is a determinism fact, not a style.
- **One drain, two callers.** The spell wave lands mid-walk through a fixed index range (`attack/spell/spell_resolver.gd:373-374`) and must not await (`outcome_applier.gd:71-73`). It drains the same queue type instantly over the wave's hits (`BeatClock.instant_clock` or an un-awaited drain — the drone picks), so wave landing and `apply` share one implementation. The exert landing (`spell_resolver.gd:62`) stays a single `land_one`.
- **`land_one` gains an optional queue argument** (default null = standalone, nothing can be appended — every existing caller is unchanged). Nothing pushes mid-drain in this unit; #{resolver}'s gather is the first pusher.
- **The stamping callable.** `HitLanding` gains one `Callable(hit: HitInstance) -> void` field the landing site sets; `place()` (or the builder right after it, the drone picks) runs it over the span exactly where today's loops run. Its two bodies are today's loops moved verbatim: the spell's (`spell_resolver.gd:347-359`: `attacker = ctx.caster`, `_stamp_crit_conditions`, `structural_key`, `ev.hits.append`) and the ranged ammo-id stamp (`attack/formulas/ranged_damage.gd:103-105`, skipping the arrow itself). `swing_resolve.gd:524-526` only appends sub-outcome hits and is not a stamp — untouched. Both loops die.
- **The landing-to-hit fold.** One method on `HitLanding` copies the eight shared facts (`attacker`, `source`, `origin`, `read_node`, `target`, `structural_key`, `paired`, `hit_key`) onto any `HitInstance`. Its callers: `StatusInstance.stamp_landing` (`attack/outcome/status_instance.gd:76-85`; keeps `def` and becomes a thin wrapper or dies — drone's call), `DetonateEffect._spend` (`attack/spell/on_hit/detonate_effect.gd:166-177`) and `PairedDamageEffect` (`attack/spell/on_hit/paired_damage_effect.gd:43-51`). Written calls on the two the handoff missed: `HaulEffect._cure_on` (`attack/spell/on_hit/haul_effect.gd:47-54`) sets a different target, origin and source, so it is **not** folded; `SplashEffect._retargeted` (`attack/spell/on_hit/splash_effect.gd:130-146`) is landing→landing, not a stamper, so it is not folded but copies the new callable field like every other field.
- **Dies:** the two post-compile loops; the duplicated eight-field blocks in `_spend` and `PairedDamageEffect.apply`.

**Files touched**
- `attack/outcome/outcome_applier.gd` — `apply` drains the queue; `land_one` takes the optional queue.
- `attack/outcome/` new queue class (one file).
- `attack/outcome/hit_landing.gd` — the callable field, the fold method, `place()` invoking the callable.
- `attack/spell/spell_resolver.gd` — the wave drain; the stamp loop becomes the callable.
- `attack/formulas/ranged_damage.gd` — the ammo-id loop becomes the callable.
- `attack/outcome/status_instance.gd`, `attack/spell/on_hit/detonate_effect.gd`, `attack/spell/on_hit/paired_damage_effect.gd`, `attack/spell/on_hit/splash_effect.gd` — the fold. (#{resolver} later dissolves `detonate_effect.gd`; this unit only edits its stamper.)
- `docs/domain/attack-timeline.md` — "OutcomeApplier.apply: the parameters" (539-566) and "Ordering and `arrival_time`" (417-422) say the loop drains a worklist and where an appended hit lands in the order.

**Acceptance**
1. New `test/unit/attack/test_outcome_applier_worklist.gd`, red first: a test-local `HitInstance` subclass whose `land_on` pushes another hit onto the queue it was handed. Asserts that the pushed hit lands after its pusher and before the next scheduled hit with a greater `schedule_index`, never before the cursor; that it ends up in `outcome.hits`; and that the crit stream draws in exactly that land order (seeded stream, compare `crit_tier` sequence to a hand-ordered expectation).
2. Same file: a spell-style instant drain and `apply` with `BeatClock.instant_clock` produce the same land order on the same hits.
3. Characterization pins, kept green **unedited** (they are the proof of "no behaviour change"): every file in the drift stamp's `OutcomeApplier.apply(` and `land_one(` seam lists, especially `test_outcome_applier_beat_clock.gd`, `test/integration/attack/test_outcome_applier_real_clock.gd`, `test_ranged_volley_arrival_order.gd`, `test_rider_order.gd`, `test_application_discovers_nothing.gd`, `test/unit/test_greed_landing.gd` (`hit_key` sharing), `test_paired_damage_effect.gd`, `test_explosive_charges.gd`, `test_outcome_fixture_replay.gd` (recorded fingerprints must not move).
4. `test/unit/spell/test_status_instance_stamp_landing.gd` may be re-pointed at the folded method; its assertions (every shared field copied, `def` set) survive.
5. `mise run check` clean; full suite once at the end, green.

**NOTES**
- Nothing pushes mid-drain until #{resolver}; do not add a gather, a share or a copy here.
- `HaulEffect` and `SplashEffect._retargeted` stay unfolded by written call above; a later unit may revisit.
- No visual in this unit.

**Stubs on master** — none — shapes are named in Composition; the drone adds them.

```drift-stamp efba0bc3
attack/outcome/outcome_applier.gd:18-43 — apply: sort, group flush, await beat, land_one, announce
attack/outcome/outcome_applier.gd:60-141 — land_one: the per-hit landing; the crit draw is a landing fact
attack/outcome/outcome_applier.gd:143-181 — in_arrival_order and why the key is structural (#543 D2)
attack/spell/spell_resolver.gd:335-378 — the per-wave walk: stamp loop 347-359, wave landing 373-374
attack/spell/spell_resolver.gd:50-62 — the exert landing, a lone land_one outside the walk
attack/formulas/ranged_damage.gd:90-105 — ranged ride and its ammo-id stamp loop
attack/outcome/hit_landing.gd:90-156 — riding(), emit(), place() bucket order
attack/outcome/status_instance.gd:76-85 — stamp_landing, the status stamper
attack/spell/on_hit/detonate_effect.gd:166-177 — _spend, the cure stamper
attack/spell/on_hit/paired_damage_effect.gd:43-51 — the shrapnel stamper
attack/spell/on_hit/splash_effect.gd:128-146 — _retargeted, landing→landing (not folded)
attack/outcome/crit_roll.gd:53-59 — decide: why land order is crit-stream order
docs/domain/attack-timeline.md:417-422 — the ordering rule
docs/domain/attack-timeline.md:539-566 — apply() parameters
docs/design/elements.md:748-752 — the owner's worklist call
attack/melee/swing_resolve.gd — seam: four OutcomeApplier.apply callers (148, 401, 428, 521); 524-526 append-only
attack/plan/ranged_attack_plan.gd — seam: ranged OutcomeApplier.apply caller (519)
systems/battle_system.gd — seam: battle caller, awaits apply (740)
attack/spell/on_hit/haul_effect.gd — seam: partial landing→hit copy, not folded (written call)
attack/spell/on_hit/apply_status_effect.gd — seam: stamp_landing caller (35)
attack/spell/on_hit/flux_effect.gd — seam: stamp_landing caller (33)
attack/spell/on_hit/multiply_row_effect.gd — seam: stamp_landing caller (27)
test/unit/spell/test_status_instance_stamp_landing.gd — seam: may be re-pointed at the fold
test/unit/attack/test_outcome_applier_beat_clock.gd — seam: pin
test/integration/attack/test_outcome_applier_real_clock.gd — seam: pin
test/unit/attack/test_ranged_volley_arrival_order.gd — seam: pin
test/unit/attack/test_rider_order.gd — seam: pin
test/unit/test_greed_landing.gd — seam: pin (hit_key)
test/unit/attack/test_cure_instance.gd — seam: land_one caller, pin
test/unit/attack/test_hit_basis.gd — seam: land_one caller, pin
test/unit/attack/test_status_instance.gd — seam: land_one caller, pin
test/unit/effects/test_mark_status.gd — seam: land_one caller, pin
test/unit/spell/test_scale_stacks_effect.gd — seam: land_one caller, pin
test/unit/spell/test_stack_fold.gd — seam: land_one caller, pin
test/unit/attack/test_heal_cures_debuffs.gd — seam: land_one caller, pin
```
