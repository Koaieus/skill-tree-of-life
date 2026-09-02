# Spell gating + range-scaling tuning

Resumes the session of 2026-09-01 (lost) and continues 2026-09-02. Owner
decisions are attributed and dated; nothing here is implemented yet unless
marked LANDED. Delete this file once spent.

## 1. The gating table (owner-approved 2026-09-02)

`min_degree` and `mana_cost` are scalars on `SpellDef` (`attack/spell/spell_def.gd`);
range is NOT a field — it is the polymorphic `RangeFinder` inside `targeting`
(`HopRangeFinder.max_hops` or `EuclideanRangeFinder.max_distance`). A hop↔euclidean
change is a **sub-resource replacement**, not a scalar edit.

| Spell | min_degree | range | mana | vs. current |
|---|---|---|---|---|
| Spark | 0 | 3 hops | 1 | deg 1→0 |
| Bruiser | 2 | 350px | 2 | hops→**euclidean** |
| Lightning Bolt | 2 | 3 hops | 2 | unchanged |
| Leafblower | 4 | 5 hops | 3 | deg 2→4, 3→5 hops |
| Resonator | 4 | 420px | 3 | deg 2→4, hops→**euclidean** |
| Trailblazer | 3 | 300px | 3 | hops→**euclidean** |
| Healing Beam | 3 | 4 hops | 4 | **euclidean→hops**, mana 5→4 |
| Cyclone | 5 | 5 hops | 5 | deg 4→5, **euclidean→hops** |
| Reverberator | 6 | 500px | 6 | deg 3→6, hops→**euclidean**, mana 5→6 |

Owner on Cyclone (2026-09-02): "5 hops so the other BIG spell (reverberator)
has a different targeting pattern, for diversity." The two flips are deliberate.

**Caveat the numbers carry:** they were chosen under the *old* multiplicative
hop scaling. Section 2 changes what "5 hops" means in play, so expect a light
re-tune pass after it lands.

## 1b. TWO different "spell hops" — do not conflate (owner, 2026-09-02)

> "bonus spell hops (cast 'range' gate) vs bonus spell hops (in flight spell
> lands more hops/bounces) — the former we are tuning right now, the latter one
> we should be very careful about, and possibly disable entirely until we find a
> proper way to tune it — adding max hops to a spell dramatically alters its
> performance"

| | what it means | where | in scope? |
|---|---|---|---|
| **Cast-range hops** | how far away a target may be | `HopRangeFinder.max_hops` | **YES** — §2 tunes this |
| **Propagation hops** | how many times the spell bounces/chains in flight | `PropagationConfig.max_hops` (`attack/spell/propagation/propagation_config.gd:29`) | **NO** — leave alone |

**Current state is already correct at runtime**: `spell_resolver.gd:110` does
`seed_state.hops_remaining = config.max_hops` — **raw**, unscaled. No stat
grants in-flight bounces today.

**The only thing scaling propagation is the tooltip, and it is lying.**
`ui/spell_tooltip/spell_tooltip.gd:186` calls `_scale_by_spell_range(_spell.propagation.max_hops)`.
Deleting that scaling both fixes the bug (§6) and implements the owner's
"disable entirely" policy.

**Why propagation cannot take a global modifier at all.** `max_hops` means two
different things depending on whether the step self-terminates:

| spell | propagation `max_hops` | role |
|---|---|---|
| Trailblazer | **999** (was 20 — see below) | **backstop** — `trail_blazer_step.gd` walks one path and stops at the first junction (degree > 2) |
| Cyclone | 8 | limiter |
| Leafblower | 7 | limiter |
| Resonator | 6 | limiter |
| Reverberator | 5 | limiter |
| Bruiser | 4 | limiter |
| Lightning Bolt, Healing Beam | 3 | limiter |

A global "+N propagation hops" would do **nothing** to Trailblazer (it terminates
on topology, not budget) while taking Cyclone from 8 bounces to 10. One
modifier, wildly different effect per spell. Any future propagation tuning has
to be per-step-strategy, not a board stat.

> **HARD CONSTRAINT for §2:** the new `spell_hops` stat feeds `HopRangeFinder`
> **only**. It must never reach `PropagationConfig.max_hops`. Propagation
> scaling stays off until it has a deliberate tuning model of its own —
> bounce count is superlinear in effect, unlike reach.

## 2. Split `spell_range` into two stats

### The problem

One stat `spell_range` (percent; `multiplier = 1 + spell_range/100`,
`attack/spell/spell_range_rules.gd:33`) drives **two incompatible geometries**.
`HopRangeFinder` multiplies an integer hop count by it, so hop bumps land at
`spell_range >= 50/h` — **regressive**: a 5-hop spell gains its first hop at
+10%, a 2-hop spell needs +25%. Longest spells scale fastest, and reachable
targets grow ~quadratically in hops.

### Owner ruling (2026-09-02): separate the stats

> "i feel like hops and spell range need to be separated ... hops be strong.
> then spell range can stay/become pure euclidean: scaled separately only from
> board ... the +%/INT is a bit too strong i think and it would let *all* magic
> damage scale with INT"

- **New stat `spell_hops`** — flat integer bonus, added to `max_hops`, driven by
  a `ThresholdFormula` on INT.
- **`spell_range` becomes euclidean-only** — drop the innate `mod_int_to_spell_range`;
  keep the procgen `spell_range +%` pool draw (`procgen/pools/intelligence.tres:68`).

### The ladder

`stats_system/formulas/threshold_formula.gd` already exists and is exactly the
right shape — it returns the *count of breakpoints reached*, saturating at
`breakpoints.size()`. `compute` breaks on `v < b`, i.e. **`>=` semantics**, so a
breakpoint of 50 fires at exactly 50 (owner wanted the round number).

```
ThresholdFormula(intelligence, breakpoints = [50, 150, 500, 1000, 5000])
  → +1 / +2 / +3 / +4 / +5 hops
```

Owner (2026-09-02): "1000 INT surely is achievable, if you collect enough +%
and × stat modifiers ... +4 would be sick. we could even do +5 at 5000 just to
reward those who dare attain it." INT is the intended exponential wildcard stat.
A scout measured *today's* pools at 150–250 typical / ~500 heavy, so the top
tiers are deliberate headroom, not dead config.

Note `ThresholdFormula`'s own header records why it exists: `mana_per_turn` was
`floor(log(INT)/log(10.0))` and broke because `log(1000.0)` lands one ulp below
`3*log(10.0)` on glibc. Same determinism reason as the multiplayer rule.

### Why "hops be strong" is safe

Geometric breakpoints make hops grow ~`log(INT)`, so targets-in-range grow
~`(log INT)²`. The owner's own balance guideline ("ranges should at best scale
with the sqrt of something") would permit targets ∝ INT. **The ladder is far
stricter than the guideline** — the two instincts agree.

### The one that actually violates the sqrt rule

Euclidean: `multiplier = 1 + spell_range/100` is linear in the stat, targets go
as r², so targets grow **quadratically** in accumulated %. Candidate fix is
`sqrt(1 + spell_range/100)` → targets linear in investment.

**`sqrt` is multiplayer-safe** and the rule's `log`/`exp`/`pow` ban does not
extend to it: IEEE 754 *requires* `sqrt` to be correctly rounded, so it is
bit-identical across platforms; `log`/`exp`/`pow` carry no such requirement.
Worth an explicit carve-out in `.claude/rules/multiplayer-sync.md` if adopted.

**Do NOT land this in the same step as the split** — removing the innate INT
scaling AND applying sqrt is a compounding nerf to the five euclidean spells,
and you could not attribute playtest feedback to either change.

### OPEN: euclidean's innate source

Removing `mod_int_to_spell_range` leaves euclidean scaling from the procgen pool
alone. Owner is undecided: "possibly other sources? but which?" Candidates:
node-local range-extender addons (#171), a core-class aura. Decide before the
table's five euclidean spells are judged.

### Consumers to update (the grep that sizes the work)

- **Four boards**, not one: `entity/default_entity_board.tres:246` plus
  `entity/blocker/blocker_{small,medium,large}_board.tres:214`.
- `attack/range_finder/hop_range_finder.gd:35` — replace
  `int(round(max_hops * mult))` with `max_hops + int(spell_hops)`.
- `attack/range_finder/euclidean_range_finder.gd:49` — keeps the multiplier.
- `ui/spell_tooltip/spell_tooltip.gd:182-203` — **duplicates the hop-scaling
  formula** (its own comment says "same formula as HopRangeFinder"). A parallel
  mirror; it must consume the same rule, not re-derive it.
- `ui/spell_picker_bar/spell_picker_bar.gd:61` — comment references hop scaling.
- `addons/spell_playground/playground_panel.gd:301` — grants `spell_range`.
- `stats_system/entity_stat_board.gd:121`, `stats_system/stat_def_roster.tres`.
- **No test references `spell_range`** — nothing protects this; add coverage.

## 3. Self-loops count toward casting degree (owner ruling, CLOSED)

The 2026-09-01 session left this open. `graph/graph_mirror.gd:117` counts a
self-loop as **+2** degree (`connections + 2 * self_loop_count`), so Cyclone's
degree-5 gate clears on 3 real edges + 1 self-loop, Reverberator's 6 on 2 + 2.

Owner (2026-09-02) — **ruled, do not reopen**:

> "self loops are a topology feature, they are caster gates but often carry
> risks as being targeted or incurring extra damage. and they're in part the
> reason a 6-degree requirement is doable, possibly we could raise min degree
> even higher (though then we would implicitly require 1 or more self loops to
> be present). self loops MUST count towards casting degree"

Gate correctly uses **entity-degree** (owned subgraph) via
`attacker.navigator.get_degree(source)` (`entity/spell_book.gd:108`), per
`.claude/rules/degree.md`. Not whole-board. Implication to keep in view: any
gate above ~6 implicitly *requires* a self-loop.

## 4. Targeting inversion (design round not yet held)

Owner's proposal: pick spell first → collect owned nodes that can cast it →
union their per-source targetings → show valid targets directly. Also wanted for
the AI planner, to cut combinatorics.

Already exists (the inversion is mostly assembly, not new logic):
- `SpellBook.castable_from(source, attacker)` — spells castable from a node.
- `Targeting.valid_targets(plan, source)` — targets from a source.
- `MagicAttackPlan._cached_valid_targets` — existing cache seam.

Genuinely new / watch out:
- **Vision is the only new logic.** FOW lives at `AiRecon.visible_enemy_nodes`,
  AI-side only — *not* in the targeting predicates. A UI-side filter here would
  become exactly the parallel mirror to avoid.
- **Mana gating is scattered** — enforced at launch, no single predicate.
- **Perf**: `valid_targets` walks the whole graph via `_filter_skill_nodes`, and
  the AI is already O(spells × owned × visible). A naive union *worsens*
  combinatorics on an 800-node board. Decide the cache level up front.

### The `spell_damage` kicker — and why it is ONE question, not two

Owner: core-class auras grant node-local `spell_damage` (e.g. more the closer to
the core), so the same spell cast at the same target from different owned nodes
deals different damage. Source choice is therefore *not* moot.

**`spell_range` is node-local too** — `spell_range_rules.gd:35` reads
`source.get_local_value(&"spell_range")`, the same `NodeCombat` merge path as
`spell_damage` (`spell_resolver.gd:306`), and the procgen pool grants it as a
*node* modifier. So effective reach already varies per source node **by stat**,
not just by position. The union-of-targetings is a union of *per-node radii*.
Same shape as the damage problem → same answer should serve both.

Owner floated a hotspot/heatmap on targets ("the redder the more spell damage a
potential caster node of yours is in range of it"). Default to it, with the
payload being per-**target** "best available caster value". **Measure first:**
the actual spread of node-local `spell_damage` across owned nodes
(`effects/aura_effect.gd:120`, `Ninja_core.tres`, `Serpent_core.tres`). ±10%
wobble → auto-pick the best source silently; 2× → the affordance is earned.

## 5. Sequencing

1. **Stat split** (§2) first — it is the change that can break loading, and it
   redefines what the table's hop numbers mean. Isolate it.
2. **Table** (§1) second, judged under the new scaling.
3. **sqrt on euclidean** (§2) as a separate, attributable step.
4. **Targeting inversion** (§4) as its own design round, after a measurement.

`mise run check` after the `.tres` edits — the hop↔euclidean swaps are
sub-resource replacements, so confirm the defs still load.

## 6. Bugs / issues found along the way (file separately, do not chase here)

- **Tooltip lies about propagation depth.** `spell_tooltip.gd:186` scales
  `propagation.max_hops` by `spell_range`; `spell_resolver.gd:110` uses
  `config.max_hops` **raw**. Over-reports for any caster above baseline INT.
  Pre-existing, independent of this work.
- **`pow()` in peer-reproduced procgen — ASSESSED, ACCEPTED, not filed.**
  `procgen/pools/stat_pool.gd:228,279` uses `pow` for tier weights, and peers
  reproduce the map from the shared seed (`game-session.md`), so a one-ulp
  difference could in principle flip a weighted draw and diverge the whole
  sequence. Deliberately **not** being chased, on owner's call (2026-09-02) plus
  two mitigations: (a) a divergence is caught by `CommandLink._report_sync`
  fingerprints and repaired by a `KIND_RESYNC` world push
  (`multiplayer-sync-model.md:295-303`) — a hitch, not a corrupted run; (b) it
  requires cross-platform play *and* a cumulative weight landing within an ulp
  of the threshold. Rare × recoverable. Revisit only if a real desync is
  observed. (`procgen/placement/gaussian_bump_field.gd` also uses `exp`, but is
  not currently used at all — owner, 2026-09-02.)
  Related owner judgement on the *range* case: under host-authoritative
  intent-up, a client whose range math differs by an ulp merely gets its intent
  rejected ("no, out of range") — a papercut, not a desync. Do not use
  determinism to argue against `sqrt` or similar in the reach path.
- **DEX has no drawback → filed as #718**, widened: four of seven pools
  (dexterity, mobility, perception, wisdom) carry no drawback at all, and
  `intelligence` is taxed by *two* pools (strength -2%, constitution -3%) while
  taxing only `node_health` (-2%). Design pass, not a bug.
