class_name ArcLayer
extends Node2D

## One edge go-off's board look (Lightning's Shocked): a jagged bolt along every
## graph edge out from [member centre], hop by hop to [member reach], fading over
## [member duration] and then freeing itself. Paint-on-top like [EdgeEnergize]:
## it reads the graph and never touches `Edge`, `Graph` or the edge MultiMesh.
## Thin jagged lines with no fill — the opposite reading from a disc.

## `ui/z_layers.gd` declares no `class_name`; it is the shared z-band index and
## is reached by preload, exactly as [AllocationVFX] reaches it.
const ZLayers = preload("res://ui/z_layers.gd")

## The node the arc spreads from.
@export var centre: SkillNode = null:
	set(value):
		centre = value
		queue_redraw()
## How many graph hops out the bolts run — the go-off's level.
@export_range(1, 8, 1) var reach: int = 1:
	set(value):
		reach = maxi(value, 1)
		queue_redraw()
## The element's identity colour the bolts carry (Lightning's tint).
@export var colour: Color = Color.WHITE:
	set(value):
		colour = value
		queue_redraw()
## Seconds from spawn to gone.
@export_range(0.05, 2.0, 0.01) var duration: float = 0.35
## Stroke width in world px.
@export_range(0.5, 12.0, 0.1) var thickness: float = 1.4:
	set(value):
		thickness = value
		queue_redraw()
## Midpoints per hop, so a hop's bolt has this many kinks.
@export_range(0, 12, 1) var kinks: int = 3:
	set(value):
		kinks = maxi(value, 0)
		queue_redraw()
## Peak sideways offset of a kink, as a fraction of its hop's length.
@export_range(0.0, 0.5, 0.01) var jaggedness: float = 0.14:
	set(value):
		jaggedness = maxf(value, 0.0)
		queue_redraw()
## Glow tier of the element's hue.
@export var emissive_tier: Emissive.Tier = Emissive.Tier.ALERT:
	set(value):
		emissive_tier = value
		queue_redraw()

## Seconds since spawn.
var _elapsed := 0.0


func _ready() -> void:
	z_as_relative = false
	z_index = ZLayers.SPELL_VFX


## Sets the blast the layer draws: its centre, hop count and element colour.
func setup(centre_node: SkillNode, hops: int, element_colour: Color = Color.WHITE) -> void:
	centre = centre_node
	reach = hops
	colour = element_colour


## The bolts, in this layer's space: one polyline per graph edge from a
## depth − 1 node to a depth node within [member reach]. Empty when the centre
## has no graph or the reach holds nobody.
func paths() -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	if centre == null or reach <= 0:
		return out
	var graph := centre.get_graph()
	if graph == null or graph.navigator == null:
		return out
	var depth := graph.navigator.nodes_within(centre, reach)
	for node: SkillNode in depth:
		if node == null or not is_instance_valid(node) or node == centre:
			continue
		var d: int = depth[node]
		if d <= 0 or d > reach:
			continue
		for neighbour: SkillNode in graph.navigator.neighbours_of(node):
			if neighbour == null or not is_instance_valid(neighbour):
				continue
			if depth.get(neighbour, -1) != d - 1:
				continue
			out.append(_bolt(to_local(neighbour.global_position), to_local(node.global_position)))
	return out


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= duration:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var fade := 1.0 - clampf(_elapsed / maxf(duration, 0.001), 0.0, 1.0)
	var stroke := Emissive.at(colour, Emissive.stops(emissive_tier))
	stroke.a *= fade
	for bolt in paths():
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
