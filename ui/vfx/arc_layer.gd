class_name ArcLayer
extends Node2D

## One edge go-off's board look (Lightning's Shocked): a jagged bolt along every
## graph edge out from [member centre], hop by hop to [member reach], fading over
## [member duration] and then freeing itself. Paint-on-top like [EdgeEnergize]:
## it reads the graph and never touches `Edge`, `Graph` or the edge MultiMesh.
## Thin jagged lines with no fill — the opposite reading from a disc. The bolts
## are every edge within the reach, not the gather's admitted set.
##
## Rider layers ride it as they ride a [BlastVisual] disc: [member companions]
## are laid at [method play] under the same duck-typed contract
## ([method BlastVisual.play]), sized to [method extent].

## `ui/z_layers.gd` declares no `class_name`; it is the shared z-band index and
## is reached by preload, exactly as [AllocationVFX] reaches it.
const ZLayers = preload("res://ui/z_layers.gd")

## The node the arc spreads from.
@export var centre: SkillNode = null:
	set(value):
		centre = value
		_invalidate()
## How many graph hops out the bolts run — the go-off's level.
@export_range(1, 8, 1) var reach: int = 1:
	set(value):
		reach = maxi(value, 1)
		_invalidate()
## The element's identity colour the bolts carry (Lightning's tint).
@export var colour: Color = Color.WHITE:
	set(value):
		colour = value
		queue_redraw()
## Seconds from spawn to gone.
@export_range(0.05, 2.0, 0.01) var duration: float = 0.35
## Seconds between one hop's bolts lighting and the next's, so the arc reads as
## travelling outward. [BlastVFX] sets its [member BlastVFX.generation_stagger]
## (the gather seats each deeper hop one generation later).
@export_range(0.0, 0.5, 0.005, "suffix:s") var hop_stagger: float = 0.05:
	set(value):
		hop_stagger = maxf(value, 0.0)
		queue_redraw()
## Stroke width in world px.
@export_range(0.5, 12.0, 0.1) var thickness: float = 1.4:
	set(value):
		thickness = value
		queue_redraw()
## Midpoints per hop, so a hop's bolt has this many kinks.
@export_range(0, 12, 1) var kinks: int = 3:
	set(value):
		kinks = maxi(value, 0)
		_invalidate()
## Peak sideways offset of a kink, as a fraction of its hop's length.
@export_range(0.0, 0.5, 0.01) var jaggedness: float = 0.14:
	set(value):
		jaggedness = maxf(value, 0.0)
		_invalidate()
## Glow tier of the element's hue.
@export var emissive_tier: Emissive.Tier = Emissive.Tier.ALERT:
	set(value):
		emissive_tier = value
		queue_redraw()
## Rider layers laid at [method play], one per rider ([method BlastVFX.layers_for]).
@export var companions: Array[PackedScene] = []

## The blast's rider identities ([member BlastMark.riders]).
var riders: Array[Identity] = []

## Seconds since spawn.
var _elapsed := 0.0
## The bolts per hop depth (index d − 1), built lazily and dropped by a setter.
var _bolts: Array = []
var _bolts_valid := false
## Px from the centre to the farthest reached node; valid with [member _bolts].
var _extent := 0.0


func _ready() -> void:
	z_as_relative = false
	z_index = ZLayers.SPELL_VFX
	set_process(false)


## Sets the blast the layer draws: its centre, hop count, element colour and riders.
func setup(centre_node: SkillNode, hops: int, element_colour: Color = Color.WHITE,
		rider_ids: Array[Identity] = []) -> void:
	centre = centre_node
	reach = hops
	colour = element_colour
	riders = rider_ids.duplicate()


## Start the fade and lay down the rider layers; frees itself at the end.
func play() -> void:
	var r := extent()
	for i in companions.size():
		var scene := companions[i]
		var companion := scene.instantiate() if scene != null else null
		if companion == null:
			continue
		if &"riders" in companion:
			companion.set(&"riders", riders)
		if &"radius" in companion:
			companion.set(&"radius", r)
		if &"duration" in companion:
			companion.set(&"duration", duration)
		if &"rider" in companion and i < riders.size():
			companion.set(&"rider", riders[i])
		if &"layer" in companion:
			companion.set(&"layer", i)
		if &"layer_count" in companion:
			companion.set(&"layer_count", companions.size())
		add_child(companion)
	_elapsed = 0.0
	set_process(true)
	queue_redraw()


## The bolts, in this layer's space: one polyline per graph edge from a
## depth − 1 node to a depth node within [member reach]. Empty when the centre
## has no graph or the reach holds nobody.
func paths() -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for hop: Array in _hops():
		for bolt: PackedVector2Array in hop:
			out.append(bolt)
	return out


## Px from the centre to the farthest node the bolts reach; 0 when none.
func extent() -> float:
	_hops()
	return _extent


func _invalidate() -> void:
	_bolts_valid = false
	queue_redraw()


func _hops() -> Array:
	if _bolts_valid:
		return _bolts
	_bolts = []
	_extent = 0.0
	_bolts_valid = true
	if centre == null or not is_instance_valid(centre) or reach <= 0:
		return _bolts
	var graph := centre.get_graph()
	if graph == null or graph.navigator == null:
		return _bolts
	for i in reach:
		_bolts.append([])
	var depth := graph.navigator.nodes_within(centre, reach)
	for node: SkillNode in depth:
		if node == null or not is_instance_valid(node) or node == centre:
			continue
		var d: int = depth[node]
		if d <= 0 or d > reach:
			continue
		_extent = maxf(_extent, node.global_position.distance_to(centre.global_position))
		for neighbour: SkillNode in graph.navigator.neighbours_of(node):
			if neighbour == null or not is_instance_valid(neighbour):
				continue
			if depth.get(neighbour, -1) != d - 1:
				continue
			_bolts[d - 1].append(_bolt(to_local(neighbour.global_position), to_local(node.global_position)))
	return _bolts


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= _span():
		queue_free()
		return
	queue_redraw()


## Seconds the whole arc lives: the last hop lights at (reach − 1) × stagger
## and fades over [member duration].
func _span() -> float:
	return maxf(duration, 0.001) + hop_stagger * float(maxi(reach - 1, 0))


func _draw() -> void:
	var hops := _hops()
	for d in hops.size():
		var local := _elapsed - hop_stagger * float(d)
		if is_processing() and local < 0.0:
			continue
		var fade := 1.0 - clampf(local / maxf(duration, 0.001), 0.0, 1.0) if is_processing() else 1.0
		var stroke := Emissive.at(colour, Emissive.stops(emissive_tier))
		stroke.a *= fade
		for bolt: PackedVector2Array in hops[d]:
			if bolt.size() >= 2:
				draw_polyline(bolt, stroke, thickness, true)


## One jagged bolt from [param from] to [param to]: [member kinks] midpoints,
## each offset off the line, both endpoints exact. The roll is seeded by the
## endpoints, so a bolt holds its shape across the fade's redraws.
func _bolt(from: Vector2, to: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array([from])
	var along := to - from
	var span := along.length()
	if span <= 0.001 or kinks <= 0:
		out.append(to)
		return out
	var side := along.orthogonal() / span
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(from) ^ hash(to)
	for k in kinks:
		var f := float(k + 1) / float(kinks + 1)
		var offset := (rng.randf() * 2.0 - 1.0) * jaggedness * span
		out.append(from + along * f + side * offset)
	out.append(to)
	return out
