extends GutTest

## A SkillNode keeps two modifier facts apart: `authored_modifiers` is what an
## author or procgen wrote (the @export, the only serialized one); `modifiers`
## is the runtime composition — authored + addon/effect/loot grants — seeded
## from the authored list by array copy at `_ready` and never stored. Pins the
## split, the serialization boundary, and the sweep of every shipped scene that
## used to bake a `modifiers =` line.

const SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const WATCHTOWER_SCENE := preload("res://skill_node/addons/defs/watchtower_addon.tscn")

## Standalone SkillNode scenes that carried a baked `modifiers =` line before
## the split — each must still instantiate with its authored offering.
const STANDALONE_SCENES: Array[String] = [
	"res://skill_node/keystone/instances/ap_keystone_node.tscn",
	"res://skill_node/keystone/instances/archmage_node.tscn",
	"res://skill_node/keystone/instances/farsight_node.tscn",
	"res://skill_node/keystone/instances/inversion_node.tscn",
	"res://skill_node/keystone/instances/mythic_ward_node.tscn",
	"res://skill_node/keystone/instances/natural_xp_node.tscn",
	"res://skill_node/keystone/instances/titan_node.tscn",
	"res://skill_node/keystone/instances/wisdom_keystone_node.tscn",
	"res://test/support/effect_landmark_node.tscn",
]

## Composed scenes → how many of their SkillNodes carried a baked line.
const COMPOSED_SCENES: Dictionary = {
	"res://scenes/dev_sandbox.tscn": 20,
	"res://scenes/dev_bloom_sandbox.tscn": 21,
}

var _node: SkillNode


func before_each() -> void:
	_node = SKILL_NODE_SCENE.instantiate()


func after_each() -> void:
	if is_instance_valid(_node):
		_node.free()


func _mod(stat: StringName, value: float) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = stat
	m.operation = StatModifier.Operation.ADD_BASE
	m.value = value
	return m


func test_addon_grants_reach_modifiers_but_never_the_authored_list() -> void:
	var authored := _mod(&"strength", 2.0)
	_node.authored_modifiers = [authored]
	add_child(_node)
	await get_tree().process_frame
	var addon: SkillNodeAddon = WATCHTOWER_SCENE.instantiate()
	_node.add_child(addon)
	var granted: Array[StatModifier] = addon.get_entity_modifiers()
	assert_true(granted.size() > 0, "fixture: the watchtower grants entity modifiers")
	for m in granted:
		assert_true(_node.modifiers.has(m), "the addon's entity modifier joins the runtime list")
	assert_eq(_node.authored_modifiers.size(), 1, "the authored list never grows from an addon")
	assert_true(_node.authored_modifiers[0] == authored, "and still holds the authored instance")
	_node.remove_child(addon)
	addon.queue_free()
	assert_eq(_node.modifiers.size(), 1, "detach returns the runtime list to the authored one")
	assert_true(_node.modifiers[0] == authored, "same authored instance, not a copy")
	assert_eq(_node.authored_modifiers.size(), 1, "the authored list is untouched by detach")


func test_authored_seeds_the_runtime_list_by_array_copy() -> void:
	var authored := _mod(&"strength", 2.0)
	_node.authored_modifiers = [authored]
	add_child(_node)
	assert_true(_node.modifiers.has(authored), "authored is composed into modifiers at _ready, same instance")
	_node.add_entity_modifier(_mod(&"dexterity", 1.0))
	assert_eq(_node.modifiers.size(), 2, "a runtime grant lands on the runtime list")
	assert_eq(_node.authored_modifiers.size(), 1, "and never on the authored list — distinct arrays")
	# A combat-depth clone shares the runtime array by design; the authored list
	# lives outside NodeState, so nothing appended through a clone can reach it.
	var c: NodeState = _node.state.clone()
	c.modifiers.append(_mod(&"intelligence", 1.0))
	assert_eq(_node.authored_modifiers.size(), 1, "a clone's grant cannot reach the authored list")


func test_runtime_modifiers_assigned_before_ready_still_compose() -> void:
	var runtime := _mod(&"strength", 1.0)
	var authored := _mod(&"dexterity", 1.0)
	_node.modifiers = [runtime]
	_node.authored_modifiers = [authored]
	add_child(_node)
	assert_true(_node.modifiers.has(runtime), "a code-built node's pre-ready runtime list survives _ready")
	assert_true(_node.modifiers.has(authored), "and the authored list composes on top")
	assert_eq(_node.modifiers.size(), 2, "exactly the two, nothing doubled")


func test_authored_assigned_after_ready_recomposes() -> void:
	add_child(_node)
	var a := _mod(&"strength", 1.0)
	_node.authored_modifiers = [a]
	assert_true(_node.modifiers.has(a), "a post-ready authored write composes immediately")
	var b := _mod(&"dexterity", 1.0)
	_node.authored_modifiers = [b]
	assert_false(_node.modifiers.has(a), "the replaced authored entry leaves the runtime list")
	assert_true(_node.modifiers.has(b), "the new one joins it")
	assert_eq(_node.modifiers.size(), 1, "no residue")


func test_only_authored_modifiers_is_serialized() -> void:
	var usage: Dictionary = {}
	for p in _node.get_property_list():
		usage[p.name] = int(p.usage)
	assert_true(usage.has("authored_modifiers"), "authored_modifiers is a property")
	assert_true((usage.get("authored_modifiers", 0) & PROPERTY_USAGE_STORAGE) != 0,
			"authored_modifiers is stored — it is what a .tscn carries")
	assert_true(usage.has("modifiers"), "modifiers is still a property")
	assert_true((usage.get("modifiers", 0) & PROPERTY_USAGE_STORAGE) == 0,
			"modifiers is never stored — a derived list cannot compound on save")


func test_shipped_standalone_scenes_kept_their_authored_modifiers() -> void:
	for path in STANDALONE_SCENES:
		var n: SkillNode = (load(path) as PackedScene).instantiate()
		assert_true(n.authored_modifiers.size() > 0, "%s still carries its authored offering" % path)
		n.queue_free()


func test_shipped_composed_scenes_kept_their_authored_modifiers() -> void:
	for path in COMPOSED_SCENES:
		var root: Node = (load(path) as PackedScene).instantiate()
		var carriers := 0
		for n in root.find_children("*", "SkillNode", true, false):
			if (n as SkillNode).authored_modifiers.size() > 0:
				carriers += 1
		assert_eq(carriers, int(COMPOSED_SCENES[path]), "%s: every baked offering survived the rename" % path)
		root.queue_free()
