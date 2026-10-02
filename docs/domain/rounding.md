# Rounding

Every place the game turns a fractional number into a whole one, in one table:
the quantity, its unit, which way it rounds, the one site that does it, and the
decision behind it. Hub: #1217. A new rounding site gets a row here before it
gets code; a rounding call outside the listed site is a bug.

The general lean (owner, 2026-09-30): *"the whole pipeline should yield
integers at each right moment a value is produced"* — round once, where the
number is made, in the direction the decision names; never a carry, never a
second rounding downstream.

| Quantity | Unit | Direction | Site | Source |
|---|---|---|---|---|
| Damage magnitude (any type: mitigated, TRUE, DoT tick, replay, core overflow, dealloc chip) | HP, int | **up** (`⌈\|x\|⌉`, sign kept); exactly 0 stays 0; float noise on a whole counts as the whole | `HitPoints.whole`, at entry to `NodeCombat.take_damage` / `EntityCombat.take_pool_damage`, **before** `Mitigation` | ADR 0033, #1307 |
| PERCENT_CURRENT damage chunk (`amount × current_hp`) | HP, int | **up**, then clamped to `current − 1` — never itself lethal, a 1 hp node takes 0; pre-crit | `HitInstance.resolve_amount` | ADR 0033, #1307 (owner, 2026-10-02) |
| Mitigated damage `max(min_damage_taken, raw − armor)` (a negative result is a heal) | HP, int | none — int-on-int (`armor`, `min_damage_taken` are INT) | `Mitigation.compute` | ADR 0017, ADR 0033 |
| Heal magnitude (after `healing_received`) | HP, int | **up** | `HitPoints.whole`, in `NodeCombat.heal_damage` / `EntityCombat.heal`, after the `healing_received` multiply | ADR 0033, #1307 |
| DoT tick, projected (`DotTick.tick_damage`, the #953 overlay) | HP, int | **up**, per tick — equals what lands | `DotTick.tick_damage` → `HitPoints.whole` | ADR 0033, #1307 |
| AI kill estimate (`AiCombatScorer.cheap_estimate`) | HP, int | mirrors the door: `⌈raw⌉`, then `Mitigation.compute` | `HitPoints.whole` + `Mitigation.compute` | #1307 |
| INT stat merged read | stat unit | down (truncate), once at the read | `Stat._coerce` | ADR 0017 |
| Spill on death, per neighbour | stacks, int | down: `⌊⌊S · f⌋ / k⌋`, remainder lost (no total increase) | `SpillSpread` | #1204, #1217 (owner, 2026-09-29/30) |
| Diffusion, FRACTION mode, per edge | stacks, int | down: `⌊f · d / (1 + max(deg_u, deg_v))⌋` (floored Metropolis) | `FractionDiffusion` | #1264 |
| Resistance cancel | stacks, int | half-down: `⌈row × res − ½⌉` cancelled (ties to the attacker) | `StatusHost.effective_power` | ADR 0031 |
| Landing fold `(authored + extras) × (1 + Σinc) × Πmore` | stacks, int | **half-up**, ties to the attacker (noise within `is_equal_approx` of a whole or a half snaps to it first); the `*_stacks_per_hit` stats stay FLOAT so the read never truncates first | `StatusDef.stacks_per_hit` (`round_half_up`), also on the null-board path | ADR 0032, #1310 (owner, 2026-10-01) |
| FRACTION decay | stacks, int | **down**, floor kept: `⌊S · (1 − f)⌋`, always reaches 0 | `FractionDecay.decayed` | ADR 0032, #1310 (owner, 2026-10-01) |
| Status row store | stacks, int | none — whole in, whole stored; a fraction reaching it is a minting site's bug (debug `assert`) | `StatusHost._settle`, `StatusHost.tick_statuses` | ADR 0032, #1310 |

## Consequences worth knowing

- **Any positive hit lands at least 1 before mitigation.** A corruption burst of
  0.4 on a 10 HP leaf lands 1 (this reverses #1157's "floors to 0 on small
  nodes"). A 0.01 hit against `armor 1`, `min_damage_taken −5` is
  `max(−5, 1 − 1) = 0` — it neither hits nor heals.
- **A 0 hit is not rounded.** The scout arrow (`damage_scale 0.0`) stays 0 and
  `Mitigation.compute`'s `amount <= 0 → 0` gate keeps it off the floor.
- **Replay is free.** The door's rounding is idempotent on wholes, so a
  recorded `DamageInstance.amount` (already whole) replays to the same number.
- **Poison loses 1 stack a tick, corruption none.** Poison and curse ship
  `FlatDecay 1` (integer-native, no rounding), corruption no decay slot, wither
  `FractionDecay 0.25` (8 → 6 → 4 → 3 → 2 → 1 → 0). Interim knobs until #1203.
- **Scouted rides `FractionDecay` on a float mark.** Floor-kept, a 120-unit
  disc steps toward 0 faster than the old halving; integer scouting is its own
  design.
- **Floating-point noise.** `0.1 * 30` is `3.0000000000000004`; a bare `ceil`
  would land 4. `HitPoints.whole` snaps a magnitude within `is_equal_approx` of
  a whole to that whole before rounding up.
