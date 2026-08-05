@tool
class_name SpikeRingAddon
extends SkillNodeAddon

## Offensive sharpness: contributes `damage` to the carrier's node-local
## `blade_damage` stat (ADD_BONUS — flat, on top of the wielder's pipeline).
## Both blade-build paths read per-vertex damage via
## SkillNode.get_local_value(&"blade_damage"), which merges this node-local
## modifier with the owner's board — so a swept spiked node deals
## base + spike, and preview matches commit. See docs/design/skill_node_addons.md.
##
## Defensive side (blade-vs-blade collision, spike-attacks-incoming-blade
## structure) is explicitly out-of-scope per docs/design/skill_node_addons.md
## — collision model is open and "do not implement until specified".

const default_color = Color.WHITE  # Color(0.95, 0.55, 0.4, 0.95)

## Flat blade_damage this node adds when swept as part of a phantom blade.
#@export var damage: float = 1.0 # REMOVING THIS ONE IN FAVOR OF JUST USING A LOCAL MODIFIER -- WE GOT THE PLUMBING FOR IT NOW. also: making it more impactful with a multiplier
@export_range(4, 24, 1) var spike_count: int = 12
@export var spike_color: Color:
	get():
		if carrier and carrier.owned_by:
			return carrier.owned_by.color
		if carrier:
			return carrier.base_type_color
		return default_color
## How far out the spike tips reach beyond the carrier's radius.
@export_range(0.0, 1.0, 0.05) var spike_overshoot: float = 0.45
## Spike base width as a fraction of the carrier's radius.
@export_range(0.05, 0.6, 0.05) var spike_base: float = 0.18

var _radius: float = 32.0

## Cached node-local modifier synthesized from `damage`. Built lazily so the
## SAME instance is handed to SkillNode on both add and remove (removal is by
## identity — see SkillNodeAddon.get_local_modifiers).
#var _damage_mod: StatModifier = null


func _ready() -> void:
	super._ready()
	if carrier != null:
		_radius = carrier.radius
		queue_redraw()


func configure_visual(r: float) -> void:
	_radius = r
	queue_redraw()


#func get_local_modifiers() -> Array[StatModifier]:
	#var out := local_modifiers.duplicate()
	#out.append(_ensure_damage_mod())
	#return out


#func _ensure_damage_mod() -> StatModifier:
	#if _damage_mod == null:
		#_damage_mod = StatModifier.new()
		#_damage_mod.stat_id = &"blade_damage"
		#_damage_mod.operation = StatModifier.Operation.ADD_BONUS
		#_damage_mod.value = damage
	#return _damage_mod


# ─── Tooltip ───────────────────────────────────────────────────────────────

func get_tooltip_title() -> String:
	return "Spikes"


#func get_tooltip_modifiers() -> Array[StatModifier]:
	#return [_ensure_damage_mod()]


func _draw() -> void:
	if _radius <= 0.0 or spike_count <= 0:
		return
	var base_half := _radius * spike_base * 0.5
	var tip_dist := _radius * (1.0 + spike_overshoot)
	var step := TAU / float(spike_count)
	for i in spike_count:
		var theta := i * step
		var radial := Vector2.from_angle(theta)
		var tangent := Vector2(-radial.y, radial.x)
		var tip := radial * tip_dist
		var b1 := radial * _radius + tangent * base_half
		var b2 := radial * _radius - tangent * base_half
		draw_colored_polygon(PackedVector2Array([tip, b1, b2]), spike_color)
