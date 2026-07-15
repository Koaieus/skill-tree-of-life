extends GutTest

## LootPicker — the pick-N-from-M loot chooser (#173). Covers the interactive
## branch the LootSystem tests can't reach (they run headless, so relics there
## always take the auto-resolve path). Drives the picker like the player would:
## build cards, toggle selections, confirm → `LootPickRequest.resolve` fires with
## exactly the chosen subset. Also pins the overshoot lock (can't pick > N).

const _PICKER_SCENE := preload("res://ui/loot_picker/loot_picker.tscn")

var _picker: LootPicker


func before_each() -> void:
	_picker = _PICKER_SCENE.instantiate()
	add_child_autofree(_picker)


func after_each() -> void:
	# present() pauses the tree (modal); tests that don't confirm must release it
	# so the paused state can't leak into the rest of the GUT run.
	get_tree().paused = false


func _mk_mod(id: StringName, v: float) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = id
	m.operation = StatModifier.Operation.ADD_BASE
	m.value = v
	return m


func _request(candidates: Array[StatModifier], pick: int, sink: Array) -> LootPickRequest:
	return LootPickRequest.new(null, candidates, pick, func(chosen): sink.append_array(chosen))


func test_present_builds_a_card_per_candidate() -> void:
	var cands: Array[StatModifier] = [_mk_mod(&"armor", 1), _mk_mod(&"armor", 2), _mk_mod(&"armor", 3)]
	var sink: Array = []
	_picker.present(_request(cands, 1, sink))
	assert_true(_picker.visible, "picker shows on present")
	assert_eq(_picker._cards.size(), 3, "one card per candidate (M)")


func test_confirm_disabled_until_exactly_n_selected() -> void:
	var cands: Array[StatModifier] = [_mk_mod(&"armor", 1), _mk_mod(&"armor", 2), _mk_mod(&"armor", 3)]
	var sink: Array = []
	_picker.present(_request(cands, 2, sink))
	assert_true(_picker._confirm_button.disabled, "confirm off with 0 selected")
	_picker._cards[0].button_pressed = true
	_picker._cards[0].toggled.emit(true)
	assert_true(_picker._confirm_button.disabled, "confirm off with 1 of 2 selected")
	_picker._cards[1].button_pressed = true
	_picker._cards[1].toggled.emit(true)
	assert_false(_picker._confirm_button.disabled, "confirm on at exactly N")


func test_selecting_n_locks_remaining_cards() -> void:
	var cands: Array[StatModifier] = [_mk_mod(&"armor", 1), _mk_mod(&"armor", 2), _mk_mod(&"armor", 3)]
	var sink: Array = []
	_picker.present(_request(cands, 1, sink))
	_picker._cards[0].button_pressed = true
	_picker._cards[0].toggled.emit(true)
	assert_true(_picker._cards[1].disabled, "unpicked cards lock once N reached")
	assert_true(_picker._cards[2].disabled, "unpicked cards lock once N reached")
	assert_false(_picker._cards[0].disabled, "the picked card stays togglable to swap")


func test_confirm_resolves_with_the_chosen_subset() -> void:
	var a := _mk_mod(&"armor", 1)
	var b := _mk_mod(&"strength", 2)
	var c := _mk_mod(&"dexterity", 3)
	var cands: Array[StatModifier] = [a, b, c]
	var sink: Array = []
	var req := _request(cands, 2, sink)
	_picker.present(req)
	_picker._cards[0].button_pressed = true
	_picker._cards[0].toggled.emit(true)
	_picker._cards[2].button_pressed = true
	_picker._cards[2].toggled.emit(true)
	_picker._on_confirm()
	assert_true(req.is_resolved(), "confirm resolves the request")
	assert_eq(sink.size(), 2, "resolver receives exactly N mods")
	assert_true(sink.has(a) and sink.has(c), "resolver receives the picked candidates")
	assert_false(sink.has(b), "unpicked candidate is excluded")
	assert_false(_picker.visible, "picker hides after confirm")


## #183: a CompositeStatModifier candidate is ONE card whose body lists every
## bundled leaf — the player sees the whole pack, picks it all-or-nothing.
func test_composite_candidate_is_one_card_listing_its_leaves() -> void:
	var bundle := CompositeStatModifier.new()
	bundle.children = [_mk_mod(&"deallocation_points", 2), _mk_mod(&"skill_points", -1)]
	var cands: Array[StatModifier] = [bundle, _mk_mod(&"armor", 5)]
	var sink: Array = []
	_picker.present(_request(cands, 1, sink))
	assert_eq(_picker._cards.size(), 2, "the bundle is a single card, not one per leaf")
	var text: String = _picker._cards[0].text
	assert_true(text.contains("+2") and text.contains("-1"),
			"the bundle card lists both leaf contributions")
	assert_true(text.contains("\n"), "leaves are stacked on separate lines")


func test_confirm_resolves_a_composite_as_a_single_unit() -> void:
	var bundle := CompositeStatModifier.new()
	bundle.children = [_mk_mod(&"deallocation_points", 2), _mk_mod(&"skill_points", -1)]
	var plain := _mk_mod(&"armor", 5)
	var cands: Array[StatModifier] = [bundle, plain]
	var sink: Array = []
	var req := _request(cands, 1, sink)
	_picker.present(req)
	_picker._cards[0].button_pressed = true
	_picker._cards[0].toggled.emit(true)
	_picker._on_confirm()
	assert_eq(sink.size(), 1, "one pick == the whole bundle, not its leaf count")
	assert_true(sink.has(bundle), "the composite is resolved whole (all-or-nothing)")
	assert_false(sink.has(plain))


func test_resolve_is_idempotent() -> void:
	var cands: Array[StatModifier] = [_mk_mod(&"armor", 1), _mk_mod(&"armor", 2)]
	var sink: Array = []
	var req := _request(cands, 1, sink)
	req.resolve([cands[0]])
	req.resolve([cands[1]])  # second call is a no-op
	assert_eq(sink.size(), 1, "resolve fires the resolver at most once")
