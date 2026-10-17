@tool
class_name BlockerCoreClass
extends CoreClass

## A Dormant Core's aspect face: the faceless blocker's class (the falloff aura,
## the core look) plus grants of one aspect, scaled by the blocker's size —
## `<id>_aspect` count, `<id>_stacks_per_hit` potency and `<id>_resistance`,
## each granted only where [StatRegistry] declares the stat. One `.tres` per
## aspect under `entity/blocker/faces/`; see `docs/domain/dormant-core.md`.
##
## The grants are minted in [method apply] from [member Entity.entity_tier]
## (1..3 = SMALL..LARGE) and land in [member Entity.core_modifiers], so the
## kill loots them through the ordinary register bucket; each is
## [member StatModifier.loot_pinned] so a faced kill always offers its face.
##
## [b]Per-instance state rides the entity's meta[/b], never this shared
## resource: the LARGE potency roll (+N or ×N) reads [constant FACE_SEED_META],
## stamped by [method EntityFactory.spawn_blocker] before `add_child`.

## Meta key carrying the per-placement face seed onto the entity.
const FACE_SEED_META := &"blocker_face_seed"
const _SIZE_COUNT := 3

## The aspect this face wears — its id names the granted stats, its tint
## colours the blocker.
@export var identity: Identity = null
## `<id>_aspect` ADD_BASE per SMALL / MEDIUM / LARGE. Tentative.
@export var count_by_size: Array[int] = [1, 2, 4]
## Extra count per size on top of [member count_by_size] — for an aspect
## without a potency stat (armor break), whose bigger tiers grow by count
## instead. Tentative.
@export var extra_count_by_size: Array[int] = [0, 0, 0]
## `<id>_stacks_per_hit` ADD_BASE per size; 0 grants nothing. Tentative.
@export var potency_by_size: Array[float] = [0.0, 1.0, 2.0]
## Chance the LARGE potency grant is a MULTIPLY by [member
## potency_multiply_value] instead of the additive grant. Tentative.
@export_range(0.0, 1.0, 0.01) var potency_multiply_weight: float = 0.25
## The LARGE potency multiplier when the roll lands on MULTIPLY. Tentative.
@export var potency_multiply_value: float = 2.0
## `<id>_resistance` ADD_BASE per size, where the stat exists. Tentative.
@export var resistance_by_size: Array[float] = [0.0, 5.0, 10.0]


func apply(entity: Entity) -> void:
	super(entity)
	if entity.stat_board == null:
		return
	var size := clampi(entity.entity_tier - 1, 0, _SIZE_COUNT - 1)
	for m in grants_for(size, int(entity.get_meta(FACE_SEED_META, 0))):
		# A blocker board is sparse: it mints a facet only on demand, and
		# `add_modifier` drops one aimed at a facet it lacks.
		entity.stat_board._ensure_stat(m.stat_id)
		entity.grant_core_modifier(m)


## The fresh, pinned modifiers this face grants at [param size] (0..2) for a
## placement seeded [param face_seed]. Pure: same inputs, same grants.
func grants_for(size: int, face_seed: int) -> Array[StatModifier]:
	var out: Array[StatModifier] = []
	assert(size >= 0 or face_seed != 0)  # STUB
	return out
