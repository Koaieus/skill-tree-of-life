extends GutTest

## [HexStatus]: every stack plants one node-local ADD_BONUS of
## `-resist_per_stack × stacks` on `status_resistance`, the family parent of
## every `<aspect>_resistance`, so one modifier shreds them all. Below 0 the
## node is vulnerable: [method StatusHost.effective_power] lands MORE than the
## row. Flat decay walks the modifier down; removal strips it. Same
## found-modifier shape as Wither: replace, never mutate, so a shadow resolve
## never writes the live board. Authored `hexed.tres` values are the owner's
## knobs and are never pinned here.

const _BOARD := preload("res://entity/default_entity_board.tres")
const HexModifier := preload("res://effects/status/modifiers/hex_modifier.gd")
const _POISON := preload("res://effects/status/poison.tres")

var _w: TestWorld
var _entity: Entity
var _node: SkillNode
var _def: HexStatus
var _shadows: Array[EntityCombat] = []


func before_each() -> void:
	_shadows = []
	_w = TestWorld.create(self)
	var alloc := _w.allocator()
	_entity = _w.add_entity("Hexed", _BOARD.duplicate(true) as EntityStatBoard)
	_node = _w.add_node(StringName("N0"))
	await get_tree().process_frame
	alloc.force_allocate(_entity, _node)
	_entity.core_location = _node

	_def = HexStatus.new()
	_def.id = &"hex"
	_def.resist_per_stack = 0.1
	_def.power_max = 0.0
	_def.decay = FlatDecay.new()
	_def.reapply = StatusDef.Reapply.ACCUMULATE


func after_each() -> void:
	for sh in _shadows:
		sh.free_shadow()


func _combat() -> NodeCombat:
	return _node.get_combat()


func _res(stat_id: StringName) -> float:
	return float(_node.get_local_value(stat_id))


func _hex_modifiers() -> Array[StatModifier]:
	var out: Array[StatModifier] = []
	var s: Stat = _node.node_board.get_stat(&"status_resistance") if _node.node_board != null else null
	if s == null:
		return out
	for m in s._modifiers:
		if m is HexModifier:
			out.append(m)
	return out


# ── Acceptance 1: the family parent reaches every child ──────────────────────

func test_five_stacks_strip_half_of_every_resistance() -> void:
	_entity.stat_board.get_stat(&"poison_resistance").base_value = 0.5
	_combat().apply_status(_def, 5.0)
	assert_almost_eq(_res(&"poison_resistance"), 0.0, 0.001, "0.5 - 0.1 × 5")
	assert_almost_eq(_res(&"curse_resistance"), -0.5, 0.001, "the parent reaches every child")
	_combat().apply_status(_def, 1.0)
	assert_eq(_hex_modifiers().size(), 1, "re-plant replaces, never stacks modifiers")
	assert_almost_eq(_res(&"curse_resistance"), -0.6, 0.001, "6 stacks")


# ── Acceptance 2: vulnerability lands more than was sent ────────────────────

func test_a_hexed_bare_node_lands_six_of_four_poison() -> void:
	_combat().apply_status(_def, 5.0)
	var host := StatusHost.new(_combat())
	assert_eq(host.effective_power(_POISON, 4.0), 6.0, "4 - ceil(4 × -0.5 - 0.5) = 6")


# ── Acceptance 3: one stack opens an immune node ────────────────────────────

func test_one_stack_opens_an_immune_node() -> void:
	_entity.stat_board.get_stat(&"poison_resistance").base_value = 1.0
	assert_true(_combat().blocks_status(_POISON), "100% blocks")
	_combat().apply_status(_def, 1.0)
	assert_almost_eq(_res(&"poison_resistance"), 0.9, 0.001)
	assert_false(_combat().blocks_status(_POISON), "90% no longer blocks")


# ── Acceptance 4: decay walks the shred down, removal restores exactly ──────

func test_decay_walks_the_modifier_down_and_removal_restores_the_base() -> void:
	_entity.stat_board.get_stat(&"poison_resistance").base_value = 0.3
	_combat().apply_status(_def, 2.0)
	assert_almost_eq(_res(&"poison_resistance"), 0.1, 0.001, "2 stacks")
	_combat().tick_statuses()
	assert_eq(_combat().get_status_power(&"hex"), 1.0)
	assert_almost_eq(_res(&"poison_resistance"), 0.2, 0.001, "1 stack after a flat tick")
	_combat().tick_statuses()
	assert_eq(_combat().get_status_power(&"hex"), 0.0, "removed")
	assert_eq(_res(&"poison_resistance"), 0.3, "base restored exactly")
	assert_eq(_hex_modifiers().size(), 0, "the modifier is stripped on removal")


# ── Acceptance 5: shadow apply never writes live ────────────────────────────

func test_shadow_apply_never_writes_the_live_modifier() -> void:
	_combat().apply_status(_def, 2.0)
	var live_mods := _hex_modifiers()
	assert_eq(live_mods.size(), 1)
	if live_mods.is_empty():
		return
	var live_value: float = live_mods[0].value

	var shadow_world := _entity.get_combat().snapshot()
	_shadows.append(shadow_world)
	var shadow := shadow_world.shadow_for(_node)
	shadow.apply_status(_def, 8.0)

	assert_almost_eq(float(shadow.get_local_value(&"poison_resistance")), -1.0, 0.001,
			"the shadow reads 10 stacks")
	assert_almost_eq(live_mods[0].value, live_value, 0.001,
			"the live modifier instance is untouched by the shadow resolve")
	assert_almost_eq(_res(&"poison_resistance"), -0.2, 0.001, "live world unchanged (still 2 stacks)")


# ── Acceptance 7: authored content loads and is wired ───────────────────────

func test_authored_hexed_loads_and_names_its_pair() -> void:
	var h := load("res://effects/status/hexed.tres") as HexStatus
	assert_not_null(h, "hexed.tres is a HexStatus")
	if h == null:
		return
	assert_eq(h.id, &"hex")
	assert_eq(h.stacks_stat_id(), &"hex_stacks_per_hit")
	assert_eq(h.resistance_stat_id(), &"", "hex has no resistance of its own")
	assert_true(h.tags.has(&"debuff"))
	assert_true(h.resist_per_stack > 0.0, "a per-stack shred is authored")
	assert_true(h.decay is FlatDecay)


func test_intelligence_pool_supplies_the_hex_aspect() -> void:
	var pack = load("res://procgen/pools/intelligence.tres")
	var found := false
	for p in pack.pools:
		if p != null and p.stat_id == &"hex_aspect":
			found = true
	assert_true(found, "intelligence.tres carries a hex_aspect supply entry")
