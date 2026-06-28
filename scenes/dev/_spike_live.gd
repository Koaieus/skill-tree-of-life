@tool
extends GameRoot

## TEMP spike (#77) — verifies a *neutered* GameRoot runs a self-driven
## allocation scenario LIVE in the editor (@tool, no play step). Settles the
## three unknowns the design doc treated as a wall:
##   1. SceneTreeTimer ticks in the editor SceneTree (the await beat loop runs).
##   2. @tool autoloads resolve in-editor (Events + StatRegistry).
##   3. The @tool'd systems run + mutate state with no stray _process.
## DELETE after verification — not part of the shipped sandbox.

const _SKILL_NODE := preload("res://skill_node/skill_node.tscn")

var _nodes: Array[SkillNode] = []
var _demo: Entity
var _iter := 0


func _setup_level() -> void:
	auto_start_turn = false
	show_ui = false
	enable_fog = false

	for j in 3:
		var n: SkillNode = _SKILL_NODE.instantiate()
		n.position = Vector2(j * 120.0, 0.0)
		var mods: Array[StatModifier] = []
		var m := StatModifier.new()
		m.stat_id = &"strength"
		m.operation = StatModifier.Operation.ADD_BASE
		m.value = 5.0
		mods.append(m)
		n.modifiers = mods
		graph.add_skill_node(n)
		_nodes.append(n)
	for j in range(_nodes.size() - 1):
		graph.add_edge(_nodes[j], _nodes[j + 1])

	# Leave `player` null — a self-driven showcase has no human player, so the
	# interaction layer (highlight / input / vision) stays dormant in-editor.
	_demo = spawn_entity("SpikeDemo", Color.CYAN, _nodes[0])
	_run_loop()


func _run_loop() -> void:
	print("[SPIKE] loop started; editor_hint=%s" % str(Engine.is_editor_hint()))
	while is_inside_tree():
		await get_tree().create_timer(0.3).timeout
		_iter += 1
		var owned := _nodes[1].owned_by == _demo
		if owned:
			allocation_system.force_deallocate(_nodes[2])
			allocation_system.force_deallocate(_nodes[1])
		else:
			allocation_system.force_allocate(_demo, _nodes[1])
			allocation_system.force_allocate(_demo, _nodes[2])
		var str_val: Variant = _demo.stat_board.get_value(&"strength")
		print("[SPIKE] iter=%d now_owned=%s STR=%s" % [_iter, str(not owned), str(str_val)])
		if _iter >= 6:
			print("[SPIKE] DONE — systems ran in-editor, timer ticked, STR moved.")
			return
