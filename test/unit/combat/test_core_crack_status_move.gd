extends GutTest

## A cracked core hands its statuses to the entity: the hit that takes the
## core node's HP from > 0 to <= 0 moves EVERY row on it onto its owner's
## [EntityCombat] host — stacks added into a same-def row, gated by the
## entity's resistance, no removal spill (a move, not a death), and nothing
## moves back when the shell regens. The crack is reproduced on a replay
## because the recorded damage lands through the same door.
##
## Fixture: core(N0) - N1, one entity. Numbers are read off the boards at
## runtime, never pinned.

const _POISON_DEF: StatusDef = preload("res://effects/status/poison.tres")
const _CORRUPTION_DEF: StatusDef = preload("res://effects/status/corruption.tres")
## A removal-spill def ([SpillSpread]): it spills only when a row is removed
## by a strip — never when it moves.
const _BLEEDING_DEF: StatusDef = preload("res://effects/status/bleeding.tres")

var _w: TestWorld
var _graph: Graph
var _entity: Entity
var _n0: SkillNode  # core
var _n1: SkillNode
var _worlds: Array[CombatWorld] = []


func before_each() -> void:
	_worlds = []
	_w = TestWorld.create(self)
	_graph = _w.graph
	_n0 = _w.add_node(&"N0")
	_n1 = _w.add_node(&"N1")
	_w.link(_n0, _n1)
	await get_tree().process_frame
	_entity = _w.add_entity("Defender")
	await get_tree().process_frame
	var alloc := _w.allocator()
	for n in [_n0, _n1]:
		alloc.force_allocate(_entity, n)
	_entity.core_location = _n0


func after_each() -> void:
	for w in _worlds:
		w.free_shadow()


func _core() -> NodeCombat:
	return _n0.get_combat()


func _ec() -> EntityCombat:
	return _entity.get_combat()


## A hit of exactly the core's current HP plus armor headroom: enough to crack
## it, small enough that the overflow leaves the entity alive.
func _crack_hit() -> DamageInstance:
	var hit := DamageInstance.new()
	hit.target = _n0
	hit.amount = _core().get_current_hp() + 2.0 * float(_core().get_local_value(&"armor"))
	return hit


func _crack(world: CombatWorld = CombatWorld.live()) -> AttackOutcome:
	var outcome := AttackOutcome.new()
	outcome.hits.append(_crack_hit())
	OutcomeApplier.apply(outcome, world)
	return outcome


func _add_base(stat_id: StringName, value: float) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = stat_id
	m.operation = StatModifier.Operation.ADD_BASE
	m.value = value
	return m


func _rows(c) -> Dictionary:
	var out := {}
	for row in c.get_statuses():
		out[[row.def.id, row.key]] = row.power
	return out


# ── Acceptance 1: the crack moves the row

func test_a_cracked_core_moves_its_poison_to_the_entity() -> void:
	_core().apply_status(_POISON_DEF, 3.0)
	var stacks := _core().get_status_power(_POISON_DEF.id)
	assert_gt(stacks, 0.0, "precondition: the core holds poison")
	_crack()
	assert_lte(_core().get_current_hp(), 0.0, "precondition: the core cracked")
	assert_false(_entity.is_dead, "precondition: the overflow left the entity alive")
	assert_almost_eq(_ec().get_status_power(_POISON_DEF.id), stacks, 0.0001,
			"the entity holds the core's poison stacks")
	assert_almost_eq(_core().get_status_power(_POISON_DEF.id), 0.0, 0.0001,
			"the core node holds none")


# ── Acceptance 2: a same-def entity row adds

func test_a_moved_row_adds_into_the_entitys_same_def_row() -> void:
	_ec().apply_status(_POISON_DEF, 2.0)
	var on_entity := _ec().get_status_power(_POISON_DEF.id)
	_core().apply_status(_POISON_DEF, 3.0)
	var on_core := _core().get_status_power(_POISON_DEF.id)
	_crack()
	assert_almost_eq(_ec().get_status_power(_POISON_DEF.id), on_entity + on_core, 0.0001,
			"the stacks add: entity row + moved row")


# ── Acceptance 3: entity resistance drops the row (tentative pick)

func test_entity_resistance_blocks_the_move_and_drops_the_row() -> void:
	_core().apply_status(_POISON_DEF, 3.0)
	_entity.stat_board.add_modifier(_add_base(_POISON_DEF.resistance_stat_id(), 1.0))
	assert_true(_ec().blocks_status(_POISON_DEF), "precondition: the entity blocks poison")
	assert_gt(_core().get_status_power(_POISON_DEF.id), 0.0, "precondition: the core still holds its row")
	_crack()
	assert_almost_eq(_ec().get_status_power(_POISON_DEF.id), 0.0, 0.0001,
			"the resisting entity receives nothing")
	assert_almost_eq(_core().get_status_power(_POISON_DEF.id), 0.0, 0.0001,
			"the row is dropped, not left on the node")


# ── Acceptance 4: a move is not a removal — no spill

func test_a_moved_row_never_spills_to_the_neighbours() -> void:
	_core().apply_status(_BLEEDING_DEF, 4.0)
	var stacks := _core().get_status_power(_BLEEDING_DEF.id)
	_crack()
	assert_almost_eq(_ec().get_status_power(_BLEEDING_DEF.id), stacks, 0.0001,
			"the bleeding moved whole")
	assert_almost_eq(_n1.get_combat().get_status_power(_BLEEDING_DEF.id), 0.0, 0.0001,
			"no removal spill reached the neighbour")
	assert_false(CombatWorld.live().has_pending_removals(), "nothing was noted as removed")


# ── Acceptance 5: regen then re-crack moves only the new rows

func test_regen_then_recrack_moves_only_what_landed_since() -> void:
	_core().apply_status(_POISON_DEF, 3.0)
	var first := _core().get_status_power(_POISON_DEF.id)
	_crack()
	_core().heal_damage(_core().get_max_hp(), null, true)
	assert_gt(_core().get_current_hp(), 0.0, "precondition: the shell regenerated")
	assert_almost_eq(_core().get_status_power(_POISON_DEF.id), 0.0, 0.0001,
			"nothing moved back on the regen")
	assert_almost_eq(_ec().get_status_power(_POISON_DEF.id), first, 0.0001,
			"the entity kept the first crack's rows")
	_core().apply_status(_POISON_DEF, 2.0)
	var second := _core().get_status_power(_POISON_DEF.id)
	_crack()
	assert_almost_eq(_ec().get_status_power(_POISON_DEF.id), first + second, 0.0001,
			"the re-crack moved only the rows landed since")


func test_damage_on_an_already_cracked_core_moves_nothing_again() -> void:
	_crack()
	_ec().apply_status(_POISON_DEF, 2.0)
	var before := _rows(_ec())
	_crack()
	assert_eq(_rows(_ec()), before, "no crack transition: the core was already at 0")


# ── Acceptance 6: shadow resolve and live replay agree

func test_the_shadow_resolve_and_the_live_replay_leave_identical_entity_rows() -> void:
	_core().apply_status(_POISON_DEF, 3.0)
	_core().apply_status(_CORRUPTION_DEF, 2.0)
	var shadow := CombatWorld.shadow()
	_worlds.append(shadow)
	var outcome := _crack(shadow)
	var shadow_rows := _rows(shadow.combat_for(_n0).owner())
	assert_false(shadow_rows.is_empty(), "precondition: the shadow moved the rows")
	assert_true(_rows(_ec()).is_empty(), "precondition: the shadow left the live entity untouched")
	var wired: Dictionary = bytes_to_var(var_to_bytes(AttackRecord.capture(outcome, _graph)))
	OutcomeApplier.apply(AttackRecord.rebuild(wired, _graph), CombatWorld.live())
	assert_eq(_rows(_ec()), shadow_rows, "the replay reproduced the move, row for row")
	assert_eq(_rows(_core()), {}, "the live core holds nothing after the replay")
