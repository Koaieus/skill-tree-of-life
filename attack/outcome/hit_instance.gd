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
## `docs/domain/stat-upkeep-and-combat.md` § "Damage mitigation"). A
## [HealInstance] never reclassifies; heals aren't mitigated. [StatusInstance]
## (#878) adds a third value — never reclassified either, and deliberately
## excluded from [method AttackOutcome.damage_hits]'s filter, so an AI scorer
## or a "damage dealt" reader does not see a status application as a hit.
## [GateFlipInstance] adds [constant Kind.GATE_FLIP]: a melee fuse's timed gate
## flip, no HP — it carries gate pairs and the stranded set it cascaded.
## [ExertInstance] adds [constant Kind.EXERT]: an origin-set node exerting at
## launch, no HP — it runs [method StatusDef._on_exerted] on the node's rows.
## Appended LAST: the wire carries `int(kind)`, so existing values never shift —
## 3 was a retired kind and stays unused.
enum Kind { DAMAGE, HEAL, STATUS, GATE_FLIP = 4, EXERT = 5 }
var kind: Kind = Kind.DAMAGE

## What [member amount] is denominated in. [constant AmountBasis.FLAT] is HP;
## [constant AmountBasis.PERCENT_MAX] is a fraction of the TARGET's max hp and
## [constant AmountBasis.PERCENT_CURRENT] a fraction of its CURRENT hp (a chunk
## that can never itself be lethal, and scales with how healthy the target is
## — the Bruiser shape), either of which [method land_on] resolves into HP
## exactly once via [method resolve_amount]
## against the landing slice (the world-aware read — max hp is the owner's
## board, and ownership can move between resolve and land). One knob for
## damage and heal alike, authored on the producer ([DamageEffect] /
## [HealEffect]'s export, [PoisonStatus]'s tick), never chosen at land.
##
## A PERCENT_MAX damage hit becomes a concrete number BEFORE [Mitigation]
## runs, so armour eats it like any other hit — sizing and bypass are
## separate axes; bypass is [constant DamageInstance.Type.TRUE]'s job.
enum AmountBasis { FLAT, PERCENT_MAX, PERCENT_CURRENT }
var basis: AmountBasis = AmountBasis.FLAT

## The hit's magnitude in the units [member basis] names. Until [method
## land_on] runs it may be a COEFFICIENT rather than HP — PERCENT_MAX here,
## the speed-curve factor in [BladeDamageInstance] (#779) — and land resolves
## it in place, once, on the authority's own resolve. [method
## AttackRecord.rebuild] reconstructs a FLAT hit carrying the resolved number,
## so a peer's replay cannot scale it a second time.
var amount: float = 0.0
## Who/what produced this hit — [AttackPlan], [SpellDef], or any RefCounted.
## Routed back through the [signal Events.skill_node_damaged] payload so UI
## can attribute the number / decide on flash color.
var source: Variant = null
## The [AmmoType] id of the arrow this hit belongs to; `&""` = not an arrow.
## Promoted to the base like [member attacker]: the [AttackRecord] round-trip
## rebuilds plain hits, so the type must ride the base class to reach a peer.
var ammo_type_id: StringName = &""
## The node this hit lands on.
var target: SkillNode = null
## The node the hit originated from (firing position / source node).
## Optional; used by VFX (tracer spawn point) and future range-falloff math.
var origin: SkillNode = null
## The attacker-side node whose local stats this hit reads — the firing leaf
## for an arrow, the node a contacting blade vertex was copied from, the cast
## source on every spell hop. Never a VFX fact (that is [member origin], which
## melee pins to the pivot and magic to the previous hop), and never on the
## wire: like [member source] it is resolve-local, so an [AttackRecord]
## rebuild leaves it null — what it feeds is resolved on the authority and
## shipped as numbers.
var read_node: SkillNode = null
## The [Entity] that produced this hit — the one whose stat board the crit
## roll reads (#507), and whose hostility a mode's land-time gate re-checks.
## Promoted here from three private copies (ranged's `_attacker`, melee's
## `_gate.attacker`, magic's `ctx.caster`): three accessors for one fact is
## the parallel-mirrors trap, and the shared [CritRoll] needs exactly one.
var attacker: Entity = null

## Whether this hit was elevated to a critical strike/heal. Decided at
## LANDING by [method CritRoll.decide] (stat roll + magic's condition tier),
## called from [method OutcomeApplier.land_one] off
## [member AttackOutcome.crit_stream] right before [method land_on]; on a
## replay the recorded value lands as-is, and the VFX layer reads it off that
## rebuilt record. The multiplier it implies is applied in [method land_on],
## by [method CritRoll.apply]; see [CritRoll].
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



## The primary hit this one rides on — an arrow's damage hit, a blade
## contact — or null for a hit nothing gates (a spell's, a primary's own). A
## rider of any kind: [method rider_gated] duds it iff [method landed] says
## the paired hit did not land (ADR 0049). Never shipped by [AttackRecord]:
## the authority already decided the gate, so a rebuilt hit has
## [code]paired == null[/code] and lands its recorded number.
var paired: HitInstance = null

## The landing this hit belongs to ([member HitLanding.hit_key]): an arrow
## and every rider it emitted share one key, so "the riders of arrow i" are
## the later hits sharing its key, and [method StatusHost.greed_arm] spends
## once per landing. Shipped by [AttackRecord] on every hit. `0` is "no
## landing behind it" (a bare arrow, a hand-built hit) and never matches.
var hit_key: int = 0

## Land-time ownership recheck, a mask over [enum SkillNode.Ownership]: at
## land the receiving node's [method NodeCombat.ownership_bit] to
## [member attacker] must intersect it, else [method rider_gated] duds the
## hit. `0` = no recheck. A [SplashEffect] copy sets its [member SplashEffect.ownership_filter]. Never shipped:
## decided once, on the authority's resolve.
var land_mask: int = 0

## Set by [method AttackRecord.rebuild] on every hit: the authority already
## decided this hit's land-time gate, so [method rider_gated]'s mask clause
## never re-reads ownership on a replay.
var land_resolved: bool = false


## The one rider gate both [method StatusInstance.land_on] and
## [method DamageInstance.land_on] consult first: true iff [member paired]
## did not land, or [member land_mask] is set, the hit is not
## [member land_resolved], and [param node]'s ownership bit to
## [member attacker] misses the mask. Reports only — each caller duds itself.
func rider_gated(node: NodeCombat) -> bool:
	if paired != null and not paired.landed():
		return true
	return land_mask != 0 and not land_resolved \
			and (node.ownership_bit(attacker) & land_mask) == 0


## Whether [method CritRoll.decide] rolls this hit's crit off the outcome's
## stream. False for a hit that inherits its crit from [member paired]
## ([PairedDamageInstance]) — it must draw nothing, or every later hit's
## crit shifts.
func draws_own_crit() -> bool:
	return true


## Whether this hit actually landed — what a rider of any kind
## ([member paired]) gates on. Base: not vetoed by its mode's
## land-time gate ([member gated]). A mode whose refusal is not a dud
## (melee's unadmitted contact) overrides it. Read after this hit's own
## [method land_on]: a rider lands after its primary hit.
func landed() -> bool:
	return not gated


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


## Resolve [member amount] into HP against the landing slice, per [member
## basis] — idempotent by construction: it flips [member basis] to FLAT, so a
## second call (or a rebuilt record's replay) multiplies nothing. Called by
## each subclass's [method land_on] ahead of [method CritRoll.apply]; the two
## multiplies commute, the order just keeps "what did this hit ask for" and
## "how hard did it crit" as separate steps.
##
## A PERCENT_CURRENT damage chunk is rounded up here (ADR 0033) and clamped to
## current hp − 1, so it is never itself lethal however the round-up falls — a
## 1 hp node takes 0 (owner, 2026-10-02). Pre-crit, as before: a crit can still
## push it over.
func resolve_amount(node: NodeCombat) -> void:
	match basis:
		AmountBasis.PERCENT_MAX:
			amount *= node.get_max_hp()
		AmountBasis.PERCENT_CURRENT:
			var current := node.get_current_hp()
			amount *= current
			if kind == Kind.DAMAGE:
				amount = minf(HitPoints.whole(amount), maxf(0.0, current - 1.0))
		_:
			return
	basis = AmountBasis.FLAT
