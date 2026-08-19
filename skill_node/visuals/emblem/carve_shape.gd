@tool
class_name CarveShape
extends Resource
## The *input* side of a CARVE (docs/domain/skillnode-emblem.md): whatever
## produces the shape a source's fallback carve etches into the dome. A
## source (today: [Archetype]) holds a reference to one of these instead of a
## bare int/enum, so "what does this shape look like" lives with the shape
## itself, not scattered across SkillNode/Archetype.
##
## Two producer families, both riding the SAME [EmblemSpec] the resolver and
## InnerDisk already understand — the spec now carries the shape ITSELF (#315),
## so neither layer re-declares what a shape is:
## - Analytic: [PolygonCarveShape], [GemCarveShape] — a formula, cheap,
##   batch-friendly.
## - Arbitrary art: [TextureCarveShape] (#246) bakes authored art (a spell icon,
##   a keystone glyph) into the shared height+gradient LUT encoding InnerDisk's
##   gem cut already uses; its live decode is still deferred (#247). A source
##   swapping its CarveShape from a PolygonCarveShape to a TextureCarveShape is
##   a one-line content change, not a re-plumb.
##
## Deliberately knows NOTHING about [InnerDisk] — no `shader_kind()`, no
## `apply_to(disk)`. The renderer dispatches on the shape's type, not the other
## way round; inverting that is what #302 rejected.

@warning_ignore("shadowed_global_identifier")
const EmblemSpec = preload("res://skill_node/visuals/emblem/emblem_spec.gd")


## Builds this shape's CARVE contribution at the given priority/source — the
## entry point every source uses. The base implementation is the whole story
## for a shape with no per-shape wrapping to do; subclasses that need none
## (all of them today) inherit it as-is.
func carve(priority: int, source: StringName) -> EmblemSpec:
	return EmblemSpec.carve(self, priority, source)
