extends Node2D
## #341 acceptance item 3 — the archetype-legibility sweep: the same 6
## shipped archetypes at 0/1 (unallocated) and 1/1 (allocated, the gapless
## ring), so a human can check "can I name the archetype from the rim alone"
## against the printed row label. This is a committed artifact for that
## eyeball pass, NOT a self-certification — nothing here asserts legibility.
##
## The tree (background, captions, row labels, the 12 RimRing instances) ships
## pre-packaged in rim_archetype_legibility_matrix.tscn; this script's only
## job is a runtime DATA lookup (Archetype.color reads StatRegistry, which
## only resolves once the autoload is up — a plain .tres can't bake that at
## edit time) fanned out onto the already-composed children. It does not
## build the tree.

const ARCHETYPES: Array[String] = [
	"constitution", "dexterity", "intelligence", "perception", "strength", "wisdom",
]


func _ready() -> void:
	for archetype_id in ARCHETYPES:
		var archetype: Archetype = load("res://archetypes/%s.tres" % archetype_id)
		var tint := archetype.color
		var unallocated := get_node(NodePath("Rim_%s_0of1" % archetype_id)) as Node2D
		var allocated := get_node(NodePath("Rim_%s_1of1" % archetype_id)) as Node2D
		unallocated.archetype_tint = tint
		allocated.archetype_tint = tint
		var label := get_node(NodePath("RowLabel_%s" % archetype_id)) as Label
		label.text = archetype.primary_stat.capitalize()
