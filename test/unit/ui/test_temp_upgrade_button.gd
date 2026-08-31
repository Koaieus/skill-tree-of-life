extends GutTest

## #465 — the melee tab's temp-upgrade cards and the four mode tabs.
##
## The visual half of this issue (does the watermark compete with the label, does
## the ripple read as washing across it) cannot be judged headless and is
## deliberately NOT tested here. What IS pinned is everything a regression could
## silently undo without anyone noticing until playtest:
##
## - the cards are real scene INSTANCES, so a slide back to `Button.new()` fails;
## - their glyph and colour come from data already authored elsewhere (the addon
##   scene's `icon`, the shared `ActionPalette`) rather than from fresh literals;
## - "armed", "available" and "unaffordable" are three distinguishable answers
##   rather than the one grey `Button.disabled` used to collapse them into;
## - the three attack tabs read their tint from `StatDef.tint_color` instead of
##   restating it (`.claude/rules/ui-palette.md`'s rule), and the Manage tab
##   reads and APPLIES its tint from `ActionPalette`'s `&"manage"` surface key
##   (#669) instead of restating it either — two routes, two assertions, both
##   catching a literal creeping back into `attack_mode_bar.tscn`.
##
## State assertions go through `TempUpgradeButton.state`, never through a colour
## value: which exact blue "armed" is remains a tuning decision, and pinning it
## here would turn every retune into a red suite.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _MELEE_BODY := preload("res://ui/hud/command_tray/bodies/melee_body.tscn")
const _MODE_BAR := preload("res://ui/attack_mode_bar/attack_mode_bar.tscn")
const _PALETTE := preload("res://ui/theme/action_palette.tres")

var _graph: Graph
var _alloc: AllocationSystem
var _tm: TurnManager
var _bs: BattleSystem
var _pic: PlayerInputController
var _attacker: Entity
var _body: MeleeBody
var _row: HBoxContainer

## A path pivot — a — b — c, all owned by the attacker. `blade_size` is 3, so
## selecting members is how a test spends the shared budget the temp upgrades
## are also paid out of.
var _pivot: SkillNode
var _a: SkillNode
var _b: SkillNode
var _c: SkillNode


func _spawn(nm: String) -> SkillNode:
	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	sn.name = nm
	_graph.add_skill_node(sn)
	return sn


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_tm = autofree(TurnManager.new())
	add_child(_tm)

	# No MeleePreview / AttackVFX: nothing here launches, so none is needed.
	_bs = autofree(BattleSystem.new())
	_bs.turn_manager = _tm
	_bs.allocation_system = _alloc
	_bs.graph = _graph
	add_child(_bs)

	_attacker = Entity.new()
	_attacker.name = "Attacker"
	_attacker.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_attacker.stat_board.blade_size.base_value = 3.0
	_attacker.stat_board.action_points.base_value = 4.0
	_attacker.stat_board.action_points.current = 4.0
	_graph.entities_container.add_child(_attacker)
	_tm.current_entity = _attacker

	_pic = autofree(PlayerInputController.new())
	_pic.graph = _graph
	_pic.allocation_system = _alloc
	_pic.battle_system = _bs
	_pic.turn_manager = _tm
	_pic.player = _attacker
	add_child(_pic)

	_pivot = _spawn("Pivot")
	_a = _spawn("A")
	_b = _spawn("B")
	_c = _spawn("C")
	_graph.add_edge(_pivot, _a)
	_graph.add_edge(_a, _b)
	_graph.add_edge(_b, _c)
	await get_tree().process_frame
	for n in [_pivot, _a, _b, _c]:
		_alloc.force_allocate(_attacker, n)

	_body = _MELEE_BODY.instantiate() as MeleeBody
	add_child_autofree(_body)
	_body.bind(_attacker, _bs, _pic)
	_row = _body.find_child("UpgradeRow", true, false) as HBoxContainer
	assert_not_null(_row, "melee_body.tscn must still carry an %UpgradeRow")


## Arm melee and pick the pivot, then grow the blade through `members` — the
## real click path, so the budget arithmetic under test is the live one.
func _arm_plan(members: Array[SkillNode] = []) -> MeleeAttackPlan:
	# Reset first: re-requesting a mode already selected keeps the live plan, so
	# without this a second call would grow the FIRST plan rather than start over.
	_bs.reset_plan()
	_bs.request_attack_mode(BattleSystem.AttackMode.MELEE)
	var plan := _bs.attack_plan as MeleeAttackPlan
	plan._on_node_left_clicked(_pivot)
	for m in members:
		plan._on_node_left_clicked(m)
	return plan


func _card(index: int) -> TempUpgradeButton:
	return _row.get_child(index) as TempUpgradeButton


## The addon's own authored icon, read the same way production reads it.
func _authored_icon(index: int) -> Texture2D:
	var entry: Dictionary = MeleeAttackPlan.TEMP_UPGRADE_CATALOG[index]
	var tmp := (entry.scene as PackedScene).instantiate() as SkillNodeAddon
	var tex := tmp.icon
	tmp.free()
	return tex


func test_one_scene_instance_per_catalog_entry() -> void:
	var n := MeleeAttackPlan.TEMP_UPGRADE_CATALOG.size()
	assert_eq(_row.get_child_count(), n,
		"one card per TEMP_UPGRADE_CATALOG entry — a new catalog kind should need no code here")
	for i in n:
		assert_true(_row.get_child(i) is TempUpgradeButton,
			"card %d must be a TempUpgradeButton scene instance, not a bare Button.new() (#465)" % i)


func test_card_glyph_and_accent_come_from_authored_data() -> void:
	for i in MeleeAttackPlan.TEMP_UPGRADE_CATALOG.size():
		var entry: Dictionary = MeleeAttackPlan.TEMP_UPGRADE_CATALOG[i]
		var card := _card(i)
		assert_not_null(card.icon_texture, "catalog entry %s has no authored addon icon" % entry.id)
		assert_eq(card.icon_texture, _authored_icon(i),
			"card %s must show the addon scene's own icon, not a parallel lookup" % entry.id)
		assert_eq(card.accent, _PALETTE.color_for(entry.id),
			"card %s must read its colour through ActionPalette.color_for()" % entry.id)


func test_three_states_are_each_reachable_and_distinct() -> void:
	var seen: Array = []

	# No plan at all → nothing is placeable.
	_body._refresh()
	seen.append(_card(0).state)

	# Pivot only, full budget → both cards at rest.
	_arm_plan()
	seen.append(_card(0).state)

	# Arm one → it is what the next graph click places.
	_pic.arm_temp_upgrade(MeleeAttackPlan.TEMP_UPGRADE_CATALOG[0])
	seen.append(_card(0).state)

	assert_eq(seen, [
		TempUpgradeButton.State.UNAFFORDABLE,
		TempUpgradeButton.State.AVAILABLE,
		TempUpgradeButton.State.ARMED,
	], "all three states must be reachable, and they must be three different answers")
	# Redundant-looking, but it is the actual contract: three DISTINCT values.
	assert_eq(_uniq(seen).size(), 3, "the three states must not collapse into one another")


func _uniq(values: Array) -> Array:
	var out: Array = []
	for v in values:
		if not out.has(v):
			out.append(v)
	return out


func test_arming_swaps_exactly_one_card() -> void:
	_arm_plan()
	var clamp_entry: Dictionary = MeleeAttackPlan.upgrade_by_id(&"clamp")
	var spike_entry: Dictionary = MeleeAttackPlan.upgrade_by_id(&"spike_ring")

	_pic.arm_temp_upgrade(clamp_entry)
	assert_eq(_card(0).state, TempUpgradeButton.State.ARMED, "clamp armed")
	assert_eq(_card(1).state, TempUpgradeButton.State.AVAILABLE, "spike must not also read as armed")

	_pic.arm_temp_upgrade(spike_entry)
	assert_eq(_card(0).state, TempUpgradeButton.State.AVAILABLE, "clamp must have dropped its arm")
	assert_eq(_card(1).state, TempUpgradeButton.State.ARMED, "spike armed")


func test_spending_the_blade_budget_flips_affordability_only() -> void:
	# blade_size 3, spike costs 2, clamp costs 1.
	_arm_plan()
	assert_true(_card(1).affordable, "spike is affordable with the full 3-node budget")

	# Two members eat 2 of 3 → spike (cost 2) no longer fits, clamp (cost 1) still does.
	# Grown on the SAME plan, so this is genuinely "the budget was spent" rather
	# than "a fresh plan happened to start smaller".
	var plan := _bs.attack_plan as MeleeAttackPlan
	plan._on_node_left_clicked(_a)
	plan._on_node_left_clicked(_b)
	assert_eq(_card(1).state, TempUpgradeButton.State.UNAFFORDABLE,
		"spending the shared budget must read as UNAFFORDABLE, not as Godot's disabled grey")
	assert_false(_card(1).armed, "affordability must not silently clear the arm flag")
	assert_eq(_card(0).state, TempUpgradeButton.State.AVAILABLE,
		"clamp still fits in the remaining budget and must stay at rest")

	# The last member exhausts it entirely.
	plan._on_node_left_clicked(_c)
	assert_eq(_card(0).state, TempUpgradeButton.State.UNAFFORDABLE, "no budget left for clamp either")


## Decision 6's regression guard. `attack_mode_bar.tscn` used to carry three
## inline `Color(...)` literals duplicating StatDef.tint_color; per
## `.claude/rules/ui-palette.md` those are the stat system's to own.
func test_mode_tabs_read_their_tint_from_the_stat_registry() -> void:
	var bar := _MODE_BAR.instantiate()
	add_child_autofree(bar)
	var expected := {
		"MeleeToggleButton": &"strength",
		"RangedToggleButton": &"dexterity",
		"MagicToggleButton": &"intelligence",
	}
	for node_name in expected:
		var btn := bar.find_child(node_name, true, false) as AttackModeButton
		assert_not_null(btn, "%s missing from attack_mode_bar.tscn" % node_name)
		var def := StatRegistry.get_def(expected[node_name])
		assert_not_null(def, "no StatDef for %s" % expected[node_name])
		assert_eq(btn.tint, def.tint_color,
			"%s must read its tint from StatDef.tint_color, not a .tscn literal" % node_name)


## #669 — the Manage tab has no attribute to resolve its own tint from
## (`_resolve_tint` no-ops for it), so `attack_mode_bar.gd` pushes the shared
## `ActionPalette`'s `&"manage"` surface key in AFTER the button's own
## `_ready` already ran. A var-only assertion can't catch a regression here:
## the setter must actually repaint the shader param, not just record the
## Color (see `AttackModeButton._apply_tint`).
func test_manage_tab_reads_and_applies_its_tint_from_the_action_palette() -> void:
	var bar := _MODE_BAR.instantiate()
	add_child_autofree(bar)
	var btn := bar.find_child("ManageToggleButton", true, false) as AttackModeButton
	assert_not_null(btn, "ManageToggleButton missing from attack_mode_bar.tscn")
	var expected: Color = _PALETTE.color_for(&"manage")
	assert_eq(btn.tint, expected,
		"Manage tab must read its tint from ActionPalette, not a .tscn literal")
	assert_eq(btn.label.material.get_shader_parameter("tint"), expected,
		"Manage tab's tint must be APPLIED to its shader, not just recorded on the var")


## #669 D4 — `color_for`'s unmapped-key fall-through is `Color.TRANSPARENT`,
## so "the key is wired" and "the key exists" are different facts and both
## need pinning.
func test_action_palette_manage_key_is_wired_and_matches_the_authored_resource() -> void:
	assert_ne(_PALETTE.color_for(&"manage"), Color.TRANSPARENT,
		"manage key must be wired in ActionPalette.color_for, not falling through")
	assert_eq(_PALETTE.color_for(&"manage"), _PALETTE.manage,
		"color_for(&manage) must return the .tres-authored value")


func test_every_mode_tab_carries_a_glyph() -> void:
	var bar := _MODE_BAR.instantiate()
	add_child_autofree(bar)
	for child in bar.get_children():
		var btn := child as AttackModeButton
		assert_not_null(btn, "every tab should be an AttackModeButton")
		assert_not_null(btn.mode_icon,
			"%s has no mode_icon — the inline glyph AND the shader watermark both go dark" % btn.name)
