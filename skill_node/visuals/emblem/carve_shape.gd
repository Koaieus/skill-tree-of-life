@tool
class_name CarveShape
extends Resource
## The *input* side of a CARVE (docs/domain/skillnode-emblem.md): whatever
## produces the shape a source's fallback carve etches into the dome. A
## source (today: [Archetype]) holds a reference to one of these instead of a
## bare int/enum, so "what does this shape look like" lives with the shape
## itself, not scattered across SkillNode/Archetype.
##
## Two producer families, both resolving to the SAME [EmblemSpec] payload
## contract the resolver/InnerDisk already understand:
## - Analytic (this epic): [PolygonCarveShape], [GemCarveShape] — a formula,
##   cheap, batch-friendly.
## - Arbitrary art (deferred, see #245/#246): a future TextureCarveShape that
##   bakes authored art (a spell icon, a keystone glyph) into the shared
##   height+gradient LUT encoding InnerDisk's gem cut already uses. Nothing
##   here forecloses that — a source swapping its CarveShape from a
##   PolygonCarveShape to a TextureCarveShape is a one-line content change,
##   not a re-plumb.

const EmblemSpec = preload("res://skill_node/visuals/emblem/emblem_spec.gd")


## Builds this shape's CARVE contribution at the given priority/source. See
## [method EmblemSpec.polygon_carve] / [method EmblemSpec.gem_carve] for the
## concrete factories a subclass should delegate to.
func carve(_priority: int, _source: StringName) -> EmblemSpec:
	push_error("CarveShape.carve() is abstract — override in a subclass")
	return null
