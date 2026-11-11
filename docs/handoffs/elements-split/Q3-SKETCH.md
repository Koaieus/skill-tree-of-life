# Q3 sketch: how often a trapped Shocked goes off (morning Q3, second pass)

**A hit that breaks the ice** means a hit that crits, or a blade touch at least as heavy as the node, or (until Q1 is ruled) a raw amount at or above the flat threshold. Two hits that land "at once" are two hits in one generation of one beat. They are read together, never one after the other (ADR 0091 §1).

## 1. Do arrows ever land together? No.
Ranged and melee compile one schedule entry per hit (`attack/outcome/outcome_schedule.gd:58`, `_entries_for`). The applier treats each entry as its own beat (`attack/outcome/outcome_applier.gd:23-35`), so two arrows always land one after the other, as the owner said. Only a magic wave, one timeline beat, puts several hits in one beat. The design's blade rule (§ Landing resolution, "A blade follows the same rule") would make two contacts of one swing sample one beat, but that is not built.

## 2. The real case: one magic wave
- One wave of a spell lands on **W1** and **W2** in generation 0. Both are Shocked at level 1, and both arc to every neighbour.
- **X** is Frozen and Shocked, and neighbours W1, W2 and **Y**. X holds 8 Charge with a T of 4. W1's and W2's arcs each move 1 Charge onto X (ADR 0084 §7), so X reads 10 Charge: level 1, and still Shocked after one arc of its own (10 − 3 = 7). Each arc from X reaches W1, W2 and Y and pays 3 Charge, 1 per node.
- The spell deals 30, ×2 on a crit = 60. That is under X's flat threshold of 100 (10% of a 1000 max HP), so only a crit breaks the ice, under every Q1 shape. b = 2, the break's extra landings (ADR 0090 §1).
- **Two copies reach X in generation 1, and each is its own hit.** W1's copy belongs to W1's hit, and W2's copy to W2's hit. Each hit has its own once-per-node set (§ Landing resolution, "Each hit owns its once-per-node set"). Each copy is tested alone (ADR 0091 §4).
- **Both can break.** A copy never rolls its own crit; it carries its head's (#1798 acc 9). If both W1's and W2's hits crit, both copies break the ice. If only W1's crits, W2's copy is under the threshold: X absorbs it (no damage, no aspect riders; its terrain riders still land; ADR 0087 §1).

## 3. The same two hits one after the other (the owner's picture)
The first hit breaks the ice: one shatter, and the trapped Shocked goes off once, as a release arc. The second hit finds X unfrozen and Shocked, lands as a plain hit, and X arcs again as that hit's own go-off (a node's own go-off fires once per hit; § Landing resolution, "Dual reach"). **That makes 2 arcs.** X takes 4 landings from the first hit (its own, b = 2 extras, the release arc's centre landing) and 2 from the second (its own, the arc's centre landing), so 6. The count is the same in either order.

If only one of the two would break the ice, the order matters even one after the other:
- **Breaker first:** the shatter, then the other hit meets unfrozen X and arcs. 2 arcs.
- **The other hit first:** X absorbs it and its arc stays trapped, then the breaker shatters and releases. 1 arc.

## 4. At once, under each option
(a) **once per generation:** the ice releases once per shatter. (b) **once per hit that breaks the ice:** each such hit sets off the trapped go-off as its own.

| Case | Arcs from X | Y takes | X takes (+ one burst) |
|---|---|---|---|
| Both break, one after the other (either order) | 2 | 2 | 6 |
| Both break at once, (a) | **1** | **1** | 7 (3 + 3 + 1 centre) |
| Both break at once, (b) | **2** | **2** | 8 (4 + 4) |
| One breaks, one after the other: breaker first | 2 | 2 | 6 |
| One breaks, one after the other: the other hit first | 1 | 1 | 4 |
| One breaks at once, (a) or (b) | 1 | 1 | 4 (the absorbed copy lands nothing) |
| Unfrozen X, at once or in turn (#1798 acc 6) | 2 | 2 | 4 |

- **(b) makes "at once" give what "one after the other" gives** for the arcs and for X's neighbours whenever every hit breaks the ice. It also matches the unfrozen count. (a) halves the neighbours. (a) also needs a rule for whose payload the single release carries when the breakers differ (heaviest, plus a tie rule that never reads arrival order). Under (b), each release carries the payload of the hit that set it off.
- **When one breaks**, "one after the other" has no single answer. Both options give the "other hit first" result, which fits: X absorbed that hit, so for that hit the ice held.

**What ADR 0091 already fixes:** at once, nothing depends on which copy the game handles first. There is one read, one shatter and one burst. Every path through X walks on, each hit that breaks the ice takes its own b, and an absorbed copy stays absorbed.
**What is left:**
1. The release count above.
2. When both break at once, X takes more landings than one after the other: 8 against 6 under (b), 7 against 6 under (a). That happens because ADR 0091 §1 gives every hit that breaks the ice its own b extras, while one after the other the second hit finds no ice. It is settled, but it is the one count where "at once" is not what "one after the other" gives.
3. **A wording gap in the issues.** #1808's mute drops X's go-offs only when no hit of the generation breaks the ice. Read with #1798's once-per-hit count, the absorbed hit in "one breaks at once" would also arc: 2 arcs, and an absorbed hit landing a centre payload on X. Neither option intends that, so the rule sentence closes it. #1798's NOTES (per hit that breaks the ice) and #1808's acc 2c (one release) still disagree until the owner rules.

## 5. Recommendation: rule sentence for the doc
**The ice releases its trapped go-off once for each hit that breaks it.** A Frozen node is still read once per generation and shatters once, with one burst. Each hit of that generation that breaks the ice sets off the node's trapped go-off as its own, the same once-per-hit count an unfrozen node goes off with. Each release carries the payload of the hit that set it off. A hit the ice absorbed sets nothing off, even when another hit of its generation breaks the ice; it still walks on. (A thaw is a different case: with no ice left at the read, nothing is muted, and every hit's go-off fires as on an unfrozen node.) So two hits that break the ice at once arc twice, as they would one after the other.
