extends GutTest

## The spell playground fires a REAL cast — and for a release it silently did
## not.
##
## The panel called [method SpellResolver.resolve] and played the coordinator
## itself. That was correct until #536's *"shadow always"*: `resolve()` now mints
## a throwaway [method CombatWorld.shadow], lands the whole cast on it and frees
## it, and the VFX layer has been a pure observer since #474 — so every spell
## resolved perfectly and mutated nothing. Nothing failed. Nothing was reported.
## The board just never moved.
##
## Two shapes of test here, and both are needed:
##   * the WIRING the cast depends on — a navigator per entity, a minted
##     `entity_id`, a seated core, a filled allocation level. Each of those reads
##     as "the spell did nothing" when it is missing, from a different direction.
##   * the OUTCOME — HP actually goes down. That is the assertion the whole class
##     of "resolved into a world nobody kept" bugs cannot survive, and it is the
##     one that was missing.

const _PANEL := preload("res://addons/spell_playground/playground_panel.tscn")
const _SPARK: SpellDef = preload("res://attack/spell/defs/spark.tres")
const _HEALING_BEAM: SpellDef = preload("res://attack/spell/defs/healing_beam.tres")

var _panel: Node
var _graph: Graph
var _caster: Entity
var _defender: Entity


func before_each() -> void:
	_panel = _PANEL.instantiate()
	add_child_autofree(_panel)
	await get_tree().process_frame
	await get_tree().process_frame
	_graph = _panel.find_child("Graph", true, false) as Graph
	_caster = _panel.find_child("CasterEntity", true, false) as Entity
	_defender = _panel.find_child("DefenderEntity", true, false) as Entity
	assert_not_null(_graph, "fixture: the panel must carry a Graph")
	assert_not_null(_caster, "fixture: the panel must carry a CasterEntity")
	assert_not_null(_defender, "fixture: the panel must carry a DefenderEntity")
	# The documented headless opt-out (#504): land the whole outcome on the line
	# rather than across several frames of the beat clock. #474's acceptance is
	# that the applied world is identical either way.
	_panel._battle.instant_mutation = true


func _node(name_: String) -> SkillNode:
	return _graph.get_node("Nodes/%s" % name_) as SkillNode


## An entity has to sit in `entities_container` for [method Graph._mint_entity_id]
## to reach it. The playground's two used to sit BESIDE the Graph, inside the
## SubViewport, on a `graph_override` — which bought them a navigator and nothing
## else. `entity_id` stayed 0, and a [LaunchAttackCommand] naming attacker 0
## resolves to null on the far side of the record round trip.
func test_both_entities_are_minted_and_mirrored() -> void:
	for entity in [_caster, _defender]:
		assert_ne(entity.entity_id, 0,
				"%s must be inside entities_container to get an id" % entity.display_name)
		assert_not_null(entity.navigator, "%s has no navigator" % entity.display_name)
	assert_eq(_defender.navigator.get_mirrored_nodes().size(), 16,
			"the defender's whole authored territory is in its mirror")
	assert_eq(_caster.navigator.get_mirrored_nodes().size(), 5,
			"and the caster's — five nodes, so `C_hub` reaches owned degree 4")


## Without a core there is no anchor for [method EntityCombat.cascade_set] to
## island against, so a kill strips the dead node and nothing else — a cascade
## that quietly never runs.
func test_both_cores_are_seated() -> void:
	assert_eq(_caster.core_location, _node("C_hub"))
	assert_eq(_defender.core_location, _node("d_core"))


## `owned_by` is the allocation truth; `allocation_level` is the FILL, and it is
## written by the allocate path alone (#337). The panel authored the first and
## never ran the second, so every node was allocated in the model and drawn as an
## empty shell — the whole board looked dead before a single spell was cast.
func test_every_authored_node_is_filled_not_just_owned() -> void:
	for sn in _graph.get_skill_nodes():
		assert_not_null(sn.owned_by, "%s lost its authored owner" % sn.name)
		assert_eq(sn.allocation_level, 1, "%s is owned but unfilled" % sn.name)


## The cast-from node has to clear the catalogue's deepest `min_degree`,
## measured over the caster's OWN subgraph, or every such spell refuses.
##
## Derived, not hardcoded: this asserted a literal 3 until Cyclone (#696)
## shipped `min_degree = 4` and quietly became uncastable on the only surface
## built for exercising spells by hand. Reading the catalogue means the next
## deeper spell fails HERE, with the fixture named, instead of failing as a
## silent no-op in the playground.
func test_the_cast_from_node_clears_the_deepest_min_degree() -> void:
	var deepest: int = 0
	for spell in SpellCatalog.ALL:
		deepest = maxi(deepest, spell.min_degree)
	assert_eq(_caster.navigator.get_degree(_node("C_hub")), deepest,
			"owned neighbours only; the global degree (one higher, counting `d_entry`) is not the question")


## The acceptance: Cast moves the world.
func test_casting_spark_damages_the_seed() -> void:
	var seed_node := _node("d_hub")
	var before := seed_node.get_combat().get_current_hp()
	_panel.load_spell(_SPARK)
	_panel._on_target_clicked(seed_node)
	await _panel._cast()
	assert_lt(seed_node.get_combat().get_current_hp(), before,
			"a cast that resolves into a freed shadow leaves this untouched")


## And it lands through the record, not around it: the plan validated, the
## affordability gate read the real board, and the AP came off it.
func test_casting_spends_the_caster_action_points() -> void:
	var ap: PoolStat = _caster.stat_board.action_points
	_panel.load_spell(_SPARK)
	_panel._on_target_clicked(_node("d_hub"))
	await _panel._cast()
	assert_lt(ap.current, float(ap.get_value()), "launch_attack deducts the outcome's ap_cost")


## A heal that changes nothing and a cast that was REFUSED look identical from
## outside — both leave the board where it was. So this asserts the heal moves HP
## upward off a wounded node rather than asserting "no error": the panel spent a
## release doing exactly the former while looking like the latter.
func test_casting_a_heal_restores_a_wounded_node() -> void:
	var wounded := _node("d_hub")
	wounded.get_combat().take_damage(5.0, null)
	var before := wounded.get_combat().get_current_hp()
	assert_lt(before, wounded.get_combat().get_max_hp(), "fixture: it has room to heal")
	_panel.load_spell(_HEALING_BEAM)
	_panel._on_target_clicked(wounded)
	await _panel._cast()
	assert_gt(wounded.get_combat().get_current_hp(), before,
			"a heal that resolves but never lands is indistinguishable from a refusal")
	assert_false(_panel.status_label.text.contains("refused"),
			"got: %s" % _panel.status_label.text)


## Killing the defender's core kills the ENTITY, and Reset has to survive that —
## `_authored_owners` holds Entity references captured at `_ready`, so anything
## that freed the corpse would leave the map dangling. A freed Object compares
## equal to null (`.claude/rules/gdscript-pitfalls.md`), so the failure mode is
## silence: Reset would allocate nothing and report success.
func test_reset_restores_the_board_after_the_defender_dies() -> void:
	var board: EntityStatBoard = _defender.stat_board
	board.health.set_current(1.0)
	_defender.core_location.get_combat().take_damage(9999.0, null)
	await get_tree().process_frame
	assert_true(_defender.is_dead, "fixture: the core died, so the entity did")
	_panel._reset_state()
	assert_false(_defender.is_dead, "Reset brings the defender back")
	for sn in _graph.get_skill_nodes():
		assert_not_null(sn.owned_by, "%s never got its authored owner back" % sn.name)
		assert_eq(sn.allocation_level, 1, "%s came back owned but unfilled" % sn.name)
	assert_eq(_defender.core_location, _node("d_core"), "and its core is re-seated")


## A seed the real targeting gate refuses is REPORTED, not swallowed. The old
## panel had no gate at all — it resolved from any seed including its own
## territory, which is not a cast a spell author can ever make in game.
func test_a_friendly_seed_is_refused_with_a_reason() -> void:
	var friendly := _node("C_n")
	var before := friendly.get_combat().get_current_hp()
	_panel.load_spell(_SPARK)
	_panel._on_target_clicked(friendly)
	await _panel._cast()
	assert_eq(friendly.get_combat().get_current_hp(), before, "no friendly fire")
	assert_string_contains(_panel.status_label.text, "refused")


## The raw crash behind the #536 bring-up (kept: it is about [EntityCombat], not
## about this panel). An entity that genuinely has no graph — a bare fixture, a
## stand-alone test — snapshots to an empty shadow rather than blowing up on the
## untyped-`[]` ternary.
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


## The node-HP slider is the max HP of every node on the board, both sides of it.
##
## It is a SET modifier on each entity's `node_health` baseline rather than a
## `base_value` write, because the baseline is `10 + node_health_scaling × CON`
## and the slider has to read as the literal cap. What this pins is the whole
## chain: mutating the modifier's `value` re-dirties the baseline, and every
## owned node's cap provider (#660) re-reads it — no per-node push exists to
## forget.
func test_node_health_slider_moves_every_node_cap() -> void:
	var mine := _node("C_n")
	var theirs := _node("d_hub")
	var before := theirs.get_combat().get_max_hp()
	assert_eq(_panel.node_health_slider.value, before,
			"the slider seeds itself from the baseline, so installing it changes nothing")
	_panel.node_health_slider.value = before + 40.0
	assert_eq(theirs.get_combat().get_max_hp(), before + 40.0, "the defender's nodes follow")
	assert_eq(mine.get_combat().get_max_hp(), before + 40.0, "so do the caster's")
	assert_string_contains(_panel.node_health_label.text, "%.0f" % (before + 40.0))


## Moving the cap — either way — does not forgive damage — `node_combat_health` stores damage
## taken and derives `current` from the live cap (#660), which is what lets this
## panel accumulate across casts while the slider moves.
func test_lowering_the_slider_keeps_the_damage_already_taken() -> void:
	var target := _node("d_hub")
	_panel.load_spell(_SPARK)
	_panel._on_target_clicked(target)
	await _panel._cast()
	var missing := target.get_combat().get_max_hp() - target.get_combat().get_current_hp()
	assert_gt(missing, 0.0, "fixture: the cast has to have hurt it")
	for moved in [_panel.node_health_slider.value + 25.0, _panel.node_health_slider.value - 5.0]:
		assert_gt(moved, missing, "fixture: stay above the wound, or `current` floors instead")
		_panel.node_health_slider.value = moved
		assert_almost_eq(target.get_combat().get_max_hp() - target.get_combat().get_current_hp(),
				missing, 0.01, "the wound survives a cap move to %.0f" % moved)
