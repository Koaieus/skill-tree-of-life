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


func _body() -> LootPickerBody:
	return _picker._body as LootPickerBody


func _mk_mod(id: StringName, v: float) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = id
	m.operation = StatModifier.Operation.ADD_BASE
	m.value = v
	return m


func _request(candidates: Array[StatModifier], sink: Array) -> LootPickRequest:
	return LootPickRequest.new(null, candidates, func(chosen): sink.append_array(chosen))


func test_present_builds_a_card_per_candidate() -> void:
	var cands: Array[StatModifier] = [_mk_mod(&"armor", 1), _mk_mod(&"armor", 2), _mk_mod(&"armor", 3)]
	var sink: Array = []
	_picker.present(_request(cands, sink))
	assert_true(_picker.visible, "picker shows on present")
	assert_eq(_body()._cards.size(), 3, "one card per candidate (M)")


func test_confirm_disabled_until_something_is_selected() -> void:
	var cands: Array[StatModifier] = [_mk_mod(&"armor", 1), _mk_mod(&"armor", 2), _mk_mod(&"armor", 3)]
	var sink: Array = []
	_picker.present(_request(cands, sink))
	assert_true(_picker._confirm_button.disabled, "confirm off with nothing selected")
	_body()._cards[0].button_pressed = true
	_body()._cards[0].toggled.emit(true)
	assert_false(_picker._confirm_button.disabled, "confirm on as soon as one is picked")


## A draw is ALWAYS a pick-one (owner call 2026-08-22 — the loot shape is
## "pick 1 out of M, N times", and N is rounds, not picks per draw). So the
## cards are a plain ButtonGroup: picking a different card auto-deselects the
## old one in a single click, no disable-then-pick-again dance, and
## `allow_unpress` lets the selected card drop back to nothing.
func test_a_draw_is_a_button_group_with_natural_exclusive_toggle() -> void:
	var cands: Array[StatModifier] = [_mk_mod(&"armor", 1), _mk_mod(&"armor", 2), _mk_mod(&"armor", 3)]
	var sink: Array = []
	_picker.present(_request(cands, sink))

	_body()._cards[0].button_pressed = true
	_body()._cards[0].toggled.emit(true)
	assert_false(_body()._cards[1].disabled, "no lock needed — the group makes exclusivity automatic")
	assert_true(_picker._confirm_button.disabled == false, "confirm valid with 1 of 1 selected")

	# One click on a different card switches the pick — no need to deselect first.
	_body()._cards[1].button_pressed = true
	_body()._cards[1].toggled.emit(true)
	assert_false(_body()._cards[0].button_pressed, "ButtonGroup auto-deselects the previous pick")
	assert_true(_body()._cards[1].button_pressed)

	# allow_unpress: clicking the selected card again drops the pick entirely.
	_body()._cards[1].button_pressed = false
	_body()._cards[1].toggled.emit(false)
	assert_false(_body()._cards[1].button_pressed)
	assert_true(_picker._confirm_button.disabled, "confirm off again with nothing selected")


func test_confirm_resolves_with_the_chosen_candidate() -> void:
	var a := _mk_mod(&"armor", 1)
	var b := _mk_mod(&"strength", 2)
	var c := _mk_mod(&"dexterity", 3)
	var cands: Array[StatModifier] = [a, b, c]
	var sink: Array = []
	var req := _request(cands, sink)
	_picker.present(req)
	_body()._cards[2].button_pressed = true
	_body()._cards[2].toggled.emit(true)
	_picker._on_confirm()
	assert_true(req.is_resolved(), "confirm resolves the request")
	assert_eq(sink.size(), 1, "a draw grants exactly one modifier")
	assert_true(sink.has(c), "resolver receives the picked candidate")
	assert_false(sink.has(a) or sink.has(b), "unpicked candidates are excluded")
	assert_false(_picker.visible, "picker hides after confirm")


## #183: a CompositeStatModifier candidate is ONE card whose body lists every
## bundled leaf — the player sees the whole pack, picks it all-or-nothing.
func test_composite_candidate_is_one_card_listing_its_leaves() -> void:
	var bundle := CompositeStatModifier.new()
	bundle.children = [_mk_mod(&"deallocation_points", 2), _mk_mod(&"skill_points", -1)]
	var cands: Array[StatModifier] = [bundle, _mk_mod(&"armor", 5)]
	var sink: Array = []
	_picker.present(_request(cands, sink))
	assert_eq(_body()._cards.size(), 2, "the bundle is a single card, not one per leaf")
	var text: String = _body()._cards[0].text
	assert_true(text.contains("+2") and text.contains("-1"),
			"the bundle card lists both leaf contributions")
	assert_true(text.contains("\n"), "leaves are stacked on separate lines")


func test_confirm_resolves_a_composite_as_a_single_unit() -> void:
	var bundle := CompositeStatModifier.new()
	bundle.children = [_mk_mod(&"deallocation_points", 2), _mk_mod(&"skill_points", -1)]
	var plain := _mk_mod(&"armor", 5)
	var cands: Array[StatModifier] = [bundle, plain]
	var sink: Array = []
	var req := _request(cands, sink)
	_picker.present(req)
	_body()._cards[0].button_pressed = true
	_body()._cards[0].toggled.emit(true)
	_picker._on_confirm()
	assert_eq(sink.size(), 1, "one pick == the whole bundle, not its leaf count")
	assert_true(sink.has(bundle), "the composite is resolved whole (all-or-nothing)")
	assert_false(sink.has(plain))


func test_resolve_is_idempotent() -> void:
	var cands: Array[StatModifier] = [_mk_mod(&"armor", 1), _mk_mod(&"armor", 2)]
	var sink: Array = []
	var req := _request(cands, sink)
	req.resolve([cands[0]])
	req.resolve([cands[1]])  # second call is a no-op
	assert_eq(sink.size(), 1, "resolve fires the resolver at most once")


## #486: present()/confirm() freeze/unfreeze the bound PlayerInputController's
## input channel instead of pausing the whole SceneTree.
func test_present_freezes_input_and_confirm_unfreezes_it() -> void:
	var input_ctl := PlayerInputController.new()
	add_child_autofree(input_ctl)
	_picker.bind(input_ctl)

	var cands: Array[StatModifier] = [_mk_mod(&"armor", 1)]
	var sink: Array = []
	_picker.present(_request(cands, sink))
	assert_true(input_ctl._input_frozen, "present() freezes the input channel")
	assert_false(get_tree().paused, "the SceneTree itself is never paused")

	_body()._cards[0].button_pressed = true
	_body()._cards[0].toggled.emit(true)
	_picker._on_confirm()
	assert_false(input_ctl._input_frozen, "confirm unfreezes the input channel")


## The inherited scene overrides ConfirmButton by NODE PATH — a path that moved
## when [ModalBase] grew a ButtonRow for the Cancel button. A stale path is a
## silently dropped override, not a load failure, so pin the authored label.
func test_the_inherited_scene_still_authors_its_own_confirm_label() -> void:
	assert_eq(_picker._confirm_button.text, "CLAIM", "LootPicker claims, it does not CONFIRM")
	assert_false(_picker._cancel_button.visible, "a loot pick is a must-answer")
