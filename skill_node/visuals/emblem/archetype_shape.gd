class_name ArchetypeShape
extends RefCounted
## The canonical archetype → carve-shape mapping. The archetype owns its own
## shape; a SkillNode never needs to know the side count. This feeds the
## lowest-priority (fallback) CARVE contribution, so an ordinary node shows its
## archetype shape only when nothing higher-priority (keystone / loot / spell)
## claims the carve — and disabling archetype shapes entirely is just declining
## to contribute this one spec.
##
## [InnerDisk] still keeps a local copy of these sides for its legacy weld path;
## fold that onto this once the resolver drives the carve (see
## SKILLNODE_EMBLEM_HANDOFF.md).

const EmblemSpec = preload("res://skill_node/visuals/emblem/emblem_spec.gd")

enum Archetype { STR, DEX, INT, WIS, PER, CON }

## Regular-polygon side count per archetype (STR = triangle … CON = dodecagon).
## These are the batch-friendly analytic shapes the dome shader can carve.
const SIDES := {
	Archetype.STR: 3,
	Archetype.DEX: 4,
	Archetype.WIS: 5,
	Archetype.INT: 6,
	Archetype.PER: 8,
	Archetype.CON: 12,
}


## The fallback CARVE this archetype contributes.
static func carve(arch: Archetype) -> EmblemSpec:
	var sides: int = SIDES.get(arch, 6)
	return EmblemSpec.polygon_carve(sides, EmblemSpec.PRIORITY_ARCHETYPE, &"archetype")
