@tool
class_name CapacityBlips
extends GridContainer
## N-of-max pip display — resolves #87 slice 2 ("empty mana crystal"
## blips). Used for blade-size pips and the Magic spell bar's degree
## icon. Instances CapacityPip children (leaf-level programmatic
## composition per scene-composition.md — the count is data-driven, not
## a fixed structural tree, so this is the sanctioned case-by-case use of
## code composition rather than a hand-authored fixed scene).

const PIP_SCENE := preload("res://ui/gauges/capacity_pip.tscn")

@export var max_count: int = 3:
	set(v):
		max_count = max(0, v)
		_rebuild()

@export var count: int = 0:
	set(v):
		count = clamp(v, 0, max_count)
		_apply_state()

@export var fill_color: Color = Color(0.62, 0.21, 0.21, 1.0):
	set(v):
		fill_color = v
		_apply_state()

@export var empty_color: Color = Color(1.0, 1.0, 1.0, 0.08):
	set(v):
		empty_color = v
		_apply_state()

@export var pip_size: Vector2 = Vector2(13, 13):
	set(v):
		pip_size = v
		for pip in get_children():
			pip.custom_minimum_size = pip_size

## Indices (0-based) currently selection-highlighted, e.g. blade nodes
## picked in the Melee builder. Cleared/rebuilt on every count() change.
var highlighted_indices: Array[int] = []:
	set(v):
		highlighted_indices = v
		_apply_state()

## Per-filled-pip color override (#406) — index i colors the i'th filled pip
## (0..count-1); shorter than `count` falls back to `fill_color` for the
## remainder. Empty (the default) keeps the single-color behavior. Lets one
## blip row mix budget "kinds" sharing the same pool (e.g. blade-member
## spend vs. a temp Spike vs. a temp Clamp) while still reading as one
## N-of-max gauge.
var segment_colors: Array[Color] = []:
	set(v):
		segment_colors = v
		_apply_state()

func _ready() -> void:
	_rebuild()

func _rebuild() -> void:
	# Immediate free (not queue_free): the same names get reused below in the
	# same call, and a deferred free leaves the old node parented (still
	# holding its name slot) until frame end, which previously produced
	# "Children name does not match parent name in hashtable" errors when
	# max_count changed more than once before the deferred frees flushed.
	for child in get_children():
		remove_child(child)
		child.free()
	for i in max_count:
		var pip: CapacityPip = PIP_SCENE.instantiate()
		pip.name = "CapacityPip_%02d" % i
		pip.custom_minimum_size = pip_size
		add_child(pip)
		# Deliberately NOT stamping pip.owner in the editor: doing so let the
		# editor bake these script-created pips into any consuming scene as
		# persistent "editable children" overrides, which then collided with
		# this same _rebuild() teardown on the next load (mismatched pip
		# count/identity vs. what the script expects). Pips render fine in
		# the editor viewport without an owner — they're just not individually
		# selectable in the Scene dock, which is correct for a script-owned,
		# count-driven leaf composition (see class doc above).
	_apply_state()

func _apply_state() -> void:
	var children := get_children()
	for i in children.size():
		var pip: CapacityPip = children[i]
		pip.fill_color = segment_colors[i] if i < segment_colors.size() else fill_color
		pip.empty_color = empty_color
		pip.filled = i < count
		pip.highlighted = i in highlighted_indices
