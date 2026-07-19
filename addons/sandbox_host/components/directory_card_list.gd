@tool
class_name DirectoryCardList
extends ScrollContainer
## A dumb, composable directory browser: scans `directory` (optionally recursive)
## for files whose extension is in `extensions`, renders one radio-toggle card per
## entry, and emits `selected` / `selected_resource` when one is picked. It knows
## nothing about tabs — a `SandboxLiveTab` drops one into its `%Sidebar` and the
## base self-wires `selected_resource → load_object` (see `_wire_sidebar`). `@tool`
## so the list populates from the exported directory while editing the tab scene.

signal selected(path: String)
signal selected_resource(res: Resource)

@export_dir var directory: String = "":
	set(value):
		directory = value
		_rebuild()
## Extensions to list, e.g. `[".tres"]` or `[".tscn"]`. Match is a suffix test.
@export var extensions: PackedStringArray = PackedStringArray([".tres"]):
	set(value):
		extensions = value
		_rebuild()
## Descend into subdirectories (defs are often nested under a preset folder).
@export var recursive: bool = false:
	set(value):
		recursive = value
		_rebuild()

@onready var _cards: VBoxContainer = %Cards
var _group := ButtonGroup.new()


func _ready() -> void:
	_rebuild()


## Sorted resource paths currently listed — for callers / tests.
func entries() -> PackedStringArray:
	return _scan()


## Programmatically press the card for `path` (no-op if it isn't listed).
func select_path(path: String) -> void:
	if _cards == null:
		return
	for card in _cards.get_children():
		if card is Button and card.tooltip_text == path:
			card.button_pressed = true
			return


func _rebuild() -> void:
	if _cards == null:
		return  # a setter fired before _ready wired %Cards; _ready rebuilds
	for c in _cards.get_children():
		c.queue_free()
	for path in _scan():
		var card := Button.new()
		card.toggle_mode = true
		card.button_group = _group
		card.text = path.get_file()
		card.tooltip_text = path
		card.alignment = HORIZONTAL_ALIGNMENT_LEFT
		card.toggled.connect(_on_card_toggled.bind(path))
		_cards.add_child(card)


func _scan() -> PackedStringArray:
	var out := PackedStringArray()
	_scan_dir(directory, out)
	out.sort()
	return out


func _scan_dir(path: String, out: PackedStringArray) -> void:
	if path.is_empty():
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for f in dir.get_files():
		for ext in extensions:
			if f.ends_with(ext):
				out.append(path.path_join(f))
				break
	if recursive:
		for sub in dir.get_directories():
			_scan_dir(path.path_join(sub), out)


func _on_card_toggled(pressed: bool, path: String) -> void:
	if not pressed:
		return
	selected.emit(path)
	if ResourceLoader.exists(path):
		selected_resource.emit(load(path))
