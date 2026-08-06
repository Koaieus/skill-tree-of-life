extends GutTest

## Loot live panel (#260) — the played showcase's heir. Asserts the embedded
## world builds armed (attacker + victim with real core class + territory) and
## that the explicit beats drive the real reward chain: ▶ Kill victim awards XP
## to the killer and drops a SkillDust relic on the victim's core — or, per the
## phase kill-switches, exactly one of the two.

const _PANEL := preload("res://addons/loot_sandbox/loot_sandbox_panel.tscn")

var _panel


func before_each() -> void:
	_panel = _PANEL.instantiate()
	add_child(_panel)
	await get_tree().process_frame


func after_each() -> void:
	_panel.queue_free()


func _attacker() -> Entity:
	return _panel.graph.get_node("Entities/Attacker") as Entity


func _victim() -> Entity:
	return _panel.graph.get_node("Entities/Victim") as Entity


func _victim_core() -> SkillNode:
	# Insertion order: attacker core, victim core, victim nodes.
	return _panel.graph.get_skill_nodes()[1] as SkillNode


func _has_dust(node: SkillNode) -> bool:
	for a in node.get_addons():
		if a is SkillDustAddon:
			return true
	return false


func test_world_builds_armed() -> void:
	assert_eq(_panel.graph.get_skill_nodes().size(), 4, "1 attacker + 3 victim nodes")
	assert_eq(_panel.graph.get_node("Entities").get_child_count(), 2)

	var victim := _victim()
	assert_not_null(victim.core_class, "victim must carry a core class (dust draw)")
	assert_eq(_victim_core().owned_by, victim, "victim owns its territory at rest")
	assert_eq(_attacker().stat_board.xp.current, 0.0)


func test_kill_awards_xp_and_drops_dust() -> void:
	_panel.select_phase(0)   # full rewards
	var victim := _victim()

	_panel.kill_victim()
	await get_tree().process_frame

	assert_true(victim.is_dead, "kill must kill the victim")
	assert_gt(float(_attacker().stat_board.xp.current), 0.0,
		"killer must earn XP for the kill")
	assert_true(_has_dust(_victim_core()), "full-rewards kill must drop a relic")


func test_xp_only_phase_drops_no_dust() -> void:
	_panel.select_phase(1)   # drop_skill_dust_on_death = false

	_panel.kill_victim()
	await get_tree().process_frame

	assert_gt(float(_attacker().stat_board.xp.current), 0.0, "XP still awarded")
	assert_false(_has_dust(_victim_core()), "relic must be switched off")


func test_relic_only_phase_awards_no_xp() -> void:
	_panel.select_phase(2)   # award_xp_on_kill = false

	_panel.kill_victim()
	await get_tree().process_frame

	assert_eq(_attacker().stat_board.xp.current, 0.0, "XP must be switched off")
	assert_true(_has_dust(_victim_core()), "relic still drops")


func test_reset_rearms_a_clean_world() -> void:
	_panel.select_phase(0)
	_panel.kill_victim()
	await get_tree().process_frame
	assert_true(_victim().is_dead)

	await _panel.reset_world()

	assert_false(_victim().is_dead, "reset must resurrect the victim")
	assert_eq(_attacker().stat_board.xp.current, 0.0, "reset must clear XP")
	assert_false(_has_dust(_victim_core()), "reset must clear the relic")
	assert_eq(_victim_core().owned_by, _victim(), "victim re-owns its territory")
