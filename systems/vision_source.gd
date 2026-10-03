class_name VisionSource
extends RefCounted

## One disc of sight [method VisionSystem.sources_for] answers with: a circle at
## [member center] of [member radius] world units, contributed by [member node]
## for the reason [member kind] names. A new kind of sight adds one [enum Kind]
## value plus one gather branch in [method VisionSystem.sources_for].

enum Kind {
	OWNED,  ## A node a viewer owns; radius = its local `vision_range`.
	SCOUT,  ## The node holds a scout row of a viewer's camp; radius = [method ScoutStatus.radius_for].
}

var node: SkillNode
var center: Vector2
var radius: float
var kind: Kind


func _init(p_node: SkillNode, p_radius: float, p_kind: Kind) -> void:
	node = p_node
	center = p_node.global_position
	radius = p_radius
	kind = p_kind
