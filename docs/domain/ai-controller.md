# AI controller

Candidate enumeration and scoring for the AI.

## Magic candidate enumeration (`entity/controller/ai_controller.gd`)

Every (known spell × eligible casting source × visible hostile target)
combination whose plan validates. No spellbook / no known spells -> no
magic candidates, same as a naive entity that never learned one.

**Reachability comes from #728's shared `SpellTargetUnion`**  — one
`SpellTargetUnion.build` per spell, whose `RangeFinder.gather_multi`
walks every eligible caster in a single pass.


The union's `SpellTargetUnion.best_source` collapse is deliberately
NOT used. It auto-picks a caster by node-local `spell_damage` alone, while
the loop below scores every (source, target) pair fully and lets
`AiCombatScorer.pick_best` decide — which strictly dominates that
heuristic. Only the ENUMERATION is shared, never the pick.

Fog stays here (`visible_enemies`, off `AiRecon.visible_enemy_nodes`):
the union answers reachability only, and each caller applies its own viewer's
fog.

**The intersection is taken from the REACH side** — the smaller one.
`SpellTargetUnion.per_source` is already ownership-filtered, so it
holds the hostile nodes inside this spell's ball (a handful), while
`visible_enemies` holds every fog-visible hostile node and grows with
the board. Enumerating the reach and testing fog membership therefore costs
O(reach) per source instead of O(visible).

The fog list's ORDER is then re-imposed via `visible_order`,
because `AiCombatScorer.pick_best` breaks a score tie by
first-appended: appending in the range finder's gather order would silently
re-decide ties that the pre-#745 implementation settled the other way. The
sort is over the intersection only, which is why it is free.

The range test itself stays necessary — `AttackPlan.is_valid` cannot
stand in for it. validate() checks presence and source degree only, and
`AttackPlan.resolve` trusts a set target unconditionally (it exists to
preview/commit a UI-picked target, not to re-validate one), so dropping it
would let the AI "cast" at an out-of-hop-range target and still score a hit.
Two-tier gated since #537 (D1/D3) — PASS 1 below enumerates every
(spell, source, target) combination exactly as before (still cheap:
`AttackPlan.is_valid` never resolves), then PASS 2 promotes only the
top `_CANDIDATE_GATE_K`, globally across every spell and source
this turn, to a real gate-accurate `AttackPlan.resolve`. Below the
gate — every existing fixture, whose spell/source/target counts are small —
this is byte-for-byte the old exhaustive behaviour: same candidates, same
order, same scores.

## AiCombatScorer cheap_estimate and arrows_to_kill (`entity/controller/ai_combat_scorer.gd`)

Cheap pre-filter estimate for the ranged/magic two-tier gate (#537 D1/D3/D4)
— every term here is a value already sitting on the board
(`SkillNode.get_local_value`, `Entity.get_current_hp`), never
a second simulator. `raw_damage` is the caller's own already-computed
un-mitigated seed hit — `ranged_damage` for a ranged candidate,
`spell_damage(source) × power` for magic (see
`attack/spell/spell_def.gd`'s doc on that formula) — so this
function itself touches no plan, no resolve, no shadow world.

Mirrors `score`'s shape (EV, clamped to what the target can actually
absorb, plus a kill bonus and the same cut-vertex/weak-point bonuses) so the
cheap tier's ranking correlates with what the gate-accurate tier will
actually decide, rather than ranking on raw power alone — a naive
raw-damage-only heuristic is exactly what would drop a low-power near-kill
behind a high-power dud (see the D5 rank-stability test). NOT tier-gated
(`ai_tier` plays no part): this is a volume cut, not a behavior
tuning knob, and it runs before `AIController.ai_tier` would apply to
anything.
How many arrows of `outcome`, in landing order, it takes for the
running total of damage on `target` to meet its CURRENT hp — the
number a kill-sized volley carries (#958, owner: computed *"from the plan's
resolve on the shadow world … never from a hand formula"*). Reads each hit
as `expected_damage` does — post-mitigation `effective_amount`, the
number the shadow world actually subtracted — so armour, duds and the
seeded crit roll are all already in it. `-1` when the whole volley falls
short (no kill on the table), so a caller sizing N can tell "fire
everything" from "fire k".

A CORE never depletes on node hp: past 0 every hit overflows into its
owner's `health` pool (`NodeCombat.take_damage`), and the entity
dies when THAT runs out — so for a core the arrows-to-kill reach is node
hp + the owner's remaining health. (The scorer's `ScoredCandidate
.is_kill` keeps its node-hp read — the #512 golden freezes that
prediction — this helper is what sizes the volley.)
