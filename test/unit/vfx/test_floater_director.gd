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
	_renderer.clock.manual = true


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
	Events.skill_node_damaged.emit(node, 7.0, null)
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
	Events.skill_node_damaged.emit(node, 0.0, null)
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
	_renderer.clock.advance(fade_in * 1.1)
	_renderer.clock.advance(fade_in * 1.1)
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
	_renderer.clock.advance(fade_in * 1.25)
	_renderer.clock.advance(fade_in * 1.25)
	assert_eq(vbox.get_child_count(), 3, "first + 2 queued; oldest dropped")


func test_model_damage_floats_the_number() -> void:
	# #504 INVERTS #482. The damage number is still a reveal like the HP bar and
	# the tint — but under design B the model itself mutates on the reveal
	# clock, so `skill_node_damaged` fires exactly when the arrow lands. Routing
	# through a separate `damage_shown` emitted by each coordinator would be a
	# second clock nominally equal to this one, which is the drift this issue
	# removed.
	var node := _SKILL_NODE_SCENE.instantiate() as SkillNode
	add_child_autofree(node)
	await get_tree().process_frame
	Events.skill_node_damaged.emit(node, 7.0, null)
	var toasters := _toaster_children()
	assert_eq(toasters.size(), 1, "the model's own damage signal floats the number")
	var vbox := toasters[0].get_node("VBoxContainer") as VBoxContainer
	assert_eq((vbox.get_child(0) as FloaterToast).label.text, "7",
			"rounded damage amount")


func test_attack_heal_floats_on_the_model_signal() -> void:
	# #504 INVERTS #481/#482: an attack heal (source is HealInstance) used to be
	# held back here and re-announced on `heal_shown`. Its model mutation now
	# happens at its own `arrival_time`, so there is nothing left distinguishing
	# it from turn regen or a heal aura — one path, one clock.
	var node := _SKILL_NODE_SCENE.instantiate() as SkillNode
	add_child_autofree(node)
	await get_tree().process_frame
	var heal := HealInstance.new()
	heal.amount = 7.0
	heal.target = node
	Events.skill_node_healed.emit(node, 7.0, heal)
	var toasters := _toaster_children()
	assert_eq(toasters.size(), 1, "an attack heal floats on its own model signal")
	var vbox := toasters[0].get_node("VBoxContainer") as VBoxContainer
	assert_eq((vbox.get_child(0) as FloaterToast).label.text, "+7",
			"rounded heal amount with + prefix")


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


## The blade sweep cue: a contact sped up by Heat or slowed by Cold says so on
## its damage floater, as a suffix beside the number.
func _damage_toast(sweep_factor: float) -> FloaterToast:
	var node := _SKILL_NODE_SCENE.instantiate() as SkillNode
	add_child_autofree(node)
	await get_tree().process_frame
	var hit := DamageInstance.new()
	hit.target = node
	hit.sweep_factor = sweep_factor
	Events.skill_node_damaged.emit(node, 7.0, hit)
	var toasters := _toaster_children()
	assert_eq(toasters.size(), 1, "one damage toaster")
	if toasters.is_empty():
		return null
	var vbox := toasters[0].get_node("VBoxContainer") as VBoxContainer
	return vbox.get_child(0) as FloaterToast


func test_a_contact_sped_up_by_heat_floats_the_fast_cue() -> void:
	var toast: FloaterToast = await _damage_toast(1.3)
	assert_eq(toast.label.text, "7", "the number is unchanged")
	assert_true(toast.suffix.visible, "the sweep cue shows")
	assert_eq(toast.suffix.text, _director.sweep_fast_text, "sped up reads fast")


func test_a_contact_slowed_by_cold_floats_the_slow_cue() -> void:
	var toast: FloaterToast = await _damage_toast(0.7)
	assert_true(toast.suffix.visible, "the sweep cue shows")
	assert_eq(toast.suffix.text, _director.sweep_slow_text, "slowed reads slow")


func test_an_unswept_hit_floats_no_cue() -> void:
	var toast: FloaterToast = await _damage_toast(1.0)
	assert_false(toast.suffix.visible, "a factor of 1 carries no cue")


## The floater's source on the live replay is the record's rebuilt plain
## [DamageInstance]: the cue survives capture and rebuild.
func test_the_sweep_cue_survives_the_record() -> void:
	var graph := TestWorld.create(self).graph
	var node := _SKILL_NODE_SCENE.instantiate() as SkillNode
	graph.add_skill_node(node)
	await get_tree().process_frame
	var outcome := AttackOutcome.new()
	for f: float in [0.75, 1.0]:
		var hit := DamageInstance.new()
		hit.target = node
		hit.amount = 7.0
		hit.effective_amount = 7.0
		hit.sweep_factor = f
		outcome.hits.append(hit)
	var rebuilt := AttackRecord.rebuild(AttackRecord.capture(outcome, graph), graph)
	assert_eq(rebuilt.hits.size(), 2, "both hits rebuild")
	assert_eq(rebuilt.hits[0].sweep_factor, 0.75, "a slowed contact's factor is recorded")
	assert_eq(rebuilt.hits[1].sweep_factor, 1.0, "an unswept hit rebuilds at 1")
	var plain := AttackOutcome.new()
	var unswept := DamageInstance.new()
	unswept.target = node
	plain.hits.append(unswept)
	assert_false(AttackRecord.capture(plain, graph).has(AttackRecord.KEY_HIT_SWEEP),
			"a record with no swept contact writes no sweep key")
