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

## AIController (`entity/controller/ai_controller.gd`)

Minimum-viable NPC controller (AI v1, #22). There are no turn phases —
the controller sequences its own actions within the single turn, pausing
briefly between them so the player can read what happened, then ends the
turn. No infinite loops — every branch exits in bounded steps.

Sequence (budget-driven, not phase-driven): NPC v1 never voluntarily
deallocates → recon pass (fog-aware, per-entity — see `AiRecon`) → spend
all SP on frontier growth, scored via `AiCombatScorer.score_frontier`
(directional-toward-enemies + a tactical-enable bonus for a pick that lands
a near-miss kill) → if no hostile is visible, end turn (growth-only
short-circuit); otherwise the AP×2 loop scores every ranged + magic
candidate against every visible hostile via `AiCombatScorer`, executes the
best, and re-evaluates — the re-eval is what makes dent-then-finish and the
1-damage floor fall out naturally rather than needing special-casing.
Melee candidates come from `AiBladeRollout` (#378 slice C) — a bounded
reach-bound-reject / steerable-proposal / two-tier-evaluation rollout
rather than exhaustive enumeration (the induced-subgraph space is too
large and a full swing resolve is milliseconds, not microseconds).

**The AI emits commands, it does not call systems** (#512). Every
mutation it decides on leaves through `_submit_and_wait` as a
`Command` applied by the one `CommandApplier`, the same queue the player's
clicks feed — which is what makes the applier the ONLY mutation path rather
than merely one of them. Read-only system access for scoring stays
(`BattleSystem` for plan composition, the navigator for reachability); what
went is the `AllocationSystem` reference the AI could have mutated through.
`turn_delay` is unaffected and deliberately kept: it is host-local
presentation pacing with no sync meaning — see
`docs/domain/multiplayer-sync-model.md`.

**Dormant Cores are scenery until they are a wall** (#604). An NPC is
indifferent to them by default (`Faction.targeted_by_ai`) — but the
indifference is a stance, not a rule, and it is re-decided every turn from
`AiRecon.is_growth_capped`. Asked AFTER the growth step (that is when
"nowhere left to allocate" is a fact rather than a guess), a capped NPC
unlocks them for the rest of its turn, shoots its way out through one, and
spends its still-banked SP on the freed node in a second growth pass — kill,
relic, expand, all on the same turn. Nothing about the *player's* ability to
clear a core changes; see `AiRecon.is_ai_target`.

Fog-aware since #378: each AI consults `AiRecon` for its OWN visibility
(not the shared player-only VisionSystem instance) — settled 2026-08-07,
"each enemy acts only on what it personally sees", no faction-shared
reveal in v1. Faction filtering uses `Entity.faction` so future
multi-faction support drops in trivially.
