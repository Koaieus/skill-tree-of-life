extends GutTest

## ToastCell — extracted toast-preview cell (#265).
## Composition-only: asserts the scene instantiates with its expected
## children and that the tint/label_text exports apply to them.

const _TOAST_CELL := preload("res://addons/toast_sandbox/toast_cell.tscn")

var _cell: ToastCell


func after_each() -> void:
	if is_instance_valid(_cell):
		_cell.queue_free()


func test_instantiates_expected_children() -> void:
	_cell = _TOAST_CELL.instantiate()
	assert_true(_cell is SubViewportContainer, "root must be a SubViewportContainer")

	var viewport := _cell.get_node_or_null("Viewport")
	assert_not_null(viewport, "expected a Viewport child")
	assert_true(viewport is SubViewport)

	var background := viewport.get_node_or_null("Background")
	assert_not_null(background, "expected a Background ColorRect")
	assert_true(background is ColorRect)

	var label := viewport.get_node_or_null("Label")
	assert_not_null(label, "expected a Label child")
	assert_true(label is Label)

	var anchor := viewport.get_node_or_null("ToastAnchor")
	assert_not_null(anchor, "expected a ToastAnchor Control")
	assert_true(anchor is Control)


func test_tint_and_label_text_apply_on_ready() -> void:
	_cell = _TOAST_CELL.instantiate()
	_cell.tint = Color(0.9, 0.1, 0.1, 1.0)
	_cell.label_text = "Burn"
	add_child_autofree(_cell)

	var background: ColorRect = _cell.get_node("Viewport/Background")
	var label: Label = _cell.get_node("Viewport/Label")
	assert_eq(background.color, Color(0.9, 0.1, 0.1, 1.0))
	assert_eq(label.text, "Burn")


func test_ready_spawns_a_toaster() -> void:
	_cell = _TOAST_CELL.instantiate()
	add_child_autofree(_cell)

	assert_not_null(_cell.toaster)
	assert_true(_cell.toaster is FloaterToaster)
	assert_eq(_cell.toaster.get_parent(), _cell.get_node("Viewport/ToastAnchor"))


func test_get_or_remake_toaster_recreates_when_freed() -> void:
	_cell = _TOAST_CELL.instantiate()
	add_child_autofree(_cell)

	var original := _cell.toaster
	original.queue_free()
	await wait_frames(1)

	var remade := _cell.get_or_remake_toaster()
	assert_not_null(remade)
	assert_ne(remade, original)
