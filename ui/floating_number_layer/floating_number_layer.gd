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

const FLOAT_DISTANCE: float = 40.0
const FLOAT_TIME: float = 0.9
const FONT_SIZE: int = 28
const OUTLINE_SIZE: int = 6
const MAX_ANGLE: int = 30  # degrees

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
	var floater := _Floater.new()
	floater.text = text
	floater.fill_color = color
	floater.global_position = world_pos
	add_child(floater)
	var t := create_tween().set_parallel(true)
	var rng_dir := randi_range(-MAX_ANGLE, MAX_ANGLE)
	t.tween_property(floater, "position",
		floater.position + Vector2(0.0, -FLOAT_DISTANCE).rotated(deg_to_rad(rng_dir)), FLOAT_TIME)
	t.tween_property(floater, "alpha", 0.0, FLOAT_TIME)
	t.tween_property(floater, "rotation_degrees", rng_dir, FLOAT_TIME)
	t.chain().tween_callback(floater.queue_free)


# --- Global signal handlers -------------------------------------------------

func _on_skill_node_damaged(node: SkillNode, amount: float, _source: Variant) -> void:
	if node == null or amount <= 0.0:
		return
	if not _node_visible(node):
		return
	spawn(node.global_position, "%d" % int(round(amount)), _COLOR_DAMAGE)


func _on_entity_wounded(entity: Entity, amount: int) -> void:
	_spawn_at_core(entity, "-%d SP" % amount, _COLOR_WOUND)


func _on_entity_healed(entity: Entity, amount: int) -> void:
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


# --- Inline floater visual --------------------------------------------------

## A Node2D that draws a single outlined string centered on its origin.
## Kept private — callers should go through [method spawn] so the drift/fade
## behavior stays consistent.
class _Floater extends Node2D:
	var text: String = ""
	var fill_color: Color = Color.WHITE
	var alpha: float = 1.0:
		set(value):
			alpha = value
			queue_redraw()
	var _font: Font

	const _OUTLINE_COLOR := Color(0.1, 0.0, 0.0, 1.0)

	func _ready() -> void:
		_font = ThemeDB.fallback_font
		queue_redraw()

	func _draw() -> void:
		if _font == null or text.is_empty():
			return
		var size := FloatingNumberLayer.FONT_SIZE
		var text_size := _font.get_string_size(
			text, HORIZONTAL_ALIGNMENT_CENTER, -1, size)
		var pos := Vector2(-text_size.x * 0.5, text_size.y * 0.25)
		var fill := Color(fill_color.r, fill_color.g, fill_color.b, alpha)
		var outline := Color(_OUTLINE_COLOR.r, _OUTLINE_COLOR.g, _OUTLINE_COLOR.b, alpha)
		draw_string_outline(_font, pos, text,
			HORIZONTAL_ALIGNMENT_CENTER, -1, size,
			FloatingNumberLayer.OUTLINE_SIZE, outline)
		draw_string(_font, pos, text,
			HORIZONTAL_ALIGNMENT_CENTER, -1, size, fill)
