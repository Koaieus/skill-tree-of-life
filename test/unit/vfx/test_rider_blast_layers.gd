extends GutTest

## A board blast lays one rider layer per [member BlastMark.riders] identity,
## in order: the rider's aspect's authored [member Aspect.blast_layer], else
## the identity-tinted generic [RiderBlastLayer]. Zero riders = the plain ring.

const _GENERIC := preload("res://ui/vfx/rider_blast_layer.tscn")
const _POISON := preload("res://identity/defs/poison.tres")
const _CURSE := preload("res://identity/defs/curse.tres")
const _NODE_SCENE := preload("res://skill_node/skill_node.tscn")

var _vfx: BlastVFX
var _centre: SkillNode


func before_each() -> void:
	_vfx = BlastVFX.new()
	_vfx.roster = AspectRoster.new()
	add_child_autofree(_vfx)
	_centre = _NODE_SCENE.instantiate() as SkillNode
	add_child_autofree(_centre)


func _mark(riders: Array[Identity]) -> BlastMark:
	var mark := BlastMark.new()
	mark.centre = _centre
	mark.reach = 100.0
	mark.riders = riders
	return mark


func _layers(visual: BlastVisual) -> Array[Node]:
	var out: Array[Node] = []
	if visual != null:
		for child in visual.get_children():
			out.append(child)
	return out


## A bespoke scene stand-in: a plain Node2D, told apart by its name.
func _bespoke() -> PackedScene:
	var root := Node2D.new()
	root.name = "Bespoke"
	var scene := PackedScene.new()
	scene.pack(root)
	root.free()
	return scene


func test_two_riders_lay_two_generic_layers_in_identity_order_each_tinted() -> void:
	var layers := _layers(_vfx.spawn(_mark([_POISON, _CURSE] as Array[Identity])))
	assert_eq(layers.size(), 2, "one layer per rider")
	if layers.size() != 2:
		return
	var expected: Array[Identity] = [_POISON, _CURSE]
	for i in 2:
		var layer := layers[i] as RiderBlastLayer
		assert_not_null(layer, "the generic layer")
		if layer == null:
			continue
		assert_true(is_same(layer.rider, expected[i]), "identity order")
		assert_eq(layer.color(), Emissive.tint(expected[i].tint, Emissive.stops(layer.emissive_tier)),
				"tinted from its identity")
		assert_eq(layer.layer, i, "stacked by index")
		assert_almost_eq(layer.radius, 100.0, 0.001, "the ring's reach")


func test_no_riders_is_the_plain_ring() -> void:
	var visual := _vfx.spawn(_mark([] as Array[Identity]))
	assert_not_null(visual, "the ring still plays")
	assert_eq(_layers(visual).size(), 0, "no layers")


func test_an_authored_blast_layer_replaces_the_generic() -> void:
	var bespoke := _bespoke()
	var aspect := Aspect.new()
	aspect.identity = _POISON
	aspect.blast_layer = bespoke
	_vfx.roster.aspects.append(aspect)
	var scenes := BlastVFX.layers_for([_POISON, _CURSE] as Array[Identity], _vfx.roster, _GENERIC)
	assert_eq(scenes, [bespoke, _GENERIC] as Array[PackedScene], "bespoke for poison, generic for curse")
	var layers := _layers(_vfx.spawn(_mark([_POISON, _CURSE] as Array[Identity])))
	assert_eq(layers.size(), 2, "one layer per rider")
	if layers.size() == 2:
		assert_eq(String(layers[0].name), "Bespoke", "the authored scene")
		assert_true(layers[1] is RiderBlastLayer, "the generic for the bare rider")


func test_eight_layers_have_strictly_increasing_delays_inside_the_duration() -> void:
	var riders: Array[Identity] = []
	for i in 8:
		riders.append(_POISON)
	var layers := _layers(_vfx.spawn(_mark(riders)))
	assert_eq(layers.size(), 8, "one layer per rider")
	var prev := 0.0
	for node in layers:
		var layer := node as RiderBlastLayer
		var d := layer.delay_seconds()
		assert_gt(d, prev, "strictly later than the layer before")
		assert_lt(d, layer.duration, "lands inside the sweep")
		prev = d


func test_few_layers_keep_the_plain_lag_stack() -> void:
	var layers := _layers(_vfx.spawn(_mark([_POISON, _CURSE] as Array[Identity])))
	assert_almost_eq((layers[1] as RiderBlastLayer).delay_seconds(), 0.12, 0.0001, "lag * (layer + 1)")


func test_blast_landed_on_the_bus_spawns_exactly_one_visual() -> void:
	Events.blast_landed.emit(_mark([] as Array[Identity]))
	var visuals := _vfx.get_children().filter(func(c: Node) -> bool: return c is BlastVisual)
	assert_eq(visuals.size(), 1, "one ring per blast")


func test_a_muted_vfx_ignores_the_bus() -> void:
	_vfx.muted = true
	Events.blast_landed.emit(_mark([] as Array[Identity]))
	var visuals := _vfx.get_children().filter(func(c: Node) -> bool: return c is BlastVisual)
	assert_eq(visuals.size(), 0, "muted = silent")
