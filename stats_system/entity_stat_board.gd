@tool
class_name EntityStatBoard
extends StatBoard

## The stat board an [Entity] carries — every stat an entity can possess, as a
## typed field. The concrete half of the split promised by [StatBoard]'s old
## "tighten to typed PlayerStatBoard / EntityStatBoard inheritance" docstring
## (#332/#287); [NodeStatBoard] is its sibling, NOT its subclass — a node board
## is not a specialization of an entity board, and inheriting these ~40
## permanently-null fields onto every SkillNode was the shape worth avoiding.
##
## Property names match each Stat's `definition.id` — so `get_stat(id)` is
## just `Object.get(id)`, inherited unchanged from [StatBoard].
##
## Scalar fields use `ScalarStat` (not `Stat`) so the inspector dropdown
## offers only "New ScalarStat" — Stat itself is abstract.
## Pool fields use `PoolStat`; `.value` is the modifier-computed cap,
## `.current` is the ephemeral game state.

@export_group("Attributes")
@export var strength: ScalarStat        ## STR / Red — melee.
@export var dexterity: ScalarStat       ## DEX / Green — ranged.
@export var intelligence: ScalarStat    ## INT / Blue — magic potency.
@export var wisdom: ScalarStat          ## WIS / Gold — XP / economy.
@export var perception: ScalarStat      ## PER / Purple — vision / sensing.
@export var constitution: ScalarStat    ## CON / White — defensive bulk; scales node_health (D-11) and the entity health pool (D-21).

@export_group("Survivability")
## Entity's **Core** health, entity dies if it reaches 0. Max is
## `10 + core_health_scaling × CON` (D-21/D-26); the flat 10 is the pool's
## `base_value`, the CON term is a board intrinsic.
@export var health: PoolStat
## Entity HP restored at turn start (D-25) — `health`'s ADD-mode companion,
## named for the mechanic rather than the `<pool>_per_turn` convention (see
## PoolStatDef.per_turn_stat_id). Ungated and unramped by design: taking damage
## never suppresses it. Placeholder 1; the real rate is a #268 measurement.
@export var core_healing: ScalarStat
## HP one point of CON buys (D-26). The class-facing half of the D-21 pair —
## `core_health_scaling` sizes the pool, `dealloc_damage` sizes the chip, and
## `nodes_lost_before_death = health / dealloc_damage` is where class identity
## lives. Entity-scope only; meaningless node-locally (see #287).
@export var core_health_scaling: ScalarStat
## Max node HP one point of CON buys (#298). Same shape as
## `core_health_scaling` one field up, for the node pool instead of the entity
## pool: `node_health = 10 + node_health_scaling × CON`. A stat rather than the
## intrinsic's `value` because a CoreClass must be able to move it with an
## ordinary modifier — no genesis/class-param mechanism (D-26, D-31).
## Per-class values are #268's; the default 1.0 is not a blessed number.
@export var node_health_scaling: ScalarStat
## Board-level scalar baseline that seeds owned-node max HP. The per-node
## combat pool is [member NodeStatBoard.node_health] — same id, different Stat
## class per board; this is the aggregate it re-syncs from.
@export var node_health: ScalarStat
## Base HP a node regenerates at its owner's turn start (D-9). Node-local —
## read per-node via SkillNode.get_local_value, gated by whether the node
## took damage since the last turn start. See docs/domain/node-hp.md.
@export var node_healing: ScalarStat
## Extra node_healing per consecutive undamaged turn (SkillNode.regen_stacks,
## D-9). Self-limiting: the ramp stops at max HP and resets, so there is no
## cap stat. Node-local, same read path as node_healing.
@export var node_healing_ramp: ScalarStat
## Flat damage reduction. Applied by Mitigation.apply before the
## min_damage_taken floor. Default 0.
@export var armor: ScalarStat
## Floor on post-armor damage. A landed hit always deals at least this much
## unless TRUE-typed. Default 3; defensive classes (Bulwark) may push lower.
@export var min_damage_taken: ScalarStat
## Flat HP damage dealt to this entity per node forced-deallocated in a battle
## cascade. Bypasses mitigation (currency-exchange semantics — the cascade also
## wounds 1 SP per node, separately). Default 1; fragile-core classes raise it.
@export var dealloc_damage: ScalarStat

@export_group("Economy")
@export var xp: PoolStat            ## XP pool; fires Entity.leveled_up on fill.
@export var xp_per_turn: ScalarStat
## Entity level. Written (+1) on each XP-pool fill by Entity._on_xp_replenished;
## a plain ScalarStat (not a bespoke derived class) so level-scaling formula
## modifiers can bind to it and auto-recalc via base_value's value_changed, and
## so it stays moddable like every other stat. `Entity.level` proxies `.value`.
@export var level: ScalarStat

@export_group( "Allocation")
## Allocation budget — careful tracking via SkillPointStat (current/wounded/max
## with `used + current + wounded == max` invariant; see skill_point_stat.gd).
@export var skill_points: SkillPointStat
## Wounds healed at this entity's turn start. SkillPointStat.heal(N) flows
## that many from `wounded` back into `current`. Consumed by
## Entity._on_turn_started.
@export var wound_heal_per_turn: ScalarStat
## SP minted on each level-up (D-16, #271), read by Entity._on_xp_replenished
## in place of the old hardcoded grant(1). Default 2 — #268-tunable, not a
## pinned balance value. A milestone bonus (+1) applies on every 5th level,
## computed in Entity, not stored here.
@export var sp_gain_on_levelup: ScalarStat

@export_group("Turn Budget")
@export var deallocation_points: SurplusPoolStat  ## Default 3/3 — reshape budget. Surplus bin for #152 transient boost.
@export var action_points: PoolStat        	## Default 2/2 — attacks per turn.
@export var movement_points: SurplusPoolStat	## Default 1/1 — moves Core along edges. Surplus bin for #152 transient boost.
## Default 2 — each unused AP at turn end grants this many bonus DP + MP surplus
## next turn (#152). A modifier target like any other stat, so class identity
## tunes it (Pacifist raises, Berserker → 0) with no bespoke mechanism.
@export var ap_transfer_rate: ScalarStat

@export_group("Turn Order")
@export var initiative: PoolStat				## Turn clock; cap = action threshold (100). Cyclic — carries overshoot.
@export var initiative_speed: ScalarStat	## Ticks of initiative added per clock tick.

@export_group("Vision")
@export var vision_range: ScalarStat	## Euclidean sight radius in scene pixels.
@export var sensor_range: ScalarStat	## Topology sensor radius in hops past owned nodes.

@export_group("Ranged")
@warning_ignore("shadowed_global_identifier")
@export var range: ScalarStat			## Per-leaf firing distance in scene pixels. Localized on leaves.
@export var ranged_damage: ScalarStat	## Damage per shot. Base 1, +1 per 10 DEX. Node-local addons add on top per-node via node_board.

@export_group("Magic")
@export var mana: PoolStat				## Casting resource. Max = base + INT//10; regen = floor(log(INT)) per turn.
@export var mana_per_turn: ScalarStat	## Mana restored at turn start. Base: floor(log(INT)).
@export var spell_range: ScalarStat		## Percent bonus to EUCLIDEAN magic-spell reach only. Scales with INT via intrinsic (reduced rate, #727).
@export var spell_hops: ScalarStat		## Flat integer bonus to HOP-ranged magic-spell reach — HopRangeFinder.max_hops only, NEVER PropagationConfig.max_hops. INT threshold ladder (#727). Node-local via SpellRangeRules.bonus_hops, mirrors spell_range.
@export var spell_damage: ScalarStat	## Damage behind one spell seed, × the spell's own `power`. Base 1, +1 per 10 INT. Node-local addons add on top per-node via node_board.

@export_group("Melee")
@export var blade_size: ScalarStat		## Max blade-member nodes per melee attack (excl. pivot). Base 1, +STR//10.
@export var blade_damage: ScalarStat	## Damage per node contact. Base 1, +1 per 10 STR. Node-local addons (e.g. SpikeRing) add on top per-node via node_board.

@export_group("Crit")
@export var crit_chance: ScalarStat		## Probability (0..1) a hit crits. Baseline 5%.
@export var crit_multiplier: ScalarStat	## Damage multiplier on crit. Baseline 2.0 (double damage).

@export_group("")


## An entity board carries every stat it can legitimately hold as a typed field
## above, so mint-on-demand has nothing left to do here: reaching this override
## means a modifier named a `stat_id` this board has no field for — in practice
## a typo, or a node-only id (`stake_level`, `addon_slots`) pointed at the wrong
## board. Warn and refuse rather than silently growing an `_extra_stats` entry
## nothing will ever read.
##
## No deny-list: the rule is derived from the class shape ("not a declared
## field") rather than authored, so it cannot drift. The mirror guard on
## [NodeStatBoard] is deliberately absent — an entity-only stat minted on a node
## board is inert, not wrong, and rejecting it would mean authoring a list of
## "stats that mean nothing on a node", which is a design statement (#287's
## StatDef scope enum) rather than a mechanism.
func _mint_stat(stat_id: StringName) -> Stat:
	push_warning(
		"EntityStatBoard._mint_stat: no field for stat id '%s' — entity boards do not mint stats on demand (typo, or a node-only id on the wrong board?)"
		% stat_id
	)
	return null
