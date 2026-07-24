extends GutTest

## HudRoot's pending-pick queue (#204, acceptance #7 in the swarm spec: "two
## picks on one death"). A kill can fire BOTH the dust pick and the spell
## draft synchronously — both modals pause the tree, so HudRoot must present
## them one at a time: dust first, then the spell draft, the next only once
## the current picker's `closed` signal fires.
##
## Drives HudRoot directly (not through LootSystem) so this is a focused test
## of the queue/serialization logic itself, independent of the loot draw.

const _HUD_SCENE := preload("res://ui/hud/hud_root.tscn")

var _hud: HudRoot
var _player: Entity


func before_each() -> void:
	_hud = _HUD_SCENE.instantiate()
	add_child_autofree(_hud)
	await get_tree().process_frame

	_player = autofree(Entity.new())
	# HudRoot filters pick requests to the bound player; compose() isn't run
	# (no GameRoot in this fixture), so set the field directly — GDScript has
	# no true privacy, and this is the field the handlers read.
	_hud._player = _player


func after_each() -> void:
	# Both pickers pause the tree while open; a test that doesn't confirm must
	# release it so paused state can't leak into the rest of the GUT run.
	get_tree().paused = false


func _mk_stat_mod(id: StringName, v: float) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = id
	m.operation = StatModifier.Operation.ADD_BASE
	m.value = v
	return m


func _mk_spell(spell_name: String) -> SpellDef:
	var s := SpellDef.new()
	s.name = spell_name
	return s


func _dust_request(sink: Array) -> LootPickRequest:
	var cands: Array[StatModifier] = [_mk_stat_mod(&"armor", 1)]
	return LootPickRequest.new(_player, cands, 1, func(chosen): sink.append_array(chosen))


func _spell_request(sink: Array) -> SpellLootRequest:
	var cands: Array[SpellDef] = [_mk_spell("Bolt")]
	return SpellLootRequest.new(_player, cands, 1, func(chosen): sink.append_array(chosen))


func test_dust_pick_presents_immediately() -> void:
	var sink: Array = []
	Events.loot_pick_requested.emit(_dust_request(sink))
	assert_true(_hud.loot_picker.visible, "dust picker presents on request")


func test_spell_draft_queues_behind_a_pending_dust_pick() -> void:
	var dust_sink: Array = []
	var spell_sink: Array = []
	# Both fire synchronously in the same stack, exactly as LootSystem does
	# (_drop_skill_dust before _award_spell_loot).
	Events.loot_pick_requested.emit(_dust_request(dust_sink))
	Events.spell_loot_requested.emit(_spell_request(spell_sink))

	assert_true(_hud.loot_picker.visible, "dust picker presents first")
	assert_false(_hud.spell_loot_picker.visible, "spell draft stays queued behind it")


func test_spell_draft_presents_once_dust_pick_closes() -> void:
	var dust_sink: Array = []
	var spell_sink: Array = []
	Events.loot_pick_requested.emit(_dust_request(dust_sink))
	Events.spell_loot_requested.emit(_spell_request(spell_sink))

	# Confirm the dust pick, like the player would.
	_hud.loot_picker._cards[0].button_pressed = true
	_hud.loot_picker._cards[0].toggled.emit(true)
	_hud.loot_picker._on_confirm()

	assert_false(_hud.loot_picker.visible, "dust picker closes")
	assert_true(_hud.spell_loot_picker.visible, "spell draft presents once the queue drains")
	assert_eq(dust_sink.size(), 1, "dust resolver fired with the chosen mod")


func test_both_requests_resolve_in_order() -> void:
	var dust_sink: Array = []
	var spell_sink: Array = []
	var spell_req := _spell_request(spell_sink)
	Events.loot_pick_requested.emit(_dust_request(dust_sink))
	Events.spell_loot_requested.emit(spell_req)

	_hud.loot_picker._cards[0].button_pressed = true
	_hud.loot_picker._cards[0].toggled.emit(true)
	_hud.loot_picker._on_confirm()

	_hud.spell_loot_picker._cards[0].button_pressed = true
	_hud.spell_loot_picker._cards[0].toggled.emit(true)
	_hud.spell_loot_picker._on_confirm()

	assert_false(_hud.spell_loot_picker.visible, "spell draft closes on confirm")
	assert_eq(spell_sink.size(), 1, "spell resolver fired with the chosen spell")
	assert_true(spell_req.is_resolved())
	assert_false(get_tree().paused, "board unpaused once both modals have closed")


func test_requests_for_a_different_collector_are_ignored() -> void:
	var other := Entity.new()
	autofree(other)
	var sink: Array = []
	var cands: Array[SpellDef] = [_mk_spell("NotForUs")]
	var req := SpellLootRequest.new(other, cands, 1, func(chosen): sink.append_array(chosen))
	Events.spell_loot_requested.emit(req)
	assert_false(_hud.spell_loot_picker.visible, "request for a non-player collector is ignored")
	assert_false(req.handled, "HudRoot never claims a request that isn't the player's")
