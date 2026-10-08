extends GutTest

## The magic tray's infusion steppers: one per aspect the caster holds, capped
## by the aspect stat, the caster's `infusion_slots` / `infusion_points` and the
## spell's `infusion_capacity`; the affinity line reads the resulting affinity; the
## seat remembers the last infusion per spell, clamped to today's caps.

const _VENOM: SpellDef = preload("res://attack/spell/defs/venom.tres")
const _SPARK: SpellDef = preload("res://attack/spell/defs/spark.tres")
const _ROW_SCENE := preload("res://ui/hud/command_tray/bodies/infusion_row.tscn")
const _LINE_SCENE := preload("res://ui/hud/command_tray/bodies/affinity_line.tscn")
const _BODY_SCENE := preload("res://ui/hud/command_tray/bodies/magic_body.tscn")
const _POISON_STATUS: StatusDef = preload("res://effects/status/poison.tres")
const _STUB_ARM := preload("res://test/fixtures/stub_arm.gd")

var h: SpellTestHelper


func before_each() -> void:
	h = SpellTestHelper.new()


## INT 100 → 1 infusion slot and 10 infusion points; every aspect zeroed but
## poison, which holds [param poison].
func _caster(poison: float) -> Entity:
	var graph := h.make_graph([[0, 1]], self)
	var atk := h.make_entity(graph, "ATK", Color.RED)
	var board := atk.stat_board
	board.intelligence.base_value = 100.0
	for aspect in AspectRoster.shared().aspects:
		if aspect.stat != null and board.get_stat(aspect.stat.id) != null:
			board.get_stat(aspect.stat.id).base_value = 0.0
	board.poison_aspect.base_value = poison
	assert_eq(AspectCurrency.cap_of(atk, &"infusion_slots"), 1, "guard: INT 100 → 1 slot")
	assert_eq(AspectCurrency.cap_of(atk, &"infusion_points"), 10, "guard: INT 100 → 10 points")
	return atk


func _plan(caster: Entity, spell: SpellDef = _VENOM) -> MagicAttackPlan:
	var plan := MagicAttackPlan.new()
	plan.attacker = caster
	plan.set_spell(spell)
	return plan


func _row(plan: MagicAttackPlan) -> InfusionRow:
	var row: InfusionRow = _ROW_SCENE.instantiate()
	add_child_autofree(row)
	row.bind(plan)
	return row


func test_one_poison_stepper_capped_at_the_aspect_stat() -> void:
	var plan := _plan(_caster(2.0))
	var row := _row(plan)
	assert_eq(row.stepper_ids(), [&"poison"] as Array[StringName], "one stepper per held aspect")
	assert_eq(row.value_text(&"poison"), "0 / 2")
	row.plus_button(&"poison").pressed.emit()
	row.plus_button(&"poison").pressed.emit()
	assert_eq(plan.infusion.points.get(&"poison", 0), 2, "stepping writes the plan")
	assert_eq(row.value_text(&"poison"), "2 / 2")
	assert_true(row.plus_button(&"poison").disabled, "greyed at the aspect cap")
	assert_string_contains(row.plus_button(&"poison").tooltip_text.to_lower(), "aspect")
	assert_eq(row.header_text(), "slots 1/1 · points 2/10")
	assert_eq(plan.aspect_overrun(), 0, "the row never overruns")
	row.minus_button(&"poison").pressed.emit()
	assert_eq(plan.infusion.points.get(&"poison", 0), 1, "minus steps back")


func test_the_points_pool_stops_the_stepper_before_a_deep_aspect() -> void:
	var plan := _plan(_caster(100.0))
	var row := _row(plan)
	for i in 15:
		row.plus_button(&"poison").pressed.emit()
	assert_eq(plan.infusion.points.get(&"poison", 0), 10, "infusion_points 10 caps a 100 aspect")
	assert_true(row.plus_button(&"poison").disabled)
	assert_string_contains(row.plus_button(&"poison").tooltip_text.to_lower(), "points")
	assert_eq(plan.aspect_overrun(), 0)


func test_the_spells_capacity_caps_below_the_pool() -> void:
	var spell := _VENOM.duplicate() as SpellDef
	spell.infusion_capacity = 4.0
	var plan := _plan(_caster(100.0), spell)
	var row := _row(plan)
	for i in 15:
		row.plus_button(&"poison").pressed.emit()
	assert_eq(plan.infusion.points.get(&"poison", 0), 4, "infusion_capacity 4")
	assert_eq(row.header_text(), "slots 1/1 · points 4/4")


func test_the_affinity_line_reads_the_infused_affinity() -> void:
	var caster := _caster(2.0)
	var plan := _plan(caster)
	var row := _row(plan)
	var line: AffinityLine = _LINE_SCENE.instantiate()
	add_child_autofree(line)
	line.bind(plan)
	row.plus_button(&"poison").pressed.emit()
	row.plus_button(&"poison").pressed.emit()
	# venom: innate 5 + floor(2 points × rate 2) = 9, through the landing's fold.
	var stacks := _POISON_STATUS.stacks_per_hit(caster.stat_board, 9.0)
	assert_true(line.visible, "venom lands poison, so the line shows")
	assert_eq(line.text(), "Poison %s/hit" % NumFmt.num(stacks))


func test_the_seat_remembers_the_infusion_per_spell_clamped_to_todays_caps() -> void:
	var caster := _caster(2.0)
	var plan := _plan(caster)
	var stack: ArmedStack = _STUB_ARM.stack_holding(plan)
	autofree(stack)
	stack.selected_spell = _VENOM
	plan.set_infusion(&"poison", 2)
	stack.selected_spell = _SPARK
	assert_eq(plan.infusion.points.get(&"poison", 0), 0, "another spell starts from its own memory")
	stack.selected_spell = _VENOM
	assert_eq(plan.infusion.points.get(&"poison", 0), 2, "back to venom restores its infusion")
	stack.selected_spell = _SPARK
	caster.stat_board.poison_aspect.base_value = 1.0
	stack.selected_spell = _VENOM
	assert_eq(plan.infusion.points.get(&"poison", 0), 1, "restored, clamped to today's aspect")
	assert_eq(plan.aspect_overrun(), 0)


func test_a_fresh_plan_with_the_sticky_spell_gets_its_memory() -> void:
	var caster := _caster(2.0)
	var first := _plan(caster)
	var stack: ArmedStack = _STUB_ARM.stack_holding(first)
	autofree(stack)
	stack.selected_spell = _VENOM
	first.set_infusion(&"poison", 2)
	stack.cancel_attack()
	var second := _plan(caster)
	stack.push(_STUB_ARM.new(second))
	assert_eq(second.infusion.points.get(&"poison", 0), 2, "a repeat cast needs no clicks")


func test_the_magic_body_hosts_the_row() -> void:
	var body: MagicBody = _BODY_SCENE.instantiate()
	add_child_autofree(body)
	assert_not_null(body.get_node_or_null("%InfusionRow") as InfusionRow)
