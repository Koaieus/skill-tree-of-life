class_name MassActionConfirmPanel
extends Control

## Modal confirm panel for a pending [MassActionRequest] (distant-allocate-path
## or would-island-deallocate-cascade). Same MODAL-by-design shape as
## [LootPicker]: pauses the tree while open so PlayerInputController's D-key
## `_unhandled_input` channel can't fire underneath it, `process_mode = ALWAYS`
## so its own buttons/Esc/right-click still work paused.
##
## Unlike LootPicker there's always exactly one thing to decide (confirm or
## cancel the whole batch), so there's no card-selection state — just a
## per-node breakdown list built fresh each `present()`.

@onready var _title: Label = %Title
@onready var _node_list: VBoxContainer = %NodeList
@onready var _footer: Label = %Footer
@onready var _confirm_button: Button = %ConfirmButton
@onready var _cancel_button: Button = %CancelButton

var _input_ctl: PlayerInputController = null
var _allocation_system: AllocationSystem = null


func _ready() -> void:
	hide()
	_confirm_button.pressed.connect(_on_confirm_pressed)
	_cancel_button.pressed.connect(_on_cancel_pressed)


func bind(input_ctl: PlayerInputController, allocation_system: AllocationSystem) -> void:
	_input_ctl = input_ctl
	_allocation_system = allocation_system
	if not input_ctl.mass_action_pending_changed.is_connected(_on_pending_changed):
		input_ctl.mass_action_pending_changed.connect(_on_pending_changed)


func _on_pending_changed(request: MassActionRequest) -> void:
	if request == null:
		hide()
		get_tree().paused = false
		return
	_present(request)


func _present(request: MassActionRequest) -> void:
	for c in _node_list.get_children():
		c.queue_free()

	match request.verb:
		MassActionRequest.Verb.ALLOCATE:
			_present_allocate(request)
		MassActionRequest.Verb.DEALLOCATE:
			_present_deallocate(request)

	show()
	get_tree().paused = true


func _present_allocate(request: MassActionRequest) -> void:
	_title.text = "ALLOCATE PATH"
	var affordable := request.affordable_count
	# nodes[0] is the already-owned frontier anchor — never listed, it's not
	# being allocated. nodes[1..affordable] is the paid-for prefix; anything
	# past that (up to the clicked target) is shown dimmed as PENDING_REMAINDER.
	for i in range(1, request.nodes.size()):
		var reached := i <= affordable
		_add_node_block(request.nodes[i], reached)

	var reaches_target := affordable >= request.nodes.size() - 1
	var sp_line := "%d Skill Point%s" % [affordable, "" if affordable == 1 else "s"]
	if not reaches_target:
		sp_line += "  —  reaches %d of %d nodes toward target" % [affordable, request.nodes.size() - 1]
	_footer.text = sp_line
	_confirm_button.disabled = affordable < 1
	_confirm_button.text = "ALLOCATE"


func _present_deallocate(request: MassActionRequest) -> void:
	_title.text = "DEALLOCATE CASCADE"
	for n in request.nodes:
		_add_node_block(n, true)

	var dp_cost := request.nodes.size()
	var sp_refund := 0
	for n in request.nodes:
		sp_refund += n.allocation_level
	var can_afford := _can_afford_dealloc(request)
	_footer.text = "%d Deallocation Point%s  —  refunds %d Skill Point%s" % [
			dp_cost, "" if dp_cost == 1 else "s", sp_refund, "" if sp_refund == 1 else "s"]
	_confirm_button.disabled = not can_afford
	_confirm_button.text = "DEALLOCATE"


func _can_afford_dealloc(request: MassActionRequest) -> bool:
	if _allocation_system == null:
		return false
	return _allocation_system.can_deallocate_set(request.nodes, request.entity)


## One block per node: display name + its modifiers, each on its own line,
## an [HSeparator] after ([code]<hr>[/code] per the design ask). [param reached]
## dims the block when it's past the SP-affordable prefix (allocate only).
func _add_node_block(node: SkillNode, reached: bool) -> void:
	var block := VBoxContainer.new()
	block.modulate = Color(1, 1, 1, 1) if reached else Color(1, 1, 1, 0.4)

	var name_label := Label.new()
	name_label.text = node.get_display_name()
	name_label.add_theme_font_size_override("font_size", 16)
	block.add_child(name_label)

	for leaf in StatModifier.flatten_all(node.modifiers):
		var mod_label := Label.new()
		mod_label.text = leaf.format()
		mod_label.add_theme_font_size_override("font_size", 13)
		block.add_child(mod_label)

	_node_list.add_child(block)
	_node_list.add_child(HSeparator.new())


func _on_confirm_pressed() -> void:
	if _input_ctl == null:
		return
	get_tree().paused = false
	_input_ctl.confirm_mass_action()


func _on_cancel_pressed() -> void:
	if _input_ctl == null:
		return
	get_tree().paused = false
	_input_ctl.cancel_mass_action()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_cancel"):
		_on_cancel_pressed()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
		_on_cancel_pressed()
		get_viewport().set_input_as_handled()
