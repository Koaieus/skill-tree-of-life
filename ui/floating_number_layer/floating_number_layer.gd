class_name FloatingNumberLayer
extends Node2D

## Floating world-space numbers. One layer per level handles every kind of
## floater (damage, wound, heal, future: XP gain, mana spend...). Each is the
## same drift-and-fade label with a different text + color.
##
## Two ways to spawn:
##   - Subscribe globally: this layer auto-listens to [signal Events.skill_node_damaged],
##     [signal Events.entity_wounded], [signal Events.entity_healed] and routes
##     them to [method spawn] with a per-kind tint.
##   - Direct: any system can call [method spawn] with arbitrary text/color.
##
## Vision gating: if [member vision_system] is set, floaters anchored at a
## SkillNode that isn't player-visible are suppressed. Without it, every event
## spawns (useful for headless tests and old sandboxes without fog).

## Each floater is a [Floater] scene that owns its own drift/fade values and
## animation (incl. an editor preview button). The layer just instantiates,
## configures text/colour/position, and kicks the animation.
const _FLOATER_SCENE: PackedScene = preload("res://ui/floating_number_layer/floater.tscn")

const _COLOR_DAMAGE := Color(1.0, 0.85, 0.85, 1.0)
const _COLOR_WOUND  := Color(1.0, 0.55, 0.55, 1.0)
const _COLOR_HEAL   := Color(0.65, 1.0, 0.7, 1.0)

## Optional. When set, floaters anchored at a SkillNode that isn't visible to
## the player are dropped on the floor — prevents fog leakage (an enemy taking
## damage off-screen would otherwise reveal itself via a number popping up).
## Null = no gating.
var vision_system: VisionSystem = null


func _ready() -> void:
	Events.skill_node_damaged.connect(_on_skill_node_damaged)
	Events.entity_wounded.connect(_on_entity_wounded)
	Events.entity_healed.connect(_on_entity_healed)
	z_index = 2000


## Generic spawn. Anchor at [param world_pos], render [param text] tinted
## [param color], drift up + fade. The single chokepoint — every kind of
## floater renders identically; only the per-event handlers above pick the
## color and string.
func spawn(world_pos: Vector2, text: String, color: Color) -> void:
	if text.is_empty():
		return
	var floater: Floater = _FLOATER_SCENE.instantiate()
	floater.text = text
	floater.fill_color = color
	add_child(floater)
	floater.global_position = world_pos
	floater.animate()


# --- Global signal handlers -------------------------------------------------

func _on_skill_node_damaged(node: SkillNode, amount: float, _source: Variant) -> void:
	if node == null or amount <= 0.0:
		return
	if not _node_visible(node):
		return
	spawn(node.global_position, "%d" % int(round(amount)), _COLOR_DAMAGE)


func _on_entity_wounded(entity: Entity, amount: int) -> void:
	# TODO: Ideally, during a cascade this triggers at each *pop* [see allocation_vfx.gd] of a node they lose
	# TODO: in general, we should find good wording for all this:
	# 		- wounded: also deals HP damage (tracked separately?) and adds to `wounds` which is a reservation block on the skill point pool (bad)
	# 		- healed: from `wound` reservation → frees up usable skill point, the opposite of wounding (-1 wound, +1 current SP)
	# also the StatPanel entries should emit floating numbers when changed, or other animation (like a temporary "+/- 123" next to the updated stat)
	
	
	_spawn_at_core(entity, "+%d WOUNDS" % amount, _COLOR_WOUND)
	

func _on_entity_healed(entity: Entity, amount: int) -> void:
	_spawn_at_core(entity, "-%d WOUNDS" % amount, _COLOR_HEAL)
	_spawn_at_core(entity, "+%d SP" % amount, _COLOR_HEAL)


# --- Helpers ----------------------------------------------------------------

func _spawn_at_core(entity: Entity, text: String, color: Color) -> void:
	if entity == null or entity.core_location == null:
		return
	var core := entity.core_location
	if not _node_visible(core):
		return
	# Flash the core itself so the number isn't the only signal — wound feels
	# like an event happening to the core, not just a number popping up nearby.
	core.play_hit_flash()
	spawn(core.global_position, text, color)


func _node_visible(node: SkillNode) -> bool:
	if vision_system == null:
		return true
	return vision_system.is_visible(node)
