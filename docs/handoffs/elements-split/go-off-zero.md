Child 4b of the #1716 elements split (design home `docs/design/elements.md` § Landing resolution; ADRs 0082 and 0083): today's explosive detonation is ported onto the gather that #{resolver} built, as go-off zero, a disc `GoOff`. Both spend ledgers and the per-wave `detonated` scope are deleted. When this unit ends, the game's blast must play exactly as it did before, except for the rule changes the owner decided (listed under Acceptance). #1733 and #1735 were closed into the split at filing, as completed with a pointing comment; this unit builds what those comments point at and closes neither.

Blocked by: #{resolver}
Blocks: #{burning}

## Acceptance spec

**Decisions** (owner, 2026-11-09 unless dated)
- Go-off zero: *"optoin 1. and for Charge / Shocked: an ArcEffect? or howzat? or shared base class between these?"*. The doc's statement of that pick: *"The resolver lands with detonation re-hosted on the go-off contract, proving it on the shipped tests and deleting both spend ledgers; the game keeps its blast until Burning inherits it."* The contract has a disc subclass, `DetonateEffect` and `BlastEffect` dissolve into the gather plus the disc, and no `ArcEffect` exists (`docs/design/elements.md:734-747`).
- `GoOff` sits on the `Element` def: *"i think it should sit on Element def, going off is just about their thing"*. Go-off zero's disc rides the Explosive `Aspect` def under the same field name until the Catalyst retag deletes it (pass pick, tentative) (`:739-747`).
- Per-hit once-per-node set and one snapshot per beat. The doc: *"The per-wave `detonated` scope goes."* (`:714-729`).
- One share: The doc: *"Today's stacks-only splash scale and the separate shrapnel fraction collapse into one knob per go-off, default 0.5"* (`:730-733`).
- A go-off copy carries its parent's crit (owner picked *it rides*; ADR 0082 §4). Spell shrapnel stops rolling its own (`:336-342`).
- Chains are flat, `damage × s` and riders `ceil(r × s)`, never `s^k`: *"LET IT RIDE"* (2026-11-05, #1735 fork 1). The doc: *"That is how it is built (#1735's finding)"* (`:489-496`); #1735 is already closed, and this unit writes the doc line (NOTES). A copy lands raw, so `stacks_per_hit` never multiplies with reach (#1733 R2, `:525-530`).
- Go-off zero keeps today's reach. The doc: *"Today's Explosive disc keeps its ×3 until the retag deletes it."* (`docs/design/elements.md` § The threshold model, "Size"). Its radius stays node radius × `reach_per_radius` (3.0) × √power, through `ExplosiveSpread.radius_for`. The new disc radius A × (√power + B) × node radius (ADR 0084 §2) does **not** apply here: it is Burning's, built by #{burning}, and the ×3 disc retires with the Explosive retag (#{catalyst}).
- What go-off zero reads, and when. ADR 0083 §1 has stage one land a hit's terrain riders (Heat, Cold, Charge only) and then read primed-ness and power from the result. Explosive charges are an aspect status, not a terrain rider, so no rider of the triggering hit ever joins go-off zero's power: at the gather's read step the disc reads the node's stored Explosive row as it stands when the hit lands (for hits of one beat, the pre-beat store; ADR 0083 §5) plus the hit's own carried load. That is today's read (`detonate_effect.gd:5`: a hit detonates before its own riders land), so riders-first changes nothing observable in this unit. The self-tipping hit of ADR 0083 §1 first shows at #{burning}.
- The disc picks its nodes by shape alone (ADR 0084 §7): every node inside the radius, the centre excluded, and the hit's own target mask then decides which of them a copy lands on. That is how today's blast already gathers (`splash_effect.gd`: the finder answers geometry, the mask answers who), so nothing changes: a node the mask excludes takes no copy and, as today, does not chain.
- A planting hit is a hit (pass ruling, 2026-11-10, `:484-487`). Today's `DetonateEffect.arm` PlantUse skip survives only as go-off zero's ported behaviour, and #{catalyst} deletes it.

**Knobs** (tentative, easy to change)
- The disc's `share` (on the `GoOff` base from #{resolver}) is authored as 0.5 on the Explosive aspect's disc. It replaces `PairedDamageEffect.fraction` (blast use), the splash `stack_scale *=` in the blast path (`splash_effect.gd:51`) and `BladePopResolver.LiveGate.shrapnel_fraction`. `warhead_reach` stays, since it is a radius and not a share.
- `ExplosiveSpread`'s `resonance`, `reach_per_radius` (3.0) and `charge_exponent` (0.5) are unchanged, so the disc stays 3 × √power × node radius. The A and B knobs of ADR 0084 §2 are not added or read here (#{burning} owns them). Tests assert the formula table and ratios, never the literals.

**Composition**
- **The disc** is a `GoOff` subclass (in `elements/`, beside the base). Go-off zero overrides spend and power with today's `spend_of` / `power_of` (`detonate_effect.gd:73-86`) and reach with `ExplosiveSpread.radius_for`. The gather calls it at its read step, after the hit's terrain riders have landed (#{resolver}; ADR 0083 §1); go-off zero's power source ignores those and reads the stored Explosive status row plus the hit's load: a spell's `DetonateUse` load (`LoadBag.detonate_load`), a blade piece's charges, and 0 for an arrow. A core with no charges reads and spends its owner's entity rows, as `_present` does today. The power source must be swappable: the disc takes its power through one overridable read (an exported source or a single override point), with today's charge formula as go-off zero's instance of it, because #{burning} reuses the same disc class with Heat's excess as power and no second disc class. Do not hard-code the charge formula into the subclass. The radius is swappable the same way: one overridable read, `radius_for` (×3) for go-off zero, which #{burning} replaces with the shared radius function of ADR 0084 §2.
- **`Aspect.go_off`** is an `@export` with the same field name as the band's, authored only on `aspects/defs/explosive.tres`. The gather reads it beside the element bands.
- **The record.** `BlastMark` stays the gather's output row, one mark and its copies (`attack_record.gd:211-217`, `_capture_blast` 700-713), and gains a generation index. `_announce_blast` is unchanged.
- **The blade** (written call): the node-side piece pass (`_piece_pass`, pop or shrug) stays in the sim gate. The board blast `arm_blasts` builds today (`blade_pop_resolver.gd:437-470`) becomes the gather at the contact's landing. The swing lands as it simulates, one sample's contacts per batch (`swing_resolve.gd:228-240` → `_land_batch` 442-529), and every gate read is live inside `land_on` → `LiveGate.admit`; the sim never runs ahead of the landings. Today a spend is still deferred: the gate records it, and `_flush_spends` (393, called at 529) lands it as a `CureInstance` only after the whole batch, so `_node_spent` (238, 391, 402-418) exists to cover two contacts of one sample on one node. With spends land-time (Acceptance 2b) that gap closes and `_node_spent`, `take_spends`, `_append_spends` and `_flush_spends` die: contacts of different samples read the world, which already carries the earlier spend; contacts of one sample on one node are hits of one beat and follow the resolver's rule — both read the pre-beat store, spends summed and clamped at 0 (Acceptance 2e; owner, 2026-11-10, picked one snapshot over sequential as today; `elements.md:724-729`; a behaviour change from today's sequential in-sample spend). If a gate decision still needs a spend not yet on the world across samples, stop and report: that is a design fork, not a workaround.
- **Dies:** `attack/spell/on_hit/detonate_effect.gd`, `attack/spell/on_hit/blast_effect.gd`, the `SPENT_KEY` ledger, `LiveGate._node_spent`, `LiveGate.take_spends` with its `_spends` list and `Spend` record, `SwingResolve._append_spends` and `_flush_spends` (and their calls at `swing_resolve.gd:331` and `:529`), `HitLanding.detonated` and its copy in `SplashEffect._retargeted`, and the per-wave scope (`spell_resolver.gd:297,336`). The `arm` call sites (`spell_resolver.gd:146`, `ranged_damage.gd:99`, `blade_pop_resolver.gd:454`) go too. `ExplosiveSpread.blast_for` dies or returns the disc. `PairedDamageEffect` survives only if a non-blast `.tres` still authors it (grep; none did at `bd800181`), otherwise it folds into the share.

**Files touched**
- `elements/` (the disc subclass), `aspects/aspect.gd`, `aspects/defs/explosive.tres`
- `attack/spell/spell_resolver.gd`, `attack/formulas/ranged_damage.gd`, `attack/melee/sim/blade_pop_resolver.gd`, `attack/melee/swing_resolve.gd`
- delete `detonate_effect.gd` and `blast_effect.gd`; edit `splash_effect.gd`, `paired_damage_effect.gd`, `attack/outcome/hit_landing.gd`, `effects/status/spread/explosive_spread.gd`, `attack/spell/load_use/detonate_use.gd` and `load_bag.gd` (names)
- `attack/outcome/attack_record.gd`, `attack/spell/on_hit/blast_mark.gd` (generation)
- `ui/vfx/blast_vfx.gd` (stagger), and the damage-number path if a copy shows none today
- `docs/domain/explosive.md` (Spend and power, Chains, the PlantUse skip now describe the disc go-off), `.claude/rules/explosive.md` (names `DetonateEffect.arm`), `docs/domain/attack-timeline.md`. #{catalyst} rewrites the explosive docs again at the retag.

**Acceptance**
1. Pins, which must stay green: the spend/power table (power is `power_of(load, present, resonance)` with `present` the stored charges before the hit), reach by power (the disc's radius equals `ExplosiveSpread.radius_for(node radius, power)` at every power of the table: a node at exactly that distance is reached and one just past it is not), the death burn, a heal blast heals under the landing mask, the PlantUse skip, the blade's two sides and verdicts, Firecracker's load-0 sparks. These live in `test_explosive_charges.gd`, `test_blade_explosive.gd`, `test_blast_mark.gd`, `test_heal_spell_blast.gd`, `test/unit/spell/test_firecracker.gd` and `test/unit/spell/test_cyclone.gd`.
2. Re-pointed **by design**, each as a red-first assertion of the new rule:
   - (a) Two arrivals of one wave on one charged node both go off, reading one pre-beat store. Their spends are summed and clamped at 0, where it used to be per-wave once-only.
   - (b) Spends are land-time; no compile-time `CureInstance` and no ledger read is left.
   - (c) A blast copy lands damage × share and riders ceil(r × share). A second link is flat, never share².
   - (d) Shrapnel copies the head's `crit_tier`. In `test_paired_damage_effect.gd`, it used to roll its own.
   - (e) Two blade contacts of one sample on one charged node both read the pre-beat charges; their spends are summed and clamped at 0. It used to be sequential through `_node_spent`.

   The drone lists every re-pointed assertion in its report. `test_blast_effect.gd` is retired or re-pointed with its class.
3. A volley on a 5-charge node fires 5, 4, 3, 2, 1 with no ledger: the arrows land and spend on the world in turn.
4. `test_outcome_fixture_replay.gd` and the `world_fingerprint` replays stay green. A fixture whose crit sequence moved is re-recorded and named in the report.
5. Visual, live replay: a cascade's discs fire staggered by generation, so a chained node's disc fires visibly after its parent's.
6. Visual: the blast draws from the record's mark (`Events.blast_landed`). An observer replay shows the same discs as the host.
7. Visual: every copy shows its own damage number at its node.
8. `mise run check`, the full suite once, and `mise run mp:e2e`, all green.

**NOTES**
- A no-parent go-off ("terrain hit") has no caller, so no unit builds it (pass ruling, 2026-11-10; `elements.md:498-503`).
- #1733 and #1735 are already closed (at filing, as completed, each with a comment pointing here; `close-1733.md`, `close-1735.md`). This unit owes #1735's doc line: `docs/domain/explosive.md` says that a chained blast carries the root payload flat. No commit or PR of this unit carries a closing keyword for either.
- ADR 0082's Context says spell shrapnel draws no crit, but it rolls its own (`hit_instance.gd:323-324`). The correction stays with #{adr-fixes}; write no ADR here.
- `vertex_charges`, `BladeVertexFill`'s charge copy and the barrel on a blade stay as they are; #{catalyst-blade} removes them.
- The look may be handed to a sub-agent working in this same worktree once the hook it draws from (signal, record field, scene stub) exists; the unit's drone stays the owner and reviewer of the result.
- The stamp was cut at `bd800181`, before #{resolver} landed. The dispatching lead re-checks `mise run issue-drift`; if it still flags, stop and say so.

**Stubs on master** — none — shapes are named in Composition; the drone adds them.

```drift-stamp efba0bc3
docs/design/elements.md:336-342 — a go-off copy carries its parent's crit; shrapnel stops rolling its own
docs/design/elements.md:484-530 — planting, chains flat, no-parent go-off, a copy lands raw
docs/design/elements.md:714-747 — per-hit set, one share, go-off zero
docs/domain/explosive.md:66-118 — spend, power, chains as built
attack/spell/on_hit/detonate_effect.gd:41-122 — arm, spend_of, power_of, apply: what is ported
attack/spell/on_hit/detonate_effect.gd:130-185 — _present, the ledger, _spend
attack/melee/sim/blade_pop_resolver.gd:225-245 — warhead_reach, shrapnel_fraction, _node_spent
attack/melee/sim/blade_pop_resolver.gd:363-470 — _piece_pass, node_charges, take_spends, arm_blasts
attack/spell/spell_resolver.gd:294-298 — the per-wave detonated scope
attack/spell/spell_resolver.gd:140-150 — DetonateEffect.arm on the spell's riders
attack/formulas/ranged_damage.gd:90-105 — the arrow's arm call
attack/spell/on_hit/splash_effect.gd:40-56 — stack_scale compounding in the blast
attack/outcome/attack_record.gd:205-220 — the blast table arrays
attack/outcome/attack_record.gd:695-713 — _capture_blast
attack/outcome/hit_landing.gd:80-86 — detonated, the scope that dies
attack/spell/on_hit/blast_effect.gd — seam: dissolves into the disc
attack/spell/on_hit/blast_mark.gd — seam: generation index
attack/spell/on_hit/paired_damage_effect.gd — seam: fraction (19) folds into share
effects/status/spread/explosive_spread.gd — seam: blast_for / radius_for
attack/melee/swing_resolve.gd — seam: arm_blasts caller, per-batch spends
attack/spell/load_use/detonate_use.gd — seam: names DetonateEffect
attack/spell/load_use/load_bag.gd — seam: detonate_load
aspects/aspect.gd — seam: go_off field
aspects/defs/explosive.tres — seam: authors the disc
ui/vfx/blast_vfx.gd — seam: blast_landed listener, stagger
.claude/rules/explosive.md — seam: names DetonateEffect.arm
docs/domain/attack-timeline.md — seam: blast prose
test/unit/attack/test_explosive_charges.gd — seam: pins + re-points
test/unit/attack/test_blade_explosive.gd — seam: pins + re-points
test/unit/attack/test_blast_effect.gd — seam: retire or re-point
test/unit/attack/test_blast_mark.gd — seam: pins
test/unit/attack/test_paired_damage_effect.gd — seam: shrapnel crit re-point
test/unit/spell/test_heal_spell_blast.gd — seam: pins
test/unit/spell/test_cyclone.gd — seam: names detonated
test/unit/spell/test_firecracker.gd — seam: load-0 sparks
test/unit/attack/test_outcome_fixture_replay.gd — seam: recorded crits
```
