extends GutTest

## Every addon a shipped sandbox's graph adopts was instantiated from a scene,
## so its kind ([method SkillNodeAddon.get_kind]) is non-empty. An addon
## authored as a bare script node inside a level, or built in code by procgen
## or loot, would read as no kind and break uniqueness and the tray outline.

const _SANDBOXES: Array[String] = [
	"res://scenes/dev_sandbox.tscn",
	"res://scenes/procgen_play_sandbox.tscn",
	"res://scenes/first_level_sandbox.tscn",
]


func test_every_adopted_addon_has_a_kind() -> void:
	for path in _SANDBOXES:
		var root := (load(path) as PackedScene).instantiate() as GameRoot
		add_child_autofree(root)
		await wait_until(func() -> bool: return root.turn_manager.current_entity != null, 10.0,
				"fixture: %s should open a turn" % path)
		var adopted := 0
		var kindless: Array[String] = []
		for n in root.graph.get_skill_nodes():
			for a in n.get_addons():
				adopted += 1
				if a.scene_file_path.is_empty():
					kindless.append("%s on %s" % [a.name, n.name])
		gut.p("%s: %d adopted addons" % [path, adopted])
		assert_eq(kindless, [] as Array[String],
				"%s adopts addons with no scene:\n%s" % [path, "\n".join(kindless)])
		root.free()
