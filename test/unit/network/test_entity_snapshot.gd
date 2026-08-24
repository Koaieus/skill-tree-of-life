extends GutTest

## #560 — a joining client's entity boards must carry every allocated node's
## grants and every looted relic. Before [EntitySnapshot],
## [method GraphSnapshot._decode_node] set `owned_by` directly and NOTHING
## rebuilt the owner's board, so every health bar and shift-tooltip that client
## drew was silently wrong from its first frame.
##
## The shape of every test here mirrors the real join: a SOURCE graph with live
## state, a TARGET graph whose entities were already spawned by the roster
## (#528/#553 — [EntitySnapshot] decorates, it never spawns), and the two-pass
## decode order #560 D5 settled (entities, then nodes, then the entity->node
## references).

const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _TITAN_KEYSTONE := preload("res://entity/keystone/instances/titan_keystone.tres")


func _new_graph() -> Graph:
	var graph: Graph = autofree(_GRAPH_SCENE.instantiate())
	add_child(graph)
	await get_tree().process_frame
	return graph


## A hand-built line of nodes — small, deterministic, and free of procgen's
## content draw, so an assertion about a modifier is about THIS test's modifier.
func _line_graph(count: int) -> Graph:
	var graph := await _new_graph()
	var previous: SkillNode = null
	for i in count:
		var node: SkillNode = _NODE_SCENE.instantiate()
		node.position = Vector2(i * 100.0, 0.0)
		graph.add_skill_node(node)
		graph.restore_stable_id(node, i + 1)
		if previous != null:
			graph.add_edge(previous, node)
		previous = node
	return graph


func _new_entity(graph: Graph) -> Entity:
	var e: Entity = autofree(Entity.new())
	e.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	graph.entities_container.add_child(e)
	return e


func _mod(stat_id: StringName, value: float, op := StatModifier.Operation.ADD_BASE) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = stat_id
	m.value = value
	m.operation = op
	return m


## Own [param node] the way [method AllocationSystem.force_allocate] does, minus
## the navigator and SP bookkeeping this file has no opinion about.
func _own(node: SkillNode, e: Entity) -> void:
	node.owned_by = e
	node.allocation_level = 1
	node.apply_entity_modifiers_to(e.stat_board)


## Both halves of the wire, in the order the join runs them.
func _transfer(source: Graph, target: Graph) -> void:
	var entity_bytes := EntitySnapshot.encode(source)
	var graph_bytes := GraphSnapshot.encode(source)
	EntitySnapshot.decode(entity_bytes, target)
	GraphSnapshot.decode(graph_bytes, target)
	EntitySnapshot.resolve_graph_refs(entity_bytes, target)


# --- 1. The bug, pinned ----------------------------------------------------

## Acceptance 1. Several nodes carrying entity modifiers, plus a relic granted
## straight onto the board, and the decoded owner must read the SAME
## `node_health` on a decoded owned node as the source does. `node_health` is a
## borrowed stat — [method NodeCombat.get_local_value] merges the node board
## with the OWNER's — so this is exactly the number every health bar draws.
##
## Fails on master: nothing rebuilt the owner's board at all.
func test_owned_node_local_value_survives_the_join() -> void:
	var source := await _line_graph(4)
	var target := await _line_graph(0)
	var src_owner := _new_entity(source)
	_new_entity(target)  # same mint order -> entity_id 1 on both

	var nodes := source.get_skill_nodes()
	nodes[0].modifiers.append(_mod(&"constitution", 5.0))
	nodes[1].modifiers.append(_mod(&"node_health", 7.0))
	for i in 2:
		_own(nodes[i], src_owner)
	# The relic: granted straight onto the board, no node behind it.
	src_owner.stat_board.add_modifier(_mod(&"constitution", 3.0))

	var expected: Variant = nodes[0].get_local_value(&"node_health")
	_transfer(source, target)

	var decoded := target.get_skill_nodes()[0]
	assert_eq(decoded.owned_by, target.get_by_entity_id(1), "ownership did not cross")
	assert_eq(decoded.get_local_value(&"node_health"), expected,
			"the decoded owner's board is missing node grants or the relic")


# --- 2. Relic ---------------------------------------------------------------

## Acceptance 2. The case D5's rejected alternative (replaying
## `register_scene_authored_ownership()`) structurally cannot reach: a board
## modifier with no node behind it.
func test_relic_with_no_node_behind_it_round_trips() -> void:
	var source := await _line_graph(1)
	var target := await _line_graph(0)
	var src_owner := _new_entity(source)
	var dst_owner := _new_entity(target)

	var baseline: Variant = dst_owner.stat_board.get_value(&"strength")
	src_owner.stat_board.add_modifier(_mod(&"strength", 12.0))

	_transfer(source, target)

	assert_eq(dst_owner.stat_board.get_value(&"strength"),
			src_owner.stat_board.get_value(&"strength"),
			"the relic modifier did not cross")
	assert_ne(dst_owner.stat_board.get_value(&"strength"), baseline,
			"the test proved nothing — the relic did not move the stat")


# --- 3. Pools carry `current` ----------------------------------------------

## Acceptance 3. `current` crosses BY VALUE; the cap does not cross at all and
## is recomputed from base + modifiers on the far side.
func test_pool_current_crosses_and_cap_is_recomputed() -> void:
	var source := await _line_graph(1)
	var target := await _line_graph(0)
	var src_owner := _new_entity(source)
	var dst_owner := _new_entity(target)

	src_owner.stat_board.add_modifier(_mod(&"health", 20.0))
	var cap := float(src_owner.stat_board.health.get_value())
	src_owner.stat_board.health.set_current(cap * 0.5)

	_transfer(source, target)

	assert_almost_eq(dst_owner.stat_board.health.current,
			src_owner.stat_board.health.current, 0.001,
			"pool `current` did not survive the join")
	assert_almost_eq(float(dst_owner.stat_board.health.get_value()), cap, 0.001,
			"the cap was not recomputed from the decoded base + modifiers")
	assert_true(dst_owner.stat_board.health.current < float(dst_owner.stat_board.health.get_value()),
			"a half-health entity arrived at full — `current` was clamped or refilled")


# --- 4. Surplus -------------------------------------------------------------

## Acceptance 4. Surplus sits OUTSIDE the cap
## (`.claude/rules/stats-system.md`), so a decode must neither clamp it into
## the cap nor let the cap-change policy touch it.
func test_surplus_round_trips_outside_the_cap() -> void:
	var source := await _line_graph(1)
	var target := await _line_graph(0)
	var src_owner := _new_entity(source)
	var dst_owner := _new_entity(target)

	var src_pool := _first_surplus_pool(src_owner.stat_board)
	assert_not_null(src_pool, "no SurplusPoolStat on the default entity board")
	if src_pool == null:
		return
	var id := src_pool.definition.id
	src_pool.set_surplus(4)

	_transfer(source, target)

	var dst_pool := dst_owner.stat_board.get_stat(id) as SurplusPoolStat
	assert_eq(dst_pool.surplus, 4, "surplus did not cross")
	assert_eq(dst_pool.available(), src_pool.available(),
			"spendable-this-turn diverged — surplus was folded into the cap")


func _first_surplus_pool(board: StatBoard) -> SurplusPoolStat:
	for pool in board.get_pool_stats():
		if pool is SurplusPoolStat:
			return pool
	return null


# --- 5. Skill points --------------------------------------------------------

## Acceptance 5. A decoded entity has the SAME spendable SP as the source, not
## a fresh pool — `wounded` and `staked` cross by value and `used` falls out of
## the identity rather than crossing.
func test_skill_point_bins_round_trip() -> void:
	var source := await _line_graph(3)
	var target := await _line_graph(0)
	var src_owner := _new_entity(source)
	var dst_owner := _new_entity(target)

	var sp := src_owner.stat_board.skill_points
	sp.grant(6)
	sp.stake(2)
	sp.spend(1)
	sp.wound(1)

	_transfer(source, target)

	var dst_sp := dst_owner.stat_board.skill_points
	assert_almost_eq(dst_sp.current, sp.current, 0.001, "spendable SP diverged")
	assert_eq(dst_sp.wounded, sp.wounded, "wounded SP did not cross")
	assert_eq(dst_sp.staked, sp.staked, "staked SP did not cross")
	assert_eq(dst_sp.used, sp.used, "derived `used` did not fall out of the decoded bins")


# --- 6. Effects with provenance --------------------------------------------

## Acceptance 6. A node-granted [EffectInstance] decodes with its `source_node`
## resolved to the node of the same `stable_id`, so
## [method Entity.revoke_effects_from] works on the client — and works for
## real: the revoke must actually take the effect's modifier back off the
## board, which is only true if the grant ledger's handle is the instance the
## board holds (see [method Stat.read_dict]'s reconcile).
func test_effect_provenance_survives_and_revoke_still_bites() -> void:
	var source := await _line_graph(3)
	var target := await _line_graph(0)
	var src_owner := _new_entity(source)
	var dst_owner := _new_entity(target)

	# A real shipped effect — a sub-resource of a keystone `.tres`, which is the
	# shape every effect in this project actually has, and the shape
	# [method GraphSnapshot._encode_node] already interns for a node's own
	# `effects`.
	var effect: Effect = _TITAN_KEYSTONE.effects[0]
	var src_node := source.get_skill_nodes()[1]
	src_owner.grant_effect(effect, src_node)

	_transfer(source, target)

	var dst_node := target.get_by_stable_id(source.get_stable_id(src_node))
	assert_not_null(dst_node, "the source node's stable_id did not cross")
	var found: EffectInstance = null
	for inst in dst_owner.get_effects():
		if inst.effect == effect:
			found = inst
	assert_not_null(found, "the granted effect did not cross")
	if found == null:
		return
	assert_eq(found.source_node, dst_node, "source_node did not resolve by stable_id")
	assert_eq(dst_owner.get_effects().size(), src_owner.get_effects().size(),
			"the effect was granted a different number of times than the source holds")

	# The provenance has to BITE, not merely be present: revoking must take the
	# effect's modifier back off the board. That is only true if the ledger's
	# handle is still the instance the board holds — i.e. if
	# [method Stat.read_dict] reconciled rather than wiped (see there).
	var with_effect: Variant = dst_owner.stat_board.get_value(&"strength")
	assert_eq(with_effect, src_owner.stat_board.get_value(&"strength"),
			"the effect's own grant did not survive the join")
	dst_owner.revoke_effects_from(dst_node)
	assert_eq(dst_owner.get_effects().size(), 0, "revoke_effects_from did not detach the instance")
	assert_ne(dst_owner.stat_board.get_value(&"strength"), with_effect,
			"revoke left the effect's modifier on the board — the grant ledger holds a stale handle")


# --- 7. Derived never crosses ----------------------------------------------

## Acceptance 7. No board total and no bin appears in the payload — the far
## side's numbers come out right from base + the modifier list alone.
func test_derived_state_is_absent_from_the_payload() -> void:
	var source := await _line_graph(1)
	var src_owner := _new_entity(source)
	src_owner.stat_board.add_modifier(_mod(&"strength", 17.0))

	var board_dict := src_owner.stat_board.to_dict()
	var strength: Dictionary = board_dict["strength"]
	assert_true(strength.has("base"), "base_value must cross")
	assert_true(strength.has("mods"), "the modifier list must cross")
	for banned in ["value", "computed_value", "bins", "base_add", "increase_sum", "bonus_add"]:
		assert_false(strength.has(banned),
				"derived state '%s' is in the payload — the receiver must recompute it" % banned)
	# The cap of a pool is derived too; only `current` is state.
	var health: Dictionary = board_dict["health"]
	assert_true(health.has("current"), "a pool's `current` must cross")
	assert_false(health.has("value"), "a pool's CAP must not cross — it is recomputed")


# --- 8. Tell-don't-ask ------------------------------------------------------

## Acceptance 8. `_modifiers` never leaves the [Stat]
## (`stats_system/stat.gd`'s own note on why), so neither [Stat] nor
## [StatBoard] may grow a `get_modifiers()` for an encoder to visit. Asserted,
## not merely stated, so a future "just expose the array" cannot land quietly.
func test_no_get_modifiers_escape_hatch() -> void:
	var s: Stat = ScalarStat.new()
	assert_false(s.has_method("get_modifiers"),
			"Stat grew a get_modifiers() — the board must encode ITSELF (#560 D4)")
	var board: StatBoard = _BOARD.duplicate(true)
	assert_false(board.has_method("get_modifiers"),
			"StatBoard grew a get_modifiers() — the board must encode ITSELF (#560 D4)")


# --- 9. Size guard ----------------------------------------------------------

## Acceptance 9. The sibling of [method GraphSnapshot.bytes_per_node]: measure
## small-N and extrapolate rather than generating a huge roster in the suite.
func test_bytes_per_entity_is_measurable_and_sane() -> void:
	var source := await _line_graph(4)
	for i in 4:
		var e := _new_entity(source)
		e.stat_board.add_modifier(_mod(&"strength", float(i + 1)))

	var per := EntitySnapshot.bytes_per_entity(source)
	assert_gt(per, 0.0, "bytes_per_entity measured nothing")
	# A full entity board is ~40 stats; 8 KB each would mean the derived tier is
	# crossing. This is a smoke ceiling, not a budget.
	assert_lt(per, 8192.0, "an entity row is far larger than its accumulated state")
	assert_eq(EntitySnapshot.bytes_per_entity(await _line_graph(0)), 0.0,
			"an empty roster must measure 0, not divide by zero")


# --- Decoration, not spawning (#560 D7) ------------------------------------

## A row whose entity the roster never spawned is SKIPPED, mirroring how
## [method GraphSnapshot._decode_node] decodes an unresolvable `owner_id` as
## unowned rather than inventing one.
func test_a_row_with_no_entity_is_skipped_not_spawned() -> void:
	var source := await _line_graph(1)
	var target := await _line_graph(0)
	_new_entity(source)

	var before := target.entities_container.get_child_count()
	_transfer(source, target)

	assert_eq(target.entities_container.get_child_count(), before,
			"EntitySnapshot spawned an entity — it must only ever decorate (#560 D7)")


## `core_location` resolves entity->node and so must be the SECOND pass
## (#560 D5) — pass 1 alone cannot know the node.
func test_core_location_resolves_in_the_second_pass() -> void:
	var source := await _line_graph(3)
	var target := await _line_graph(0)
	var src_owner := _new_entity(source)
	var dst_owner := _new_entity(target)
	src_owner.core_location = source.get_skill_nodes()[2]

	var entity_bytes := EntitySnapshot.encode(source)
	EntitySnapshot.decode(entity_bytes, target)
	assert_null(dst_owner.core_location, "pass 1 resolved a node that does not exist yet")

	GraphSnapshot.decode(GraphSnapshot.encode(source), target)
	EntitySnapshot.resolve_graph_refs(entity_bytes, target)
	assert_eq(dst_owner.core_location,
			target.get_by_stable_id(source.get_stable_id(src_owner.core_location)),
			"core_location did not resolve by stable_id in pass 2")


## The reconcile contract (#560 D4/D7): decoding the same payload twice must
## leave the board identical, not double every modifier on it. This is what
## makes a repeated resync (#561) safe.
func test_decoding_twice_is_idempotent() -> void:
	var source := await _line_graph(2)
	var target := await _line_graph(0)
	var src_owner := _new_entity(source)
	var dst_owner := _new_entity(target)
	src_owner.stat_board.add_modifier(_mod(&"constitution", 9.0))

	_transfer(source, target)
	var once: Variant = dst_owner.stat_board.get_value(&"constitution")
	EntitySnapshot.decode(EntitySnapshot.encode(source), target)

	assert_eq(dst_owner.stat_board.get_value(&"constitution"), once,
			"a second decode doubled the board's modifiers")
