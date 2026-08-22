extends GutTest

## #527 — the wire format's own acceptance: a joining client receives a
## serialized graph rather than regenerating one, and the round trip preserves
## everything [WorldFingerprint] folds (ownership, topology, accumulated
## per-node state). See `docs/handoffs/lan-versus-transport.md` and #527's
## acceptance spec.
##
## [b]Why fingerprints, not field-by-field asserts.[/b] [WorldFingerprint] is
## the SAME contract the join handshake itself checks at link-up
## (`network/command_link.gd`'s `_on_hello`) — proving decode reproduces a
## matching fingerprint is proving the thing that actually gets checked live,
## not a parallel notion of "correct" this test invented.

const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _CLAMP_ADDON := preload("res://skill_node/addons/clamp_addon.tscn")
const _TITAN_KEYSTONE := preload("res://entity/keystone/instances/titan_keystone.tres")


func _new_graph() -> Graph:
	var graph: Graph = autofree(_GRAPH_SCENE.instantiate())
	add_child(graph)
	await get_tree().process_frame
	return graph


func _procgen_graph(node_count: int, seed_value: int) -> Graph:
	var graph := await _new_graph()
	var cfg := GraphProcgenConfig.new()
	cfg.node_count = node_count
	cfg.seed = seed_value
	cfg.shape_mask = CircularShapeMask.new()
	await GraphProcgen.generate(cfg, graph)
	return graph


func _new_owner(graph: Graph) -> Entity:
	var e: Entity = autofree(Entity.new())
	e.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	graph.entities_container.add_child(e)
	return e


func test_pristine_round_trip_fingerprints_agree() -> void:
	var source := await _procgen_graph(24, 20260822)
	var target := await _new_graph()

	var bytes := GraphSnapshot.encode(source)
	GraphSnapshot.decode(bytes, target)

	assert_eq(WorldFingerprint.compute(target), WorldFingerprint.compute(source),
			"decoded graph diverged from source: %s vs %s" %
			[WorldFingerprint.describe(target), WorldFingerprint.describe(source)])
	assert_eq(target.get_skill_nodes().size(), source.get_skill_nodes().size(),
			"node count did not survive the round trip")
	assert_eq(target.get_edges().size(), source.get_edges().size(),
			"edge count did not survive the round trip")


## The case that motivated the whole decision (#527's acceptance spec):
## ownership, damage, stake/regen state, and an attached addon must all
## survive. Source and target each mint their OWNER entity first (entity_id=1
## on both, per-graph), so ownership resolves without needing #528's roster —
## matching ids across peers is that unit's job, not this one's.
func test_non_pristine_round_trip_fingerprints_agree() -> void:
	var source := await _procgen_graph(16, 555)
	var target := await _new_graph()

	var source_owner := _new_owner(source)
	_new_owner(target)  # same mint order -> same entity_id (1) on target

	var nodes := source.get_skill_nodes()
	var owned_node: SkillNode = nodes[0]
	owned_node.owned_by = source_owner
	owned_node.stake_level = 2
	owned_node.allocation_level = 1
	owned_node.regen_stacks = 3
	owned_node.add_child(_CLAMP_ADDON.instantiate())
	owned_node.restore_current_hp(maxf(owned_node.get_max_hp() - 15.0, 0.0))
	# A keystone (#527's Decisions section names it explicitly in the authored
	# tier — see graph_snapshot.gd's own docstring) on a SEPARATE node, so a
	# lost keystone can't hide behind the addon assertion above.
	var keystone_node: SkillNode = nodes[1]
	keystone_node.keystone = _TITAN_KEYSTONE

	var bytes := GraphSnapshot.encode(source)
	GraphSnapshot.decode(bytes, target)

	assert_eq(WorldFingerprint.compute(target), WorldFingerprint.compute(source),
			"decoded graph diverged from source: %s vs %s" %
			[WorldFingerprint.describe(target), WorldFingerprint.describe(source)])

	var decoded_node := target.get_by_stable_id(source.get_stable_id(owned_node))
	assert_not_null(decoded_node, "decoded graph is missing the owned node's stable_id")
	assert_true(decoded_node.has_addon(ClampAddon), "attached addon did not survive the round trip")

	var decoded_keystone_node := target.get_by_stable_id(source.get_stable_id(keystone_node))
	assert_not_null(decoded_keystone_node, "decoded graph is missing the keystone node's stable_id")
	assert_eq(decoded_keystone_node.keystone, _TITAN_KEYSTONE,
			"keystone did not survive the round trip — a joining client would silently lose its grant")


## Size guard (#527's acceptance): don't generate 2000 nodes inside the unit
## suite (5-10s of procgen in a 105s run) — measure bytes/node at small N and
## assert the extrapolation instead. What this actually guards is that
## resource REFERENCES are interned rather than pathed: a per-node archetype
## path alone (`res://archetypes/....tres`, tens of bytes) repeated instead of
## a one-byte index is the regression this would catch.
func test_bytes_per_node_extrapolates_under_the_naive_ceiling() -> void:
	var graph := await _procgen_graph(40, 777)
	var bpn := GraphSnapshot.bytes_per_node(graph)
	assert_lt(bpn, 80.0,
			"bytes/node (%f) is high enough to suggest paths, not indices, are crossing per node" % bpn)
	# The issue's own ceiling: ~680 KB naive (positional but un-interned) at
	# 2000 nodes. Interned + positional should land well under it.
	assert_lt(bpn * 2000.0, 300000.0,
			"extrapolated 2000-node payload (%f bytes) would blow the naive-encoding ceiling" % (bpn * 2000.0))
