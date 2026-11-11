# Q3 sketch: how often a trapped Shocked releases (morning Q3, re-asked)

Line numbers are `docs/design/elements.md` in the working tree on 2026-11-11. A concurrent edit is moving them, so treat the § name as the anchor.

## The fixture (every number below comes from here)
- **X** is Frozen (Cold above its T) and Shocked. It holds 7 Charge against a T of 4, so its arc is level 1 (level L at count > L² × T, § The threshold model ~129). A level-1 arc reaches Y and Z and pays 1 Charge per node reached (~79). Each spent stack moves onto the node it reached (#1806 Decisions, ADR 0084 §7). The arc deals no damage of its own (#1806 Composition).
- **Y and Z** are X's only neighbours. Both are unfrozen, hold 0 Charge and have T ≥ 3, so the moved stacks never prime them. Because both are unfrozen, the owner's Q6 ruling (pay only for the nodes reached) changes nothing here.
- Every node is enemy-held, with max HP 1000 and no armor. The flat break threshold is 10% of max HP, so 100 (~265).
- **A1** deals 30 and carries a Curse rider of 3. **A2** deals 45 and carries no rider. Both are unelemented arrows and both crit at ×2, so they deal 60 and 90. The ×2 is `crit_multiplier` base 2.0 (`entity/default_entity_board.tres:202`) and the `CritRoll.multiplier_for` fallback (`attack/outcome/crit_roll.gd:133`). The crit is decided at the head, and every copy carries it (#1798 acc 9).
- **Both break by crit**: 60 and 90 are under 100. A crit breaks under all three open Q1 shapes, so nothing here waits on Q1. Both are direct hits, so they land on Frozen and are not absorbed (§ Pair rules, Frozen row).
- **b = 2**: each breaker takes 2 extra landings (ADR 0090 §1). The shatter's burst is #1807's amount, counted apart from the landings.
- **Generations**: generation 0 is the wave's arrivals at X; generation 1 is the arc's copies landing on Y and Z (ADR 0091 §1).
- **The same under both options**: one read, one shatter (one burst, one Cold spend), 1 + b landings for each breaker, and every path walks on (ADR 0091 §1 and its Consequences; #1798 "The shatter").

## 1–3. The two options, and the same arrows on an unfrozen X

| | (a) once per generation | (b) once per breaking arrival | Contrast: X only Shocked |
|---|---|---|---|
| Arcs from X | 1 | 2 (A1's, A2's) | 2 (#1798 acc 6: "both go off") |
| Landings on X, gen 0 | A1 ×3, A2 ×3, 1 centre = **7** (#1808 acc 2c: 3 + 2b) | A1 ×3 + centre, A2 ×3 + centre = **8** (4 + 2b) | A1 + centre, A2 + centre = **4** |
| Damage on X | 180 + 270 + 90 = 540, + burst | 240 + 360 = 600, + burst | 120 + 180 = 300 |
| Curse on X | 9 | 12 | 6 |
| Y, gen 1 (Z the same) | **1** landing: 90, no Curse (A2's payload, § 4) | **2** landings: 60 + Curse 3, and 90 | **2** landings: 60 + Curse 3, and 90 |
| Charge X spends | 2: 7 → 5, **X stays Shocked** | 2 + 2, summed: 7 → 3, **X falls below T** | 2 + 2: 7 → 3 |
| Charge Y, Z gain | +1 each | +2 each | +2 each |

**The deciding rule.** A node's own go-off fires **once per hit** (owner, 2026-11-10; § Landing resolution ~1199). Two arrows are two hits, so an unfrozen X arcs twice. Each arc reads the same post-land 7 Charge (#1798 acc 6; ~1114: *"several same-beat go-offs each read a deep store at full power before the clamp"*).
- **(b)** counts the released arc the same way. A broken X gets everything an unfrozen X gets, plus the breakers' 2b extra landings and the burst, and Y and Z take exactly what they take with no ice. **(b) keeps the frozen and unfrozen counts consistent.** Everything a breaker adds (its own landing, its b extras, its arc) counts per breaker. Only the shatter's spend and burst count once per node.
- **(a)** makes the released arc the one go-off that fires once per read instead of once per hit. That is an exception to the rule above, on top of the payload sub-rule in § 4. With the ice, Y and Z take half of what the same two arrows give them without it, and X keeps 2 more Charge and stays Shocked. It reads as "one ice, one storm".
- `dedupe_dual_reach` does not merge (b)'s two landings on Y. Each hit has its own once-per-node set (~1099), and the switch merges reaches only within one hit (#1798 Knobs, ADR 0086 §3). A1 and A2 are two hits.

## 4. Option (a)'s payload sub-question: A1 is lighter but carries a Curse
- **Heaviest wins.** A2 (90) beats A1 (60), so the released copies on X, Y and Z carry A2's payload: 90 each, no Curse. A1's Curse lands only through A1's own 3 landings on X. Option (b) needs no such rule, because each arc copies its own breaker (ADR 0091 driver "one clear breaker").
- **Gap 1: which number "heaviest" reads.** The obvious pick is the raw amount as thrown, crit in, × load (ADR 0091 §3). That is the read Q1 reopened.
- **Gap 2: the tie rule, which nothing written supplies.** If both arrows deal 60, the winner must come from the hits' own facts, never from arrival order (ADR 0091 driver: order independence). *Illustrative only:* the hit with more aspect-rider stacks wins, then the lower attacker `entity_id`.
- **Two attackers.** If A1 and A2 come from different players, (a) gives the whole release to one player's payload and side mask; the hit's mask decides who the copies hurt (~762, #1798 Dual reach). Under (b), each player gets their own arc.

## 5. A Burning blade vertex on the same X (Q7's Frozen half, tentative)
The vertex's contact deals 40, does not crit and carries no aspect rider. Its Heat copy is 2 over its source's T. Its disc is assumed to reach Y and Z, and it pays 2 from its own copy, never from the source node (~661, #1805). The ice holds when the vertex is lighter than X (ADR 0088 §3) and breaks when it is at least as heavy (ADR 0088 §1, §5).

| | Lead's reading: the shape runs alone (#1812 "Frozen seed") | #1805 as written: the disc is the vertex's own go-off, with a centre landing |
|---|---|---|
| Ice holds: X | **1** landing (40). The arc is muted; Charge stays 7 | **2** (the contact, plus the disc's centre landing) |
| Ice breaks: X | 1 + b + 1 (the released arc's centre) = **4**, + burst. Charge 7 → 5 | **5**, + burst. Charge the same (7 → 5) |
| Y and Z, gen 1 | Holds: 1 each (the disc). Breaks: 2 each (the arc, and the disc beside it; #1812 pass reading) | the same |

- **The readings differ only by the disc's centre landing on X.** In both, the disc reaches Y and Z even while the ice holds. Under the lead's reading, the mute never drops a shape (#1812 acc 8a). Under #1805's, the disc belongs to the vertex, not the node (#1805 NOTES).
- **Heat does not thaw X.** The vertex's Heat copy is its fuel: it is spent 1 per node reached and destroyed (~103: *"hands none to the reached nodes"*). Only a Heat addon lands Heat on X: 1 per contact (#1805 knob), once. That thaws X only if its Cold excess is ≤ 1.
- **Does it walk on?** A blade has no walk. The vertex pops in both cases (ADR 0088 §3, §5; ADR 0090 §2), and the rest of the sweep goes on. The disc's copies leave X one generation later either way; the released arc's copies leave only on a break.
- **Not decided anywhere:** whether the vertex still pops when its Heat addon thaws X before the read.

## Where the docs and issues already disagree on a count
1. **#1798 against #1808 (known; REVIEW-3 T8).** #1798's NOTES say *"as it stands a released arc fires once per breaking hit"*, which is (b). #1808's Decisions, Composition and acc 2c carry "one release", which is (a), marked tentative. Both wait on this answer, and #1798's acc 6 changes first if the answer is (a).
2. **New, surfaced by Q7.** #1805's Composition says *"an unprimed contact node takes 2"*, and #1806 acc 7 says the same for a Shocked vertex. The owner's Q7 reading (a vertex counts as a Fire-shaped cast) plus ADR 0086 §4 (a shape alone is not a channel) gives 1. The uncommitted Q7 fold into the doc (~654) does not reach those issue lines. The owner ruled on the Burning vertex only; the Shocked vertex is the same question and has not been asked.
3. **Not a disagreement, a reading.** § Pair rules words the release per hit: *"the hit that breaks the ice sets off the Shocked state"* (~1288) and *"unless this hit shatters"* (~1294). It was written with one breaker in mind, so it decides nothing, but read literally it is (b).
