@tool
class_name AmmoType
extends Resource

## One kind of arrow — what it does on hit and where it sits in the fixed
## volley order. Authored as `.tres` under `attack/ammo/types/` and listed on
## [AmmoTypeRoster]; the [Quiver] keys its bins by [member id].
##
## On hit (#495) the type is read by [RangedDamageFormula]: [method
## RangedDamageFormula.compute] scales the loosed amount by [member
## damage_scale] before mitigation, and [method RangedDamageFormula.status_for]
## emits a [StatusInstance] of [member status_def] at [member status_power]
## alongside the arrow's [DamageInstance] for the same landing. A scout type
## ([member reveal_fraction] > 0) takes neither path — see [RevealInstance].

## Bin key on the [Quiver] and suffix of the minting stat (`<id>_arrows_per_reload`).
@export var id: StringName = &""
@export var display_name: String = ""
## Position in a volley's fixed type order — lower fires (and lands) first.
## Owner (2026-09-18): armour-breaking first … poison near last, base last.
@export var order: int = 0
## Multiplier on the arrow's raw damage before mitigation. 1.0 for the base arrow.
@export var damage_scale: float = 1.0
## Status applied on a landing hit (a [StatusInstance] alongside the
## [DamageInstance]), or null.
@export var status_def: Resource = null
## Power of that status per landing arrow; a volley re-applies it per arrow
## under the def's `reapply` rule. Owner tunes.
@export var status_power: float = 1.0
## A SCOUT type (#1035): `> 0` makes the arrow deal no damage at all — the
## resolve emits one [RevealInstance] per arrow instead of a [DamageInstance]
## — with radius `firing leaf's local vision_range × reveal_fraction`. Never
## pair this with a [member status_def]: the mark is [VisionSystem]'s fact,
## not a node status (hub #949).
@export var reveal_fraction: float = 0.0
## `+%` of that radius per added scout arrow in one volley — the k-th lands
## `× (1 + reveal_stack_bonus·(k−1))`, where k counts scout arrows from the
## SAME firing leaf in landing order (the radius is that leaf's; so is the
## pile). Owner tunes.
@export var reveal_stack_bonus: float = 0.0
## Entity-board stat id minting this type on reload. The base arrow's is
## `arrows_per_reload` (node-local, summed per leaf); specials are flat.
@export var per_reload_stat_id: StringName = &""
