extends GutTest

## Heal bolt hits cure debuffs (#875, hub #868 D7): [method HealInstance.land_on]
## reduces every `&"debuff"`-tagged status's power by the EFFECTIVE heal (post-
## crit, post-clamp — the same number the hp got) times that def's own
## [member StatusDef.cure_per_hp] (#872 amendment: NOT the raw heal amount). A
## def that authors no `cure_per_hp` (the `0.0` default) is never cured. A
## status cured to `<= 0` is removed through the normal path so
## [method StatusDef._on_removed] fires once; one that survives gets
## [method StatusDef._on_applied] re-run so a planted modifier (Blindness's
## factor) tracks the new power — there is no separate "on cured" hook.
##
## Every non-trivial cure test damages the node first: a heal on a full-HP
## node clamps `effective_amount` to 0, and `cure_debuffs(0.0)` is correctly a
## no-op — so the expected cure below is always read off the LANDED hit's own
## `effective_amount`, never assumed, since default-board mitigation soaks an
## unknown fraction of the fixture damage.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")

## A tagged-debuff def with `cure_per_hp` set (the owner's real content ships
## `cure_per_hp = 0.0` today — untuned — so every test below hand-authors its
## own def rather than loading `.tres` content, same as `test_blindness_status`).
class _TrackingDebuff:
	extends StatusDef
	var removed_calls := 0
	var applied_powers: Array[float] = []

	func _on_applied(_node: NodeCombat, power: float) -> void:
		applied_powers.append(power)

	func _on_removed(_node: NodeCombat) -> void:
		removed_calls += 1


var _graph: Graph
var _alloc: AllocationSystem
var _entity: Entity
var _node: SkillNode
var _worlds: Array[CombatWorld] = []


func before_each() -> void:
	_worlds = []
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_entity = autofree(Entity.new())
	_entity.display_name = "Cured"
	_entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	# Heals crit too (HealInstance.land_on) — zero it so the exact-power
	# asserts below don't flake on the default board's 5% baseline.
	_entity.stat_board.get_stat(&"crit_chance").base_value = 0.0
	_graph.add_child(_entity)

	_node = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_graph.skill_nodes_container.add_child(_node)
	await get_tree().process_frame

	_alloc.force_allocate(_entity, _node)
	_entity.core_location = _node


func after_each() -> void:
	for w in _worlds:
		w.free_shadow()


func _shadow() -> CombatWorld:
	var w := CombatWorld.shadow()
	_worlds.append(w)
	return w


## Damages [member _node] for HALF its max hp (raw — mitigation may soak
## some of it) so a later heal always has room to land, without risking a
## depleted-node cascade that would `clear_statuses()` out from under us.
func _open_a_heal_deficit() -> void:
	var combat := _node.get_combat()
	combat.take_damage(combat.get_max_hp() * 0.5, null)
	assert_lt(combat.get_current_hp(), combat.get_max_hp(),
		"fixture: the node must actually be short of full hp")


func _heal(amount: float) -> HealInstance:
	var h := HealInstance.new()
	h.amount = amount
	h.target = _node
	return h


func _debuff(cure_per_hp: float, power_max: float = 10.0) -> _TrackingDebuff:
	var d := _TrackingDebuff.new()
	d.id = &"tracked_debuff"
	d.tags = [&"debuff"]
	d.power_max = power_max
	d.decay_per_tick = 0.0
	d.cure_per_hp = cure_per_hp
	return d


func test_heal_reduces_debuff_power_by_effective_amount_times_cure_per_hp() -> void:
	_open_a_heal_deficit()
	var def := _debuff(0.5)
	_node.get_combat().apply_status(def, 4.0)
	def.applied_powers.clear()  # drop the apply-time call, isolate the cure

	var heal := _heal(2.0)
	OutcomeApplier.land_one(heal, CombatWorld.live())
	assert_gt(heal.effective_amount, 0.0, "fixture: the heal must have actually landed some hp")

	var expected := 4.0 - heal.effective_amount * 0.5
	assert_almost_eq(_node.get_combat().get_status_power(&"tracked_debuff"), expected, 0.0001,
		"power drops by effective heal * cure_per_hp")
	assert_almost_eq(def.applied_powers[0], expected, 0.0001,
		"_on_applied re-fires at the cured power (Blindness-follow shape)")


func test_heal_removes_status_at_zero_and_fires_on_removed_once() -> void:
	_open_a_heal_deficit()
	var def := _debuff(1.0, 1.0)  # power_max 1.0: any real heal fully cures it
	_node.get_combat().apply_status(def, 1.0)
	var heal := _heal(50.0)  # comfortably larger than any plausible half-hp deficit
	OutcomeApplier.land_one(heal, CombatWorld.live())
	assert_gt(heal.effective_amount, 0.0, "fixture: the heal must have actually landed some hp")

	assert_almost_eq(_node.get_combat().get_status_power(&"tracked_debuff"), 0.0, 0.0001,
		"cured past zero → gone")
	assert_eq(def.removed_calls, 1, "_on_removed fires exactly once")


func test_non_debuff_tagged_status_is_untouched_by_a_heal() -> void:
	_open_a_heal_deficit()
	var def := _debuff(1.0)
	def.tags = []  # not a debuff
	_node.get_combat().apply_status(def, 4.0)
	OutcomeApplier.land_one(_heal(50.0), CombatWorld.live())

	assert_almost_eq(_node.get_combat().get_status_power(&"tracked_debuff"), 4.0, 0.0001,
		"a heal never touches a status without the debuff tag")


func test_a_debuff_with_no_authored_cure_per_hp_is_untouched_by_a_heal() -> void:
	_open_a_heal_deficit()
	var def := _debuff(0.0)  # the owner's shipped default on blindness.tres today
	_node.get_combat().apply_status(def, 4.0)
	OutcomeApplier.land_one(_heal(50.0), CombatWorld.live())

	assert_almost_eq(_node.get_combat().get_status_power(&"tracked_debuff"), 4.0, 0.0001,
		"cure_per_hp 0.0 opts a status out of cure entirely")


func test_a_heal_wasted_on_a_full_health_node_cures_nothing() -> void:
	# Deliberately no _open_a_heal_deficit() — the node is at full hp.
	var def := _debuff(1.0)
	_node.get_combat().apply_status(def, 4.0)
	var heal := _heal(5.0)
	OutcomeApplier.land_one(heal, CombatWorld.live())
	assert_almost_eq(heal.effective_amount, 0.0, 0.0001, "fixture: nothing to heal")

	assert_almost_eq(_node.get_combat().get_status_power(&"tracked_debuff"), 4.0, 0.0001,
		"effective_amount 0 → cure_debuffs is a no-op, per its own guard")


func test_heal_on_a_shadow_cures_only_the_shadow_slice() -> void:
	_open_a_heal_deficit()
	var def := _debuff(1.0)
	_node.get_combat().apply_status(def, 4.0)

	var w := _shadow()
	var slice := w.combat_for(_node)
	var heal := _heal(3.0)
	OutcomeApplier.land_one(heal, w)
	assert_gt(heal.effective_amount, 0.0, "fixture: the shadow heal must have actually landed some hp")

	assert_almost_eq(slice.get_status_power(&"tracked_debuff"), 4.0 - heal.effective_amount, 0.0001,
		"the shadow slice's status is cured by exactly the shadow heal's effective amount")
	assert_almost_eq(_node.get_combat().get_status_power(&"tracked_debuff"), 4.0, 0.0001,
		"the live status must be untouched by a shadow landing")


## Pins the Blindness-specific consequence (hub #868 amendment): the cured
## power must re-drive the planted local modifier, not just the stored power
## number, and the modifier must vanish with the status at zero.
func test_a_cured_blindness_modifier_tracks_the_new_power_and_clears_at_zero() -> void:
	_open_a_heal_deficit()
	var blind := BlindnessStatus.new()
	blind.id = &"blindness"
	blind.tags = [&"debuff"]
	blind.power_max = 3.0
	blind.decay_per_tick = 0.0
	blind.cure_per_hp = 1.0

	_node.get_combat().apply_status(blind, 3.0)
	var heal := _heal(1.0)
	OutcomeApplier.land_one(heal, CombatWorld.live())
	var expected := maxf(3.0 - heal.effective_amount, 0.0)
	assert_gt(expected, 0.0, "fixture: pick a small enough heal that the status survives")

	var s: Stat = _node.node_board.get_stat(&"vision_range")
	var mod: StatModifier = null
	for m in s.bins.multipliers:
		if m is BlindnessStatus.BlindModifier:
			mod = m
	assert_not_null(mod, "the blind modifier is still planted")
	if mod != null:
		assert_almost_eq(mod.value, blind.factor_for(expected), 0.0001,
			"the modifier's factor follows the cured power")

	# A second, larger heal cures it the rest of the way to zero.
	OutcomeApplier.land_one(_heal(50.0), CombatWorld.live())
	mod = null
	for m in s.bins.multipliers:
		if m is BlindnessStatus.BlindModifier:
			mod = m
	assert_null(mod, "cured to zero strips the modifier, same as a normal removal")
