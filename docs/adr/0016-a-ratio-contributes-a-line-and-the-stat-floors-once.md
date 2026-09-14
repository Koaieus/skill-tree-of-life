---
id: 0016
title: A ratio intrinsic contributes a line, not a stair; an INT stat floors its finished total once
status: proposed
date: 2026-09-14
deciders: owner
supersedes: []
superseded-by: null
sources:
  - "#889"
  - "#775"
  - "#776"
  - "#792"
  - "#271"
  - "stats_system/formulas/ratio_formula.gd"
  - "stats_system/stat.gd"
  - "stats_system/modifier_bins.gd"
tags: [stats, balance, loot, formulas, design]
---

# ADR 0016 — A ratio intrinsic contributes a line, not a stair; an INT stat floors its finished total once

> **Preliminary.** The owner made the call on 2026-09-14 in the #889 swarmify
> pass; it becomes `accepted` when the two child issues land and the
> characterisation pass over the INT ratio targets confirms the consequences
> below. Until then, argue on #889, not here.

## Context

`RatioFormula` (`stats_system/formulas/ratio_formula.gd`) is the shape of nearly
every intrinsic — `+1 XP/turn per 5 WIS`, `+1 blade damage per 20 STR`. It
computed `floor(source / divisor)`, and the modifier multiplied that stair by its
`value` coefficient. Two later decisions turned that stair into a problem:

1. **#775 merges looted copies of a rule into the looter's own by adding
   coefficients** — a tier-1 blocker's copy is `0.25`, so the merged rule reads
   `1.25 × floor(WIS / 5)`. Under the stair a fractional coefficient is invisible
   until enough copies stack ("you need X× the divisor to see a difference" —
   owner), and the tooltip reads `+1.25 XP/turn per 5 WIS`, which nobody can
   convert into "when do I get the next one".
2. **Procgen already puts `% increased` on ratio targets** (`xp_per_turn`,
   `node_health`, `spell_range` — `procgen/pools/*.tres`). The stair is applied
   *before* the bins, so a player with 200% increased blade size gains **+3 in a
   burst every 20 STR**, and the burst grows with every multiplier they find.

The owner's framing of what a divisor is for (2026-09-14): *"divisors are kinda
shitty. Big divisor = big dead space […]; small divisor = no wiggle room for
changing them (/5 → /4 sure, but then /3 /2 /1 → hit a wall."* And of what the
stair is actually worth as legibility: past small stat values, nobody computes
`12345 mod 20` — what a player reads off `+1 per 20 STR` is the **rate**.

Meanwhile `Stat._coerce` (`stats_system/stat.gd:571`) rounded an INT stat's
finished total to nearest (`roundi`), and `ModifierBins._fold` has no
intermediate rounding: `(base + add) × (1 + inc%) × mult + bon`, coerced once.

## Decision

1. **A `RatioFormula` contributes `source / divisor` — a line.** No floor inside
   the formula. The modifier's `value` multiplies it as before, so loot mass
   accumulates in `value` exactly as #775 built it; the merge key, the wire form
   and the tier ladder are untouched. The divisor stays the **authored** knob —
   `RatioFormula` remains the human representation and is not folded into
   `LinearFormula`.
2. **An INT-typed scalar stat floors its finished total** — `_coerce` truncates
   toward zero instead of rounding to nearest. This is the only floor in the
   pipeline, and it is the stat's, not any modifier's. Pools are untouched
   (they round their own `current`).
3. **A ratio rule displays as `+1 <stat> per <divisor / value> <SRC>`** —
   normalised to a unit numerator, so a merged rule reads `+1 XP/turn per 3.75
   WIS`; when the step would drop below one point of source it flips to
   `+<value / divisor> <stat> per <SRC>` (`+20 mana per INT`, never `+1 per 0.05
   INT`). The displayed step is what the line divides by, so
   `RatioFormula`'s invariant — the number shown is the number computed —
   survives the change.

Owner, 2026-09-14: *"roundi is good as final touch. but the steps should floor
i think. if `+1 per 3.75` we don't give +1 unless at least 3.75 is attained,
not at ~half of 3.75"* — and, on the bins: *"with these %inc and mults
existing, i think the smooth stairs is what we want. +1 +1 +1 better than +3 in
one go."* Decision 1 + decision 2 is the only combination that satisfies both
sentences at once (see the table under *Alternatives*).

## Consequences

- **Unlooted, un-multiplied baseline is unchanged.** `floor(1 × s / d)` and
  `floor(s / d)` are the same number; #271's "WIS 21 still reads what WIS 20
  reads" still holds for a lone rule.
- **Multiplied stairs become ramps.** 200% increased blade size now yields
  +1 every ~6.67 STR instead of +3 every 20 — same slope, and at the old step
  you hold exactly what the stair promised, never more. This is the intended
  change, not a side effect.
- **Dead space shrinks as you loot** — the step is `divisor / value`, so
  looting the rule also smooths it, and there is no `/1` wall: slope can pass
  one per point (`+20 per INT`) without special handling.
- **A fractional coefficient is still invisible on its own** until the total
  crosses the next integer — the INT cliff accepted on #775 (2026-09-13). It is
  now proportionally smaller (a t1 copy moves the step from 5 to 4 WIS rather
  than doing nothing until four copies stack).
- **Every INT scalar stat with a fractional total floors instead of rounding**
  — `10 STR + 5% increased` reads 10, not 11. 26 INT scalar defs are in scope;
  tests that pinned a rounded total are re-pointed, and the landing report lists
  them. Display formatting (`stat_def.gd:74`, `stat_modifier.gd`) keeps its
  `roundi` — it formats an already-coerced number.
- **`mana` is a FLOAT pool**, so `INT 15 / 10` now contributes a cap of 1.5
  rather than 1. Harmless at the planned `/1000` divisor; noted so nobody reads a
  `.5` cap as a bug.
- **"When is my next +1" moves out of the representation.** If it is wanted, it
  is a computed per-modifier readout ("next +1 from this rule at 12360 STR, → +3
  after your 200% inc") — parked on #889, not a reason to keep the stair.
- The #776 equivalence test — ratio equals the old `floor(...)` expression across
  a range — is retired by design; its contract *was* the stair.

## Alternatives considered

For a merged rule at `+1 per 3.75 WIS` with 200% increased on the target:

| variant | first +1 at | under 200% inc |
|---|---|---|
| **(i) today** — `value × floor(s/d)`, roundi | 5 (a whole authored step) | +3 burst per 5 |
| **(ii) floor per modifier** — `floor(v·s/d)`, roundi | 3.75 | **+3 burst** per 3.75 |
| **(iii) no floor, roundi** | **1.875** — half a step early | +1 per 1.25 |
| **(iii′) no floor, INT floors** — *chosen* | 3.75 | +1 per 1.25, +3 at 3.75 |

### (ii) Floor inside the ratio at the effective step, keep `roundi`
One line (`floor(value × source / divisor)`) and no global change. **Why it
lost:** the floor still sits *before* the bins, so every multiplier turns the
step back into a burst — the thing the owner ruled out.

### (iii) No floor, keep `roundi`
Smooth ramps for free. **Why it lost:** round-to-nearest hands out the first
point at half a step (WIS 13 → 2.6 → 3 XP/turn), which contradicts "nothing until
3.75 is attained" and is a silent half-step buff to every ratio target.

### Put loot mass on the divisor (`/5 → /3.75`) and match by an ID
The owner's first instinct, kept live through the discussion. Wiring a `changed`
emit on `divisor` is trivial. **Why it lost:** `merge_key` erases only `value`,
so the divisor is part of the key — an ID-based key is a second key path and a
late-join reconcile change; and rounding a *mutated* divisor to an integer is
lossy and path-dependent (four t1 loots on /5: 5 → 4 → 3 → **3**, the fourth
vanishes). Storing the exact slope to fix that makes the divisor a cache of
`divisor / value`, i.e. decision 1 with a different field name. The owner also
ruled the "integer divisor" legibility a mirage past small stat values.

### Raise the starting numerator (`+10 per 50 WIS`, doubling at n = 10)
Revived by decision 1 (no dead space once the stair is gone) and attractive
because merged values stay integers. **Why it lost:** it only works if loot mints
a *unit* of the rule rather than a fraction of the victim's value, and the owner
rejected that outright — *"If i stack to 1 gazillion and die and get looted, they
would loot a fraction of 1 gazillion. Not 1"* — so a t3 kill of a `10/50` rule
drops `+10` and doubles it anyway.

### Sublinear stack curves at evaluation (`1+√n`, `1+ln(1+n)`)
Explored to push "out of hand" further out. **Why it lost:** `1+n` is already
concave in relative terms; the only wrong step was the first one, which is the
tier ladder — and the owner kept the ladder (*"t3 loots are relatively rare and
SHOULD have an impact"*). A curve inside the merge would also break "four t1 ==
one t3".

### A per-rule `stepped` flag
Keep bursts for rules that want them. **Why it lost:** once the owner chose
ramps *because* multipliers exist, no rule wants them; the flag would only
reintroduce the wall and the dead space for whoever opted in.

### Fold `RatioFormula` into `LinearFormula` with coefficient `1/divisor`
Same maths, one class. **Why it lost (for now):** the divisor is the authored
tuning knob and the phrase players read; keeping the class keeps `describe_per`
honest with zero migration. A Ratio rule and an equivalent Linear rule do not
share a merge key — acceptable, and stated.
