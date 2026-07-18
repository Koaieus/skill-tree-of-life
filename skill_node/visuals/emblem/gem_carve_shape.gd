@tool
class_name GemCarveShape
extends CarveShape
## The loot relic's gem-cut carve (#168) — a fixed, baked height-field dent,
## identical on every instance (see InnerDisk's gem LUT / `sn_gem_bump`). No
## per-instance parameters: unlike [PolygonCarveShape], this shape's geometry
## never varies, which is exactly why it's baked once instead of computed
## per-pixel (see .claude/rules/skill-node-visuals.md's "diamond crown"
## section). Carries no @export knobs on purpose — tune the shape itself in
## InnerDisk's GEM_* bake constants, not per-instance here.


func carve(priority: int, source: StringName) -> EmblemSpec:
	return EmblemSpec.gem_carve(priority, source)
