class_name HitInstance
extends RefCounted

## Base for one landing's effect on a target — [DamageInstance] and
## [HealInstance] both extend this so [AttackOutcome.hits] /
## [PropagationEvent.hits] can hold either (or, per landing, several) in one
## polymorphic list instead of parallel damage/heal slots (#381).

## What this landing did to its target, for reveal routing
## ([BattleSystem._flush_presentation], the VFX coordinators' presentation
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

## Whether this hit was elevated to a critical strike/heal. Set by the
## resolver's crit pass (stat roll + condition check). The VFX layer
## reads this for emphasis visuals.
var is_crit: bool = false
## The effective multiplier applied on a crit (default 1.0 = normal hit).
var crit_multiplier: float = 1.0
## Crit stacking tier — 0 = no crit, 1 = crit, ≥2 = multi-source. Moved down
## from [PropagationEvent] (#381): crit-ness belongs to the hit, not the
## propagation step that carried it.
var crit_tier: int = 0

## Seconds from attack launch until this hit's VFX visually reaches its
## target — the presentation-clock analogue of melee's per-event
## [code]BladeHitEvent.t[/code] and magic's fixed propagation clock. 0.0 for
## hit types that don't yet compute one.
var arrival_time: float = 0.0

## Post-mitigation / post-clamp HP delta magnitude — what actually landed,
## always positive regardless of [member kind]. Filled in by
## [method SkillNode.take_damage] / [method SkillNode.heal_damage] the
## instant they apply this instance (still ahead of any VFX reveal).
## 0.0 until applied.
var effective_amount: float = 0.0


## Land this hit on [param node]. Applying-the-world stays a SYSTEM's job
## (see [code]attack/outcome/outcome_applier.gd[/code]) — this virtual only
## names the verb each subclass performs, so the applier's loop stays
## kind-agnostic. Base is abstract; every concrete subclass must override.
func land_on(_node: SkillNode) -> void:
	push_error("HitInstance.land_on is abstract — override on the subclass")
