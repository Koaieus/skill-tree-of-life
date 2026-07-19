extends GutTest
## DirectoryCardList (#253): scans a folder into radio-toggle cards and emits the
## picked resource. Uses the spell defs folder as a stable real fixture.

const _SCENE := "res://addons/sandbox_host/components/directory_card_list.tscn"
const _SPELL_DIR := "res://attack/spell/defs"


func _make(dir: String, recursive := false) -> DirectoryCardList:
	var list: DirectoryCardList = load(_SCENE).instantiate()
	list.directory = dir
	list.recursive = recursive
	add_child(list)
	return list


func test_renders_one_card_per_matching_file() -> void:
	var list := _make(_SPELL_DIR)
	await get_tree().process_frame
	var cards: VBoxContainer = list.get_node(^"%Cards")
	assert_gt(cards.get_child_count(), 0, "should list the spell defs")
	assert_eq(cards.get_child_count(), list.entries().size(), "one card per entry")
	list.queue_free()


func test_cards_are_a_single_selection_radio_group() -> void:
	var list := _make(_SPELL_DIR)
	await get_tree().process_frame
	var cards: VBoxContainer = list.get_node(^"%Cards")
	var a: Button = cards.get_child(0)
	var b: Button = cards.get_child(1)
	a.button_pressed = true
	b.button_pressed = true
	assert_false(a.button_pressed, "selecting b must release a (radio group)")
	assert_true(b.button_pressed)
	list.queue_free()


func test_selecting_emits_selected_resource() -> void:
	var list := _make(_SPELL_DIR)
	await get_tree().process_frame
	watch_signals(list)
	var cards: VBoxContainer = list.get_node(^"%Cards")
	var first: Button = cards.get_child(0)
	first.button_pressed = true
	assert_signal_emitted(list, "selected")
	assert_signal_emitted(list, "selected_resource")
	list.queue_free()


func test_recursive_finds_nested_defs() -> void:
	# procgen configs live nested under a preset folder.
	var flat := _make("res://procgen/presets")
	await get_tree().process_frame
	var recursive := _make("res://procgen/presets", true)
	await get_tree().process_frame
	assert_gt(recursive.entries().size(), flat.entries().size(),
		"recursive scan should reach nested preset .tres a flat scan misses")
	flat.queue_free()
	recursive.queue_free()
