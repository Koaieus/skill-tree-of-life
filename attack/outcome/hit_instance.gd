class_name HitInstance
extends RefCounted

## Base for one landing's effect on a target — [DamageInstance] and
## [HealInstance] both extend this so [AttackOutcome.hits] /
## [PropagationEvent.hits] can hold either (or, per landing, several) in one
## polymorphic list instead of parallel damage/heal slots (#381).

## What this landing did to its target, for reveal routing
## (the VFX coordinators' presentation
## pass) and for [method AttackOutcome.damage_hits]'s filter. Defaulted by
## each subclass's own [code]_init()[/code], but [b]not fixed at
## construction for damage[/b] — [method SkillNode.take_damage] reclassifies
## a [DamageInstance] to [constant Kind.HEAL] when post-[Mitigation] damage
## goes negative (a Bulwark-style `min_damage_taken` underflow — see
## `.claude/rules/stats-system.md`'s "Damage mitigation" section). A
## [HealInstance] never reclassifies; heals aren't mitigated.
enum Kind { DAMAGE, HEAL }
var kind: Kind = Kind.DAMAGE

var amount: float = 0.0
## Who/what produced this hit — [AttackPlan], [SpellDef], or any RefCounted.
## Routed back through the [signal Events.skill_node_damaged] payload so UI
## can attribute the number / decide on flash color.
var source: Variant = null
## The node this hit lands on.
var target: SkillNode = null
## The node the hit originated from (firing position / source node).
## Optional; used by VFX (tracer spawn point) and future range-falloff math.
var origin: SkillNode = null
## The [Entity] that produced this hit — the one whose stat board the crit
## roll reads (#507), and whose hostility a mode's land-time gate re-checks.
## Promoted here from three private copies (ranged's `_attacker`, melee's
## `_gate.attacker`, magic's `ctx.caster`): three accessors for one fact is
## the parallel-mirrors trap, and the shared [CritRoll] needs exactly one.
var attacker: Entity = null

## Whether this hit was elevated to a critical strike/heal. Decided at
## RESOLVE by [method CritRoll.decide_all] (stat roll + magic's condition
## check) — the VFX layer reads it for emphasis visuals before the hit lands,
## so it cannot wait for [method land_on]. The multiplier it implies is
## applied at land, by [method CritRoll.apply]; see [CritRoll] for why the
## two halves sit on different clocks.
var is_crit: bool = false
## The effective multiplier applied on a crit (default 1.0 = normal hit).
var crit_multiplier: float = 1.0
## Crit stacking tier — 0 = no crit, 1 = crit, ≥2 = multi-source. Moved down
## from [PropagationEvent] (#381): crit-ness belongs to the hit, not the
## propagation step that carried it.
var crit_tier: int = 0

## This landing's STRUCTURAL position, in whatever units its outcome's
## [member AttackOutcome.cadence] names — a hop ordinal for magic, normalized
## position in the volley's distance span for ranged, normalized position along
## the swing for melee (#543).
##
## [b]This is what the resolver writes, and the only timing-shaped thing it
## knows.[/b] It is also the only one that crosses the wire: a peer recompiles
## its own seconds from it (see [OutcomeSchedule]), so tempo may differ per
## machine without any of them disagreeing about what happened.
var structural_key: float = 0.0

## Position of this landing's [ScheduleEntry] in its
## [member AttackOutcome.schedule] — [b]the landing-order key[/b]
## ([method OutcomeApplier.in_arrival_order], #543 D2).
##
## Ordering had to leave [member arrival_time] because land order is
## gameplay-observable (cascades, land-time mitigation) and [CritRoll] consumes
## its seeded stream in exactly that order, while seconds became
## tempo-dependent and tempo became per-peer. Sorting on a float that two peers
## are ALLOWED to disagree about is a desync that reports a green suite.
##
## -1 until a schedule has been compiled; the applier compiles one rather than
## landing on an unassigned key.
var schedule_index: int = -1

## Seconds from attack launch until this hit's VFX visually reaches its target.
##
## [b]A compiler-written cache, not a resolver output[/b] (#543 D1). Its sole
## writer is [method OutcomeSchedule._write_back]; the three resolver stamps
## that used to fill it in ([SpellResolver]'s wave loop,
## [method RangedAttackPlan.resolve_against], [method MeleeAttackPlan.resolve_against])
## are gone. It survives as a field because deleting it would push the applier's
## per-hit wait and [CameraDirector]'s span walk through a dictionary lookup in
## a hot loop for zero behavioural gain — the field was never the problem,
## who wrote it was.
##
## [b]Never sort or compare on it.[/b] See [member schedule_index].
var arrival_time: float = 0.0

## Post-mitigation / post-clamp HP delta magnitude — what actually landed,
## always positive regardless of [member kind]. Filled in by
## [method NodeCombat.take_damage] / [method NodeCombat.heal_damage] the
## instant they apply this instance (still ahead of any VFX reveal).
##
## [b]Always filled by the time anyone can read it.[/b] This said "0.0 until
## applied" from when [method AttackPlan.resolve] handed back an UNLANDED plan.
## Since #536 resolving IS applying — to a [method CombatWorld.shadow] the
## caller may throw away — so every outcome [method AttackPlan.resolve_against]
## returns has already landed every hit it holds, and AI scoring reads real
## post-mitigation numbers rather than pre-mitigation estimates.
##
## Still 0.0 in exactly one case: a hit whose gate vetoed it ([member gated]),
## which never reached a mitigation pass at all. That is what [member gated]
## exists to distinguish from "their armour held".
var effective_amount: float = 0.0

## The target's HP pool around this landing, and its cap — filled by
## [method NodeCombat.take_damage] / [method NodeCombat.heal_damage] the
## instant they apply (#518).
##
## [b]These deliberately do NOT agree with [member effective_amount] on an
## overkill, and reconciling them would be a bug.[/b] Owner call 2026-08-21,
## on a 3 HP node at 5 armor taking 10:
##
## > [i]a 3 HP node at 5 armor taking 10 damage would take 5 effective, and end
## > up at 0 (not -2), lost 3 HP, and died -- all these numbers which makes
## > complete sense in the game, they tell the story. if instead this a core sat
## > on this node it wouldn't have deallocated, its HP reduced to 0 still and the
## > core would take 2 damage, effective damage 5, total hp lost 5, of which 3
## > node and 2 core[/i]
##
## So the damage FLOATER reads `effective_amount` (5) and the health BAR moves
## `hp_before` -> `hp_after` (3), and on any overkill they always will differ.
## Everything else derives and is not stored: node damage is
## `hp_before - hp_after`, overflow is `effective_amount - that`, core damage is
## the overflow when the target is its owner's core, total HP lost is the sum.
var hp_before: float = 0.0
var hp_after: float = 0.0
## The target's max HP at land time. Carried per hit rather than read off the
## owner's board because a fogged client under the filtered-delta model
## (docs/domain/multiplayer-sync-model.md) may not hold that board at all, and a
## bar needs a maximum as well as a current. One float, self-healing — owner
## call 2026-08-22, choosing this over waiting for the board-subscription
## channel in the client-fidelity unit.
var hp_max: float = 0.0

## The forced deallocations this landing caused — the depleted node plus
## everything islanded off it, each with the SP wound and `dealloc_damage` chip
## it cost (#518). Empty for a hit that did not kill a node, which is most of
## them.
##
## Recorded rather than derived, for two independent reasons. An AI reads it
## because entity `health` only moves through core overflow or that chip, so a
## hit that leaves a node at 1 HP moves it by zero — damage totals alone do not
## expose the path to eliminating an entity. A PEER reads it because
## re-deriving the islanded set means walking the defender's navigator through
## nodes a fogged client may not hold; this is the one place
## `.claude/rules/multiplayer-sync.md`'s "a peer replays a recorded result"
## was not literally true.
var deallocations: Array[DeallocEntry] = []

## The spiked defender node that popped one of the attacker's blade vertices as
## this landing was gated (#536) — null for every hit that popped nothing,
## which is nearly all of them.
##
## [b]Recorded rather than announced in place[/b], for exactly the reason
## [member deallocations] is. Under #498 step 3 the authority resolves and
## applies on a SHADOW world, where an announcement has no audience by
## construction ([method CombatWorld.is_shadow], the same branch [NodeCombat]
## makes as `host != null`), and then replays its own record on the live world
## the way every peer does. A cue emitted during that shadow pass would simply
## be lost. Carried here, it fires from [method OutcomeApplier.land_one] as the
## record lands — which puts it back on the mutation clock, where #504 put it,
## and hands a peer the pop cue it never used to get at all.
var popped_vertex: SkillNode = null

## Set when a mode's land-time gate VETOED this landing (target/origin no
## longer allocated or hostile) instead of applying it — #503. Not the same
## as [code]effective_amount == 0.0[/code]: a hit that WAS applied and
## fully-mitigated to nothing also reports `effective_amount == 0.0`, and
## the two must read differently (a gated dud vs. "their armor held"). Only
## a gating [method land_on] override sets this; a mode with no dud concept
## (melee — see `docs/domain/attack-timeline.md` "Ranged") never touches it,
## so it stays false there by construction.
var gated: bool = false


## Land this hit on [param node]. Applying-the-world stays a SYSTEM's job
## (see [code]attack/outcome/outcome_applier.gd[/code]) — this virtual only
## names the verb each subclass performs, so the applier's loop stays
## kind-agnostic. Base is abstract; every concrete subclass must override.
##
## [param node] is a [NodeCombat], not the [SkillNode] in [member target]
## (#498 step 3). The two are the same node seen two ways: [member target] is
## the hit's IDENTITY — what a record serializes and a peer resolves by
## `stable_id` — while [param node] is the STATE this landing mutates, which
## [param world] just chose. On a live world they are the same node's live
## slice; on a shadow world [param node] is a detached clone and
## [member target] still names the real one.
##
## [param world] is passed down so a mode's land-time gate can look up the
## slice for a node it holds by reference — ranged reads [member origin]'s,
## melee's pop gate reads each blade contact's. A gate that only needs the
## target itself ignores it.
func land_on(_node: NodeCombat, _world: CombatWorld) -> void:
	push_error("HitInstance.land_on is abstract — override on the subclass")
