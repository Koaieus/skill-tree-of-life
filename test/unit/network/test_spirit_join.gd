extends GutTest

## A spirit crosses a join as its scene (by path) and position (by value); the
## aspect is a function of position, so nothing extra is on the wire.

const _SPIRIT := preload("res://skill_node/keystone/instances/spirit_node.tscn")
const _MYSTERY := preload("res://skill_node/keystone/instances/mystery_spirit_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")


func _graph() -> Graph:
	var g := autofree(_GRAPH_SCENE.instantiate()) as Graph
	add_child(g)
	return g


func _join(host: Graph) -> Graph:
	var client := _graph()
	await get_tree().process_frame
	GraphSnapshot.decode(GraphSnapshot.encode(host), client)
	await get_tree().process_frame
	return client


func _spirits(g: Graph) -> Array[SpiritNode]:
	var out: Array[SpiritNode] = []
	for n in g.get_skill_nodes():
		if n is SpiritNode:
			out.append(n)
	return out


func _place(g: Graph, scene: PackedScene, at: Vector2, stable_id: int) -> SpiritNode:
	var s := scene.instantiate() as SpiritNode
	s.position = at
	g.add_skill_node(s)
	g.restore_stable_id(s, stable_id)
	return s


func test_a_joining_peer_offers_the_same_aspect() -> void:
	var host := _graph()
	await get_tree().process_frame
	var faced := _place(host, _SPIRIT, Vector2(217, -90), 1)
	var mystery := _place(host, _MYSTERY, Vector2(-310, 44), 2)
	var client: Graph = await _join(host)

	var back := _spirits(client)
	assert_eq(back.size(), 2, "both spirits crossed")
	for s in back:
		var src: SpiritNode = faced if s.position == faced.position else mystery
		assert_eq(s.scene_file_path, src.scene_file_path)
		assert_eq(s.aspect, src.aspect, "same aspect on both peers")
		assert_eq(s.get_addons().size(), 1, "one relic, not the scene's plus a re-instantiated one")
		var dust := s.get_dust()
		assert_not_null(dust, "the relic came with the scene")
		if dust == null:
			continue
		assert_eq(dust.candidates[0].stat_id, src.get_dust().candidates[0].stat_id)
		assert_eq(dust.gold_color, src.get_dust().gold_color)
		assert_eq(dust.conceal_offer, src.reveal_on_claim)
	var client_mystery: SpiritNode = back[0] if back[0].reveal_on_claim else back[1]
	assert_eq(client_mystery.get_dust().gold_color, client_mystery.mystery_color, "gray on the joiner too")
	assert_eq(mystery.get_dust().gold_color, mystery.mystery_color, "and on the host")


func test_a_claimed_spirit_crosses_without_its_relic() -> void:
	var host := _graph()
	await get_tree().process_frame
	var s := _place(host, _SPIRIT, Vector2(50, 50), 1)
	var dust := s.get_dust()
	s.remove_child(dust)
	dust.free()
	var client: Graph = await _join(host)
	var back := _spirits(client)
	assert_eq(back.size(), 1)
	if back.size() == 1:
		assert_null(back[0].get_dust(), "a spent spirit stays spent on the joiner")
