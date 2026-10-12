extends GutTest

## [ReadoutLines]: one line per aspect in play — socketed first, in socket
## order, then innate-only — whose numbers are the plan's own
## ([method Infusion.affinity_of] through [method StatusDef.stacks_per_hit]).

const _VENOM: SpellDef = preload("res://attack/spell/defs/venom_burst.tres")
const _POISON_STATUS: StatusDef = preload("res://effects/status/poison.tres")

var h: SpellTestHelper


func before_each() -> void:
	h = SpellTestHelper.new()


## INT 100 → 1 infusion slot; every aspect zeroed but poison, which holds [param poison].
func _caster(poison: float) -> Entity:
	var graph := h.make_graph([[0, 1]], self)
	var atk := h.make_entity(graph, "ATK", Color.RED)
	var board := atk.stat_board
	board.intelligence.base_value = 100.0
	for aspect in AspectRoster.shared().aspects:
		if aspect.stat != null and board.get_stat(aspect.stat.id) != null:
			board.get_stat(aspect.stat.id).base_value = 0.0
	board.facet(&"poison", StatDef.Role.ASPECT).base_value = poison
	return atk


func _plan(caster: Entity) -> MagicAttackPlan:
	var plan := MagicAttackPlan.new()
	plan.attacker = caster
	plan.set_spell(_VENOM)
	return plan


func test_venom_with_40_poison_socketed_reads_innate_plus_infused() -> void:
	var caster := _caster(40.0)
	var plan := _plan(caster)
	plan.set_socket(0, &"poison")
	assert_eq(plan.infusion.points.get(&"poison", 0), 40, "guard: 40 points socketed")
	var aff: SpellAffinity = _VENOM.affinities[0]
	assert_eq(aff.innate, 15, "guard: venom's innate poison")
	assert_almost_eq(aff.rate, 2.0, 0.001, "guard: venom's poison rate")
	var lines := ReadoutLines.lines(plan)
	assert_eq(lines.size(), 1, "one aspect in play")
	if lines.size() != 1:
		return
	var line := lines[0]
	assert_eq(line.aspect_id, &"poison")
	assert_eq(line.socket, 0)
	assert_eq(line.points, 40)
	assert_eq(line.innate, 15)
	assert_eq(line.infused, 80)
	assert_eq(line.innate + line.infused, plan.infusion.affinity_of(_VENOM)[&"poison"],
			"the total is the plan's own affinity")
	assert_eq(line.per_hit, _POISON_STATUS.stacks_per_hit(caster.stat_board, 95.0),
			"per hit folds through stacks_per_hit")
	assert_eq(line.status, _POISON_STATUS)


func test_an_innate_only_aspect_yields_a_line_with_no_socket() -> void:
	var caster := _caster(0.0)
	var plan := _plan(caster)
	var lines := ReadoutLines.lines(plan)
	assert_eq(lines.size(), 1, "venom's innate poison is in play with nothing socketed")
	if lines.size() != 1:
		return
	assert_eq(lines[0].socket, -1)
	assert_eq(lines[0].innate, 15)
	assert_eq(lines[0].infused, 0)
	assert_eq(lines[0].points, 0)


func test_previewing_a_socket_reads_the_plan_as_if_socketed() -> void:
	var caster := _caster(40.0)
	var plan := _plan(caster)
	var preview := ReadoutLines.preview(plan, 0, &"poison")
	assert_eq(plan.infusion.points.size(), 0, "a preview never writes the plan")
	assert_eq(preview.size(), 1)
	if preview.size() != 1:
		return
	assert_eq(preview[0].socket, 0)
	assert_eq(preview[0].infused, 80)


func test_a_socketed_line_reads_its_exchange_and_phrase() -> void:
	var caster := _caster(40.0)
	var plan := _plan(caster)
	plan.set_socket(0, &"poison")
	var line := ReadoutLines.lines(plan)[0]
	assert_eq(line.exchange(_VENOM), InfusionExchange.line(_VENOM, &"poison", 40))
	assert_eq(line.text(), "+ applies %s poison stacks per hit (15 innate + 80 infused)"
			% NumFmt.num(line.per_hit))
