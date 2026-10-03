@tool
class_name ScoutStatus
extends StatusDef

## The scout status (`scouted.tres`, id `scout`): camp-keyed stacks a scout
## arrow lands, whose reveal disc is the def's own function of the count —
## [method radius_for], `radius_scale · √n · V` — the count-in, effect-out
## rule of ADR 0032 (the [BlindnessStatus] precedent). The def is shared and
## stateless; it applies no modifiers and has no behaviour hooks.

## The scale in `radius_scale · √n · V`. Owner knob, tentative.
## At V = 400: 1 stack → 200, 4 → 400, 9 → 600.
@export_range(0.0, 2.0, 0.05, "or_greater") var radius_scale: float = 0.5
## A never-owned node's V, as a multiple of its own [member SkillNode.radius].
## Owner knob, tentative.
@export_range(0.0, 40.0, 0.5, "or_greater") var fallback_radius_factor: float = 10.0


## The reveal radius [param stacks] scout stacks give on [param node]. V is,
## in priority order: the node's live local `vision_range` while owned; the
## sight it remembered when it last lost its owner
## ([member SkillNode.last_owned_vision]); else
## [member fallback_radius_factor] × the node's radius. `0` for no stacks.
func radius_for(node: SkillNode, stacks: int) -> float:
	if node == null or stacks <= 0:
		return 0.0
	return radius_scale * sqrt(float(stacks)) * sight_of(node)


## V in [method radius_for] — the sight the node lends a scout disc.
func sight_of(node: SkillNode) -> float:
	if node.owned_by != null:
		return float(node.get_local_value(&"vision_range"))
	if node.last_owned_vision > 0.0:
		return node.last_owned_vision
	return fallback_radius_factor * node.radius

