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
