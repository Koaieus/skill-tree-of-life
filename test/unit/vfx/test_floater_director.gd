extends GutTest

## #81 — FloaterToasterManager / FloaterToaster integration.
## Covers: renderer is the right type; spawn routes to per-target toasters;
## null/empty are suppressed; damage events route through the director;
## bursts stagger one-per-fade_in; ungrouped requests get separate toasters;
## queue cap drops oldest overflow.

const _DIRECTOR_SCENE := preload("res://ui/floating_number_layer/floater_director.tscn")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")

var _director: FloaterDirector
var _renderer: FloaterToasterManager


func before_each() -> void:
	_director = _DIRECTOR_SCENE.instantiate() as FloaterDirector
	_director.vision_system = null  # no fog gating in tests
	add_child_autofree(_director)
	_renderer = _director.renderer


func _toaster_children() -> Array:
	return _renderer.get_children().filter(func(c): return c is FloaterToaster)


func test_scene_wires_renderer() -> void:
	assert_not_null(_renderer, "director scene resolves its renderer child")
	assert_true(_renderer is FloaterToasterManager)


func test_renderer_spawns_at_target() -> void:
	var node := Node2D.new()
	add_child_autofree(node)
	node.global_position = Vector2(123, 45)
	var req := FloaterRequest.new()
	req.target = node
	req.text = "+5"
	req.style = FloaterStyle.new()
	_renderer.spawn(req)
	var toasters := _toaster_children()
	assert_eq(toasters.size(), 1, "exactly one toaster spawned")
	assert_eq((toasters[0] as FloaterToaster).global_position, Vector2(123, 45), "anchored at target")


func test_renderer_ignores_empty_and_null() -> void:
	_renderer.spawn(null)
	var req := FloaterRequest.new()
	req.text = ""
	_renderer.spawn(req)
	assert_eq(_toaster_children().size(), 0, "no toaster for null request or empty text")


func test_damage_event_routes_through_director() -> void:
	var node := _SKILL_NODE_SCENE.instantiate() as SkillNode
	add_child_autofree(node)
	await get_tree().process_frame
	Events.damage_shown.emit(node, 7.0)
	var toasters := _toaster_children()
	assert_eq(toasters.size(), 1, "a damage fact becomes one toaster")
	var vbox := toasters[0].get_node("VBoxContainer") as VBoxContainer
	assert_eq(vbox.get_child_count(), 1, "one toast in the stack")
	var toast := vbox.get_child(0) as FloaterToast
	assert_eq(toast.label.text, "7", "rounded damage amount")


func test_zero_damage_makes_no_toaster() -> void:
	var node := _SKILL_NODE_SCENE.instantiate() as SkillNode
	add_child_autofree(node)
	await get_tree().process_frame
	Events.damage_shown.emit(node, 0.0)
	assert_eq(_toaster_children().size(), 0, "non-positive damage is suppressed")


func test_burst_staggers_by_target() -> void:
	var target := Node2D.new()
	add_child_autofree(target)
	for i in 3:
		var req := FloaterRequest.new()
		req.target = target
		req.text = "+%d" % i
		_renderer.spawn(req)
	var toasters := _toaster_children()
	assert_eq(toasters.size(), 1, "one toaster per target")
	var vbox := toasters[0].get_node("VBoxContainer") as VBoxContainer
	assert_eq(vbox.get_child_count(), 1, "first fires immediately; 2 queued")
	var fade_in: float = (vbox.get_child(0) as FloaterToast).fade_in_duration
	await get_tree().create_timer(fade_in * 2.2).timeout
	assert_eq(vbox.get_child_count(), 3, "all 3 popped after stagger intervals")


func test_ungrouped_creates_separate_toasters() -> void:
	for i in 2:
		var req := FloaterRequest.new()
		req.target = null
		req.anchor = Vector2(i * 10.0, 0.0)
		req.text = "x"
		_renderer.spawn(req)
	assert_eq(_toaster_children().size(), 2, "ungrouped (key==0) each get their own toaster")


func test_max_stack_drops_oldest() -> void:
	_renderer.max_queue_size = 2
	var target := Node2D.new()
	add_child_autofree(target)
	for i in 4:
		var req := FloaterRequest.new()
		req.target = target
		req.text = "t%d" % i
		_renderer.spawn(req)
	# t0 popped immediately; queue held [t1,t2,t3] → capped to [t2,t3] (t1 dropped).
	var toasters := _toaster_children()
	assert_eq(toasters.size(), 1)
	var vbox := toasters[0].get_node("VBoxContainer") as VBoxContainer
	var fade_in: float = (vbox.get_child(0) as FloaterToast).fade_in_duration
	await get_tree().create_timer(fade_in * 2.5).timeout
	assert_eq(vbox.get_child_count(), 3, "first + 2 queued; oldest dropped")


func test_model_damage_alone_floats_nothing() -> void:
	# #482: the damage number is a reveal like the HP bar and the tint. It rides
	# Events.damage_shown, which the VFX coordinators fire when the swing/arrow/
	# bolt lands (and PresentationPlayer.play_instant backstops when no
	# coordinator runs). Reacting to skill_node_damaged instead would float the
	# number over a node the projectile has not reached — that was the bug.
	var node := _SKILL_NODE_SCENE.instantiate() as SkillNode
	add_child_autofree(node)
	await get_tree().process_frame
	Events.skill_node_damaged.emit(node, 7.0, null)
	assert_eq(_toaster_children().size(), 0,
			"model mutation alone must not float a number")


func test_heal_shown_floats() -> void:
	# #481/#482: the attack-heal number rides Events.heal_shown, the same arrival
	# reveal as damage — it must appear when the heal's VFX lands, not when
	# BattleSystem applied it.
	var node := _SKILL_NODE_SCENE.instantiate() as SkillNode
	add_child_autofree(node)
	await get_tree().process_frame
	Events.heal_shown.emit(node, 7.0)
	var toasters := _toaster_children()
	assert_eq(toasters.size(), 1, "a heal reveal becomes one toaster")
	var vbox := toasters[0].get_node("VBoxContainer") as VBoxContainer
	var toast := vbox.get_child(0) as FloaterToast
	assert_eq(toast.label.text, "+7", "rounded heal amount with + prefix")


func test_attack_heal_model_signal_floats_nothing() -> void:
	# #481/#482: an attack heal (source is HealInstance) is shown by heal_shown on
	# the arrival clock. skill_node_healed at model-mutation time must NOT float
	# it over a node the projectile hasn't reached.
	var node := _SKILL_NODE_SCENE.instantiate() as SkillNode
	add_child_autofree(node)
	await get_tree().process_frame
	var heal := HealInstance.new()
	heal.amount = 7.0
	heal.target = node
	Events.skill_node_healed.emit(node, 7.0, heal)
	assert_eq(_toaster_children().size(), 0,
			"an attack heal's model mutation alone must not float a number")


func test_non_attack_heal_still_floats_immediately() -> void:
	# #481/#482: non-attack heals (turn regen, heal aura) have no arrival schedule —
	# their +N keeps floating at model time, as before.
	var node := _SKILL_NODE_SCENE.instantiate() as SkillNode
	add_child_autofree(node)
	await get_tree().process_frame
	Events.skill_node_healed.emit(node, 7.0, null)
	var toasters := _toaster_children()
	assert_eq(toasters.size(), 1, "a regen/aura heal floats immediately")
	var vbox := toasters[0].get_node("VBoxContainer") as VBoxContainer
	var toast := vbox.get_child(0) as FloaterToast
	assert_eq(toast.label.text, "+7", "same +N display")
