@abstract
class_name AttackPlan
extends RefCounted
## Abstract parent class for a plan for an [Entity] preparing an attack.
##
## Holds shared state (attacker, mode) and the input + visualization contract:
## concrete plans handle [method _on_node_left_clicked] /
## [method _on_node_right_clicked] for input, expose visualization roles via
## [method get_highlight_role], and emit [signal state_changed] whenever any
## of their internal state shifts (pivot picked, blade toggled, target set,
## spell selected, etc.). BattleSystem rebinds [signal state_changed] across
## plan swaps so UI subscribes once to the system, not every plan.

## Semantic roles for visualizing nodes participating in a plan. The
## AttackHighlightOverlay reads these per visible SkillNode and renders
## accordingly — overlay doesn't care whether a role came from a right-click
## (melee pivot) or was derived (ranged firing position).
enum HighlightRole {
	NONE,
	ORIGIN,           ## Melee pivot / magic source / ranged firing position.
	MEMBER,           ## Secondary participant (melee blade member).
	HOSTILE_TARGET,   ## Committed enemy target.
	FRIENDLY_TARGET,  ## Committed allied target (heals / buffs).
	IN_RANGE,         ## Valid candidate the plan would accept.
	INVALID,          ## Hovered-but-rejected (range / ownership / etc.).
}

## Fires whenever any plan-internal state changes. Concrete plans emit this
## after mutations. BattleSystem rebinds + re-emits as
## attack_plan_state_changed for downstream UI.
signal state_changed

var attacker: Entity
var mode: BattleSystem.AttackMode


## error messages, empty = valid
@abstract func validate() -> Array[String]


## Pure resolution — what would happen if this plan were committed right now.
## Called for BOTH preview (UI tooltips, AI scoring) and commit (the launch
## flow drives VFX off these hits then applies them). Implementations should
## be side-effect free: no state mutation on the plan, attacker, or any node.
@abstract func resolve() -> AttackOutcome

## all required slots filled
func is_valid() -> bool:
	return validate().is_empty()


## Wipe plan-internal selection state back to its initial empty form. Keeps the
## plan instance (and any sticky mode-level preferences like melee swing_cw)
## alive — the UI's RESET button calls this so the player can re-target without
## re-picking the mode. Default is a no-op; subclasses override and emit
## state_changed when they've actually cleared something.
func reset() -> void:
	pass


## Visualization role for [param node] under this plan's current state.
## Default is NONE; concrete plans override for the nodes they care about.
func get_highlight_role(_node: SkillNode) -> HighlightRole:
	return HighlightRole.NONE


## Input hooks — concrete plans override the ones they react to. Defaults
## are no-ops so plans only implement what's relevant to their mode.
func _on_node_left_clicked(_node: SkillNode) -> void:
	pass


func _on_node_right_clicked(_node: SkillNode) -> void:
	pass


## Optional range visualization hook. Concrete plans return a non-zero
## radius to have the overlay paint a range circle around [param node]
## (e.g. ranged firing-position reach). Default 0 = no circle.
func get_node_range(_node: SkillNode) -> float:
	return 0.0


## Optional richer range visualization — rings + edges from a RangeFinder.
## Returned [code]null[/code] = nothing to paint. Magic plans hand back the
## active spell's range_finder visual; other plans can opt in as needed.
func get_source_range_visual() -> RangeVisual:
	return null


func _to_string() -> String:
	var cls: String = str(get_script().get_global_name()) if get_script() else "AttackPlan"
	var mode_name: String = BattleSystem.AttackMode.keys()[mode]
	var atk: String = attacker.display_name if attacker != null else "?"
	return "<%s %s by %s>" % [cls, mode_name, atk]
