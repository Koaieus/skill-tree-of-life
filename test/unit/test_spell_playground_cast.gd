extends GutTest

## The spell playground parks its two entities BESIDE the Graph, inside the
## SubViewport — an ancestor walk can never find it from there, so they used to
## come up with `navigator == null`.
##
## That was invisible until #536 made the resolver LAND each wave mid-walk. A
## shadow `EntityCombat` is built from the owner's `EntityNavigator`, so a
## navigator-less entity snapshots an empty owned set; `CombatWorld.combat_for`
## then falls through to an ownerless ORPHAN slice, and `NodeCombat.take_damage`
## drops the hit on its `owner() == null` guard — a spell that propagates
## normally and quietly gates nothing. Before it even got that far,
## `EntityCombat.snapshot` crashed outright on the untyped-`[]` ternary.
##
## Both halves are pinned here: the entities get a real navigator (via the
## scene-wired `graph_override`), and a snapshot with no navigator at all is
## merely empty rather than fatal.

const _PANEL := preload("res://addons/spell_playground/playground_panel.tscn")

var _panel: Node
var _graph: Graph


func before_each() -> void:
	_panel = _PANEL.instantiate()
	add_child_autofree(_panel)
	await get_tree().process_frame
	await get_tree().process_frame
	_graph = _panel.find_child("Graph", true, false) as Graph
	assert_not_null(_graph, "fixture: the panel must carry a Graph")


func test_the_defender_mirrors_its_authored_territory() -> void:
	var defender := _panel.find_child("DefenderEntity", true, false) as Entity
	assert_not_null(defender, "fixture: the panel must carry a DefenderEntity")
	assert_not_null(defender.navigator,
			"an entity beside the Graph still needs one — that is what `graph_override` is for")
	assert_eq(defender.navigator.get_mirrored_nodes().size(), 16,
			"`wire_to` bootstraps the mirror from authored `owned_by`; all 16 grid cells are the defender's")


## The acceptance for the silent half: the shadow a cast resolves against has to
## INDEX those nodes, or every landing lands nowhere.
func test_a_cast_shadow_indexes_the_defender_nodes() -> void:
	var defender := _panel.find_child("DefenderEntity", true, false) as Entity
	var target := _graph.get_node("Nodes/T_11") as SkillNode
	var world := CombatWorld.shadow()
	var slice := world.combat_for(target)
	assert_not_null(slice, "a shadow must resolve a slice for an allocated node")
	assert_not_null(slice.owner(),
			"resolved through the defender's snapshot, not as an ownerless orphan — an orphan drops every hit")
	assert_eq(slice.owner(), world.combat_for_entity(defender),
			"and it must be THE defender's slice, so a cascade sees the same territory")
	world.free_shadow()


## The raw crash, with no playground around it: an entity that genuinely has no
## graph (a bare fixture, a stand-alone test) snapshots to an empty shadow.
func test_snapshotting_an_entity_with_no_navigator_is_empty_not_fatal() -> void:
	var lone := Entity.new()
	lone.display_name = "Lone"
	autofree(lone)
	add_child(lone)
	await get_tree().process_frame
	assert_null(lone.navigator, "fixture: no Graph anywhere, so no navigator")
	var shadow := lone.get_combat().snapshot()
	assert_not_null(shadow, "snapshot must return a shadow, not blow up on `Array[SkillNode]`")
	assert_eq(shadow.owned().size(), 0, "nothing is owned, so the shadow owns nothing")
	shadow.free_shadow()
