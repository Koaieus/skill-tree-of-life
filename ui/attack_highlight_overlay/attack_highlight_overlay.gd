class_name AttackHighlightOverlay
extends Node2D

## World-space overlay that paints a ring around every SkillNode tagged with
## a non-NONE HighlightRole by the active AttackPlan. One overlay handles
## every plan type — concrete plans expose their state via
## [method AttackPlan.get_highlight_role] and this widget paints it.
##
## Mounted programmatically by GameRoot so no scene wiring is required.

@export var battle_system: BattleSystem
@export var graph: Graph

const RING_PADDING: float = 6.0
const RING_WIDTH: float = 3.0
const RING_SEGMENTS: int = 32

const ROLE_COLORS: Dictionary[int, Color] = {
	AttackPlan.HighlightRole.ORIGIN:          Color(1.0, 0.85, 0.0, 0.9),
	AttackPlan.HighlightRole.MEMBER:          Color(1.0, 0.55, 0.1, 0.85),
	AttackPlan.HighlightRole.IN_RANGE:        Color(0.45, 0.95, 0.45, 0.55),
	AttackPlan.HighlightRole.HOSTILE_TARGET:  Color(1.0, 0.2, 0.2, 0.95),
	AttackPlan.HighlightRole.FRIENDLY_TARGET: Color(0.2, 0.7, 1.0, 0.95),
	AttackPlan.HighlightRole.INVALID:         Color(0.45, 0.45, 0.45, 0.55),
}


func _ready() -> void:
	if battle_system == null:
		push_warning("AttackHighlightOverlay missing battle_system; nothing to paint")
		return
	battle_system.attack_plan_changed.connect(_on_repaint_needed.unbind(1))
	battle_system.attack_plan_state_changed.connect(_on_repaint_needed)


func _on_repaint_needed() -> void:
	queue_redraw()


func _draw() -> void:
	if battle_system == null or graph == null:
		return
	var plan := battle_system.attack_plan
	if plan == null:
		return
	for sn in graph.get_skill_nodes():
		var role: int = plan.get_highlight_role(sn)
		if role == AttackPlan.HighlightRole.NONE:
			continue
		var color: Color = ROLE_COLORS.get(role, Color.WHITE)
		var center := sn.global_position - global_position
		draw_arc(center, sn.radius + RING_PADDING, 0.0, TAU, RING_SEGMENTS, color, RING_WIDTH)
