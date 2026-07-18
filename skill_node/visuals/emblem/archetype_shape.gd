class_name ArchetypeShape
extends RefCounted
## The canonical archetype → carve-shape mapping for the six hand-authored
## archetypes (dev_sandbox content, tests). Procgen content doesn't use this
## at all — an open, StringName-keyed [ArchetypePolicy] names its OWN
## [CarveShape] directly (see [ArchetypePolicy.carve_shape] /
## [SkillNode.carve_shape]); this enum/dict pair only exists as the quick-pick
## default for hand-authored nodes that never got a policy stamped onto them.
##
## Each shape is meant to be recognisable at a glance, at a distance, on an
## otherwise-empty node (the "ordinary nodes should still read as something"
## design intent — see docs/domain/skillnode-emblem.md's ARCHETYPE priority):
## STR = a plain triangle, DEX = a squished diamond (agile, angular), INT = a
## pentagon, WIS = a placeholder hexagon pending a bespoke "exudes wealth"
## motif (#246 — the first real target for the arbitrary-art bake pipeline),
## PER = an octagon (many-faceted, sensory), CON = a dodecagon (many-sided,
## sturdy).

const EmblemSpec = preload("res://skill_node/visuals/emblem/emblem_spec.gd")
const CarveShape = preload("res://skill_node/visuals/emblem/carve_shape.gd")
const PolygonCarveShape = preload("res://skill_node/visuals/emblem/polygon_carve_shape.gd")

enum Archetype { STR, DEX, INT, WIS, PER, CON }

## Per-archetype [CarveShape]. Built once, lazily, on first access — a plain
## dictionary literal can't call `PolygonCarveShape.new()` at const-eval time.
static var _shapes: Dictionary


static func _ensure_shapes() -> void:
	if not _shapes.is_empty():
		return
	_shapes = {
		Archetype.STR: _polygon(3),
		# Squished from the sides — a diamond read, not a plain square.
		Archetype.DEX: _polygon(4, 0.62),
		Archetype.INT: _polygon(5),
		# TODO(#246): replace with a bespoke "exudes wealth" motif (coin/laurel/
		# sunburst) once the arbitrary-art bake pipeline lands. Hexagon is a
		# placeholder distinct from every other archetype's shape, not a
		# deliberate design pick.
		Archetype.WIS: _polygon(6),
		Archetype.PER: _polygon(8),
		Archetype.CON: _polygon(12),
	}


static func _polygon(sides: int, squish: float = 1.0) -> PolygonCarveShape:
	var shape := PolygonCarveShape.new()
	shape.sides = sides
	shape.squish_x = squish
	return shape


## This archetype's [CarveShape] — the shape it owns, not a bare side count.
static func shape_for(arch: Archetype) -> CarveShape:
	_ensure_shapes()
	return _shapes[arch]


## The fallback CARVE this archetype contributes.
static func carve(arch: Archetype, priority: int = EmblemSpec.PRIORITY_ARCHETYPE, source: StringName = &"archetype") -> EmblemSpec:
	return shape_for(arch).carve(priority, source)
