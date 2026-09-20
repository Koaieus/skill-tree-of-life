extends GutTest

## #997 (hub #994), owner 2026-09-20: an entity-hosted modifier status plants
## on the ENTITY board — entity-wide by construction, because every node's
## combined read is `[entity.bins, node.bins]`. One proof per def (Blindness,
## ArmorBreak, Curse, Wither), each with the shadow-isolation assert: the
## entity board's static modifiers are SHARED with a shadow clone
## (`StatBoard._localize` copies only formula-bearing ones), so a shadow
## resolve must replace, never edit, the found modifier. Hand-built defs —
## the authored `.tres` values are the owner's knobs.
##
## Fixture: core(N0) - N1, one entity. N1 is the non-core node every
## "every node" claim is checked on.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

var _graph: Graph
var _alloc: AllocationSystem
var _entity: Entity
var _n0: SkillNode
var _n1: SkillNode
var _shadows: Array[EntityCombat] = []


func before_each() -> void:
	_shadows = []
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_n0 = _new_node("N0")
	_n1 = _new_node("N1")
	_graph.add_edge(_n0, _n1)
	await get_tree().process_frame

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_entity = autofree(Entity.new())
	_entity.display_name = "Hosted"
	_entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.entities_container.add_child(_entity)
	await get_tree().process_frame

	for n in [_n0, _n1]:
		_alloc.force_allocate(_entity, n)
	_entity.core_location = _n0


func after_each() -> void:
	for s in _shadows:
		s.free_shadow()


func _new_node(n: String) -> SkillNode:
	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	sn.name = n
	_graph.add_skill_node(sn)
	return sn


func _combat() -> EntityCombat:
	return _entity.get_combat()


func _shadow() -> EntityCombat:
	var s := _combat().snapshot()
	_shadows.append(s)
	return s


## The planted modifiers of class [param cls] on the LIVE entity board's stat.
func _entity_mods(stat_id: StringName, cls: Script) -> Array[StatModifier]:
	var out: Array[StatModifier] = []
	var s: Stat = _entity.stat_board.get_stat(stat_id)
	if s == null:
		return out
	for m in s._modifiers:
		if is_instance_of(m, cls):
			out.append(m)
	return out


func _decaying(def: StatusDef) -> StatusDef:
	def.power_max = 0.0
	def.decay_mode = StatusDef.DecayMode.FRACTION
	def.decay_per_tick = 0.5
	def.reapply = StatusDef.Reapply.ACCUMULATE
	return def


# ── Blindness ───────────────────────────────────────────────────────────────

func test_entity_blindness_halves_every_nodes_combined_vision_range() -> void:
	var def := BlindnessStatus.new()
	def.id = &"blindness"
	def.blind_factor = 0.5
	def.power_max = 10.0
	def.decay_mode = StatusDef.DecayMode.FRACTION
	def.decay_per_tick = 0.5
	var v0 := float(_n0.get_local_value(&"vision_range"))
	var v1 := float(_n1.get_local_value(&"vision_range"))
	assert_gt(v1, 0.0)
	_combat().apply_status(def, 10.0)
	assert_almost_eq(float(_n0.get_local_value(&"vision_range")), v0 * 0.5, 0.001, "the core reads the entity-wide blind")
	assert_almost_eq(float(_n1.get_local_value(&"vision_range")), v1 * 0.5, 0.001, "a non-core node reads it too")
	var live := _entity_mods(&"vision_range", BlindnessStatus.BlindModifier)
	assert_eq(live.size(), 1, "planted on the ENTITY board")
	if live.is_empty():
		return
	var live_value: float = live[0].value

	var shadow := _shadow()
	shadow.apply_status(def, 10.0)  # ACCUMULATE is not set: max(10, 10)
	shadow.remove_status(&"blindness")
	assert_almost_eq(live[0].value, live_value, 0.001, "the live modifier instance is untouched by a shadow resolve")
	assert_eq(_entity_mods(&"vision_range", BlindnessStatus.BlindModifier).size(), 1, "live bin unchanged")
	assert_almost_eq(float(_n1.get_local_value(&"vision_range")), v1 * 0.5, 0.001, "live world still blinded")


# ── ArmorBreak ──────────────────────────────────────────────────────────────

func test_entity_armor_break_multiplies_every_nodes_armor() -> void:
	var def := ArmorBreakStatus.new()
	def.id = &"armor_break"
	def.power_max = 1.0
	def.decay_mode = StatusDef.DecayMode.FRACTION
	def.decay_per_tick = 0.5
	_entity.stat_board.get_stat(&"armor").base_value = 8.0
	assert_almost_eq(float(_n1.get_local_value(&"armor")), 8.0, 0.001)
	_combat().apply_status(def, 0.5)
	assert_almost_eq(float(_n0.get_local_value(&"armor")), 4.0, 0.001, "core armor × (1 − 0.5)")
	assert_almost_eq(float(_n1.get_local_value(&"armor")), 4.0, 0.001, "non-core armor × (1 − 0.5)")
	var live := _entity_mods(&"armor", ArmorBreakStatus.ArmorBreakModifier)
	assert_eq(live.size(), 1)
	if live.is_empty():
		return
	var live_value: float = live[0].value

	var shadow := _shadow()
	shadow.apply_status(def, 1.0)
	assert_almost_eq(float(shadow.get_local_value(&"armor")), 0.0, 0.001, "the shadow reads its own full break")
	assert_almost_eq(live[0].value, live_value, 0.001, "the live modifier instance is untouched")
	assert_almost_eq(float(_n1.get_local_value(&"armor")), 4.0, 0.001, "live world unchanged")


# ── Curse ───────────────────────────────────────────────────────────────────

func test_entity_curse_raises_the_floor_on_a_non_core_nodes_hit() -> void:
	var def := _decaying(CurseStatus.new()) as CurseStatus
	def.id = &"curse"
	# armor 100 soaks any small hit, so a PHYSICAL hit lands exactly at the floor.
	_entity.stat_board.get_stat(&"armor").base_value = 100.0
	_entity.stat_board.get_stat(&"min_damage_taken").base_value = 1.0
	_combat().apply_status(def, 4.0)
	assert_almost_eq(float(_n1.get_local_value(&"min_damage_taken")), 5.0, 0.001, "1 + 4 stacks on the non-core node")
	var hp_before := _n1.get_current_hp()
	var hit := DamageInstance.new()
	hit.type = DamageInstance.Type.PHYSICAL
	hit.amount = 1.0
	_n1.get_combat().take_damage(1.0, hit)
	assert_almost_eq(_n1.get_current_hp(), hp_before - 5.0, 0.001, "the hit on N1 lands at the cursed floor")
	var live := _entity_mods(&"min_damage_taken", CurseStatus.CurseModifier)
	assert_eq(live.size(), 1)
	if live.is_empty():
		return
	var live_value: float = live[0].value

	var shadow := _shadow()
	shadow.apply_status(def, 10.0)
	assert_almost_eq(float(shadow.get_local_value(&"min_damage_taken")), 15.0, 0.01, "the shadow reads its own 14 stacks")
	assert_almost_eq(live[0].value, live_value, 0.001, "the live modifier instance is untouched")
	assert_almost_eq(float(_n1.get_local_value(&"min_damage_taken")), 5.0, 0.001, "live world unchanged")


# ── Wither ──────────────────────────────────────────────────────────────────

func test_entity_wither_multiplies_a_non_core_nodes_heal() -> void:
	var def := _decaying(WitherStatus.new()) as WitherStatus
	def.id = &"wither"
	def.factor_per_stack = 0.1
	_combat().apply_status(def, 5.0)
	assert_almost_eq(float(_n1.get_local_value(&"healing_received")), 0.5, 0.001, "1 − 0.5 on the non-core node")
	var crack := DamageInstance.new()
	crack.type = DamageInstance.Type.TRUE
	crack.amount = 6.0
	_n1.get_combat().take_damage(6.0, crack)
	var before := _n1.get_current_hp()
	_n1.get_combat().heal_damage(4.0, null)
	assert_almost_eq(_n1.get_current_hp(), before + 2.0, 0.001, "4 × 0.5 = 2 healed on N1")
	var live := _entity_mods(&"healing_received", WitherStatus.WitherModifier)
	assert_eq(live.size(), 1)
	if live.is_empty():
		return
	var live_value: float = live[0].value

	var shadow := _shadow()
	shadow.apply_status(def, 10.0)
	assert_almost_eq(float(shadow.get_local_value(&"healing_received")), -0.5, 0.001, "the shadow reads its own 15 stacks")
	assert_almost_eq(live[0].value, live_value, 0.001, "the live modifier instance is untouched")
	assert_almost_eq(float(_n1.get_local_value(&"healing_received")), 0.5, 0.001, "live world unchanged")
