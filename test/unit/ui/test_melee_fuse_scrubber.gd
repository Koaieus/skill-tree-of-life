extends GutTest

## #1210: the melee body's multi-marker fuse scrubber. One marker per fusable
## gate in the blade, linked by default (one drag moves them all); a split drag
## moves one alone, re-linking snaps the rest to the last dragged. The scrubber
## writes the plan only through its fuse setters, and the prediction's stranded
## union drives both the warning chip and the gate-cut highlight.
##
## Board (all the attacker's, core = Pivot), from test_gate_fuse.gd:
##   Pivot – B1 =G1= B2 – B3        (a G1 fuse strands B2, B3)
##   Pivot – C1 =G2= C2

var _catalog: TempUpgradeCatalog = preload("res://attack/melee/temp_upgrade_catalog.tres")

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _MELEE_BODY := preload("res://ui/hud/command_tray/bodies/melee_body.tscn")
const _SPACING := 150.0

var _graph: Graph
var _alloc: AllocationSystem
var _battle: BattleSystem
var _tm: TurnManager
var _ctl: PlayerInputController
var _highlight: HighlightController
var _attacker: Entity
var _n: Dictionary = {}
var _g1: Gate
var _g2: Gate


func _spawn(nm: String, pos: Vector2) -> SkillNode:
	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	sn.name = nm
	_graph.add_skill_node(sn)
	sn.global_position = pos
	_n[nm] = sn
	return sn


func before_each() -> void:
	_n = {}
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	_alloc.navigator = _graph.navigator
	add_child_autofree(_alloc)
	_tm = autofree(TurnManager.new())
	add_child(_tm)
	_alloc.turn_manager = _tm
	_battle = autofree(BattleSystem.new())
	_battle.temp_upgrade_catalog = _catalog
	_battle.graph = _graph
	_battle.turn_manager = _tm
	add_child(_battle)

	_attacker = Entity.new()
	_attacker.display_name = "Player"
	_attacker.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_attacker.stat_board.get_stat(&"crit_chance").base_value = 0.0
	_attacker.turns_taken = 1
	_graph.entities_container.add_child(_attacker)
	_attacker.stat_board.blade_size.base_value = 5.0
	_attacker.stat_board.action_points.base_value = 4.0
	_attacker.stat_board.action_points.current = 4.0
	_tm.start_turn(_attacker)

	_spawn("Pivot", Vector2.ZERO)
	_spawn("B1", Vector2(_SPACING, 0.0))
	_spawn("B2", Vector2(_SPACING * 2.0, 0.0))
	_spawn("B3", Vector2(_SPACING * 3.0, 0.0))
	_spawn("C1", Vector2(0.0, _SPACING))
	_spawn("C2", Vector2(0.0, _SPACING * 2.0))
	_graph.add_edge(_n["Pivot"], _n["B1"])
	_graph.add_edge(_n["B2"], _n["B3"])
	_graph.add_edge(_n["Pivot"], _n["C1"])
	_g1 = _graph.add_gate(_n["B1"], _n["B2"], true)
	_g2 = _graph.add_gate(_n["C1"], _n["C2"], true)
	await get_tree().process_frame
	await get_tree().physics_frame
	for id in ["Pivot", "B1", "B2", "B3", "C1", "C2"]:
		_alloc.force_allocate(_attacker, _n[id])
	_attacker.core_location = _n["Pivot"]

	_ctl = PlayerInputController.new()
	_ctl.graph = _graph
	_ctl.allocation_system = _alloc
	_ctl.battle_system = _battle
	_ctl.turn_manager = _tm
	_ctl.player = _attacker
	add_child_autofree(_ctl)

	_highlight = HighlightController.new()
	_highlight.battle_system = _battle
	add_child_autofree(_highlight)


## The body bound to a melee plan whose blade is [param members].
func _mount(members: Array[String]) -> MeleeBody:
	_battle.request_attack_mode(BattleSystem.AttackMode.MELEE)
	var plan := _plan()
	assert_not_null(plan, "fixture: melee is the active plan")
	plan.attacker = _attacker
	plan.source = _n["Pivot"]
	var blade: Array[SkillNode] = []
	for id in members:
		blade.append(_n[id])
	plan.blade_nodes = blade
	assert_true(plan.is_valid(), "fixture: the blade is a valid plan")
	var body := _MELEE_BODY.instantiate() as MeleeBody
	add_child_autofree(body)
	await get_tree().process_frame
	body.bind(_attacker, _battle, _ctl)
	await get_tree().process_frame
	return body


func _plan() -> MeleeAttackPlan:
	return _battle.attack_plan as MeleeAttackPlan


func _scrubber(body: MeleeBody) -> FuseScrubber:
	return body.get_node("%FuseScrubber") as FuseScrubber


func _names(nodes: Array) -> Array[String]:
	var out: Array[String] = []
	for n in nodes:
		out.append(String((n as SkillNode).name))
	out.sort()
	return out


# ── acceptance 1 ─────────────────────────────────────────────────────────────

func test_the_scrubber_is_hidden_without_a_fusable_gate() -> void:
	var body := await _mount(["B1"] as Array[String])
	assert_true(_plan().fusable_gates().is_empty(), "fixture: no gate inside this blade")
	assert_false(_scrubber(body).visible, "no fusable gate, no scrubber")


func test_the_scrubber_shows_with_a_fusable_gate() -> void:
	var body := await _mount(["B1", "B2", "B3"] as Array[String])
	assert_eq(_plan().fusable_gates(), [_g1] as Array[Gate], "fixture: G1 is fusable")
	assert_true(_scrubber(body).visible, "a fusable gate shows the scrubber")


func test_a_scrub_sets_the_fuse_and_reruns_the_prediction_once() -> void:
	var body := await _mount(["B1", "B2", "B3", "C1", "C2"] as Array[String])
	var plan := _plan()
	var runs := plan.prediction_runs
	_scrubber(body).drag(_g1, 0.5)
	assert_almost_eq(plan.gate_fuse(_g1), 0.5, 1e-6, "the scrub lands on the plan")
	assert_not_null(plan.prediction(), "the fused swing is predicted")
	assert_eq(plan.prediction_runs - runs, 1, "one scrub, one prediction run")


func test_a_stranding_fuse_shows_the_chip_and_the_highlight_and_clear_drops_both() -> void:
	var body := await _mount(["B1", "B2", "B3"] as Array[String])
	var scrubber := _scrubber(body)
	scrubber.drag(_g1, 0.5)
	await get_tree().process_frame
	var p := _plan().prediction()
	assert_not_null(p, "the fused swing is predicted")
	if p == null:
		return
	assert_eq(_names(p.predicted_stranded()), ["B2", "B3"] as Array[String],
			"fixture: a G1 fuse strands B2 and B3")
	assert_eq(scrubber.stranded_count(), 2, "the chip counts the predicted set")
	assert_true(scrubber.get_node("%Chip").visible, "the chip shows")
	var provider := _highlight.provider
	assert_true(provider is GateCutHighlightProvider, "the fuse warning drives the gate-cut provider")
	assert_eq(provider.get_node_role(_n["B3"]), HighlightProvider.HighlightRole.FORFEIT,
			"a stranded node lights")
	assert_eq(provider.get_node_role(_n["B1"]), _plan().get_node_role(_n["B1"]),
			"a kept node reads the plan's own role underneath")

	scrubber.clear()
	await get_tree().process_frame
	assert_true(_plan().gate_fuses().is_empty(), "clear is fuse off")
	assert_false(scrubber.get_node("%Chip").visible, "the chip goes")
	assert_eq(_highlight.provider, _plan() as HighlightProvider, "the plan paints alone again")
	assert_eq(_highlight.provider.get_node_role(_n["B3"]),
			_plan().get_node_role(_n["B3"]), "no stranded light survives the clear")


# ── amendment: linked by default, split, re-link ─────────────────────────────

func test_a_linked_drag_moves_every_marker() -> void:
	var body := await _mount(["B1", "B2", "B3", "C1", "C2"] as Array[String])
	var plan := _plan()
	assert_eq(plan.fusable_gates().size(), 2, "fixture: two fusable gates")
	_scrubber(body).drag(_g2, 0.4)
	assert_almost_eq(plan.gate_fuse(_g1), 0.4, 1e-6, "G1 moved with the drag")
	assert_almost_eq(plan.gate_fuse(_g2), 0.4, 1e-6, "G2 moved with the drag")


func test_a_split_marker_moves_alone() -> void:
	var body := await _mount(["B1", "B2", "B3", "C1", "C2"] as Array[String])
	var plan := _plan()
	var scrubber := _scrubber(body)
	scrubber.drag(_g1, 0.4)
	scrubber.drag(_g2, 0.8, true)
	assert_almost_eq(plan.gate_fuse(_g1), 0.4, 1e-6, "G1 stays where the linked drag left it")
	assert_almost_eq(plan.gate_fuse(_g2), 0.8, 1e-6, "the split G2 moved alone")
	scrubber.drag(_g1, 0.2)
	assert_almost_eq(plan.gate_fuse(_g1), 0.2, 1e-6, "the linked group moves")
	assert_almost_eq(plan.gate_fuse(_g2), 0.8, 1e-6, "the split marker does not follow it")


func test_relinking_snaps_the_markers_to_the_dragged_one() -> void:
	var body := await _mount(["B1", "B2", "B3", "C1", "C2"] as Array[String])
	var plan := _plan()
	var scrubber := _scrubber(body)
	scrubber.drag(_g1, 0.4)
	scrubber.drag(_g2, 0.8, true)
	scrubber.relink()
	assert_almost_eq(plan.gate_fuse(_g1), 0.8, 1e-6, "G1 snaps to the last dragged marker")
	assert_almost_eq(plan.gate_fuse(_g2), 0.8, 1e-6, "G2 keeps its time")
	scrubber.drag(_g1, 0.1)
	assert_almost_eq(plan.gate_fuse(_g2), 0.1, 1e-6, "linked again: one drag moves both")
