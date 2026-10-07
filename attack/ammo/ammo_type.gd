@tool
class_name AmmoType
extends Resource

## One kind of arrow — what it does on hit and where it sits in the fixed
## volley order. Authored as `.tres` under `attack/ammo/types/` and listed on
## [AmmoTypeRoster]; the [Quiver] keys its bins by [member id].
##
## On hit (#495) the type is read by [RangedDamageFormula]: [method
## RangedDamageFormula.compute] scales the loosed amount by [member
## damage_scale] before mitigation, and [method RangedDamageFormula.riders_for]
## runs every one of [member on_hit_effects] for the same landing, so their
## hits ride the arrow's beat. A scout type ([method is_scout]) is no
## exception: its zero-damage arrow carries a `scout` stack like any rider.

## Bin key on the [Quiver]; the stat minting it is [member per_reload_stat_id].
@export var id: StringName = &""
@export var display_name: String = ""
## Position in a volley's fixed type order — lower fires (and lands) first.
## Owner (2026-09-18): armour-breaking first … poison near last, base last.
@export var order: int = 0
## Multiplier on the arrow's raw damage before mitigation. 1.0 for the base arrow.
@export var damage_scale: float = 1.0
## What a landing arrow carries (ADR 0044), run in order by [method
## RangedDamageFormula.riders_for] against one [HitLanding] paired to the arrow
## — a status rider is an [ApplyStatusEffect], whose power a volley re-applies
## per arrow under the def's `reapply` rule (owner tunes).
## Spell-only riders ([SpellOnHitEffect]) are dropped at load with one
## `push_error` each; the stored array never holds one.
@export var on_hit_effects: Array[OnHitEffect] = []:
	set(value):
		var kept: Array[OnHitEffect] = []
		for effect in value:
			if effect is SpellOnHitEffect:
				push_error("%s: %s is spell-only; refused from on_hit_effects" % [resource_path, str(effect.resource_path)])
			else:
				kept.append(effect)
		on_hit_effects = kept
## Entity-board stat id minting this type on reload. The base arrow's is
## `arrows_per_reload` (node-local, summed per leaf); specials are flat.
@export var per_reload_stat_id: StringName = &""
## A special's own bank cap: its bin holds at most this many, outside the
## quiver's shared capacity (owner, 2026-10-01: "Banks, capped at 999 per
## type"; ADR 0041). The base arrow ignores it — its cap is the `arrows` pool's
## max. Owner tunes.
@export_range(1, 9999) var max_stock: int = Quiver.DEFAULT_MAX_STOCK
## What this type's arrow looks like in flight — a [StatusArrow]-family scene
## (`ui/vfx/projectile/visual/`). Null → the volley coordinator's default
## [member ArrowVolleyCoordinator.visual_scene], today's plain [LightArrow].
@export var visual_scene: PackedScene = null


## The first non-null [method OnHitEffect.status_def] in [member on_hit_effects]
## (a wrapper answers for what it wraps), or null — tint only (card swatch,
## arrow hue); the riders pass runs every effect.
func first_status_def() -> StatusDef:
	for effect in on_hit_effects:
		var def := effect.status_def() if effect != null else null
		if def != null:
			return def
	return null


## A scout type: one of its riders lands a [ScoutStatus] — the only kind that
## may fly into fog at a sensed-only node.
func is_scout() -> bool:
	for effect in on_hit_effects:
		if effect != null and effect.status_def() is ScoutStatus:
			return true
	return false
