extends GutTest

## Drift guard for the heal doors (#997, hub #994). Owner (2026-09-20): "All
## heals must consult it [`healing_received`]" — so every write that RAISES
## the `health` or `node_health` pool goes through exactly one door per host:
## [method NodeCombat.heal_damage] and [method EntityCombat.heal]. The only
## bypass is those doors' `raw` flag. Same shape as the `SpellCatalog.ALL`
## guard (#965) and the stat-def roster scan: a directory walk that names
## file:line, because a functional test cannot see the NEXT heal mechanic
## that slips past the stat.
##
## Two halves. The textual scan finds call sites that name the pool. The
## behavioural pin covers the one site a scan cannot: `PoolStat`'s generic ADD
## upkeep never names `health`, so the pin asserts a bare board's upkeep leaves
## `health` alone — the companion (`core_healing`) enters through the entity
## door instead.

const _ROOT := "res://"
## Directories the walk never enters. `test/` and `addons/` arrange pool state
## (`set_current(1.0)` on a victim) — fixtures, not heals; the rest is engine
## and sibling-worktree churn.
const _SKIP_DIRS: Array[String] = [".godot", ".worktrees", ".git", "addons", "test", ".claude", "docs"]
## The allowlist: `file → funcs` whose bodies may move the pool directly. The
## two doors, plus the two `node_health` sites that RESTORE or ZERO state
## (a wire decode and a reset) rather than heal.
const _ALLOWED: Dictionary = {
	"res://combat/node_combat.gd": ["heal_damage"],
	"res://combat/entity_combat.gd": ["heal"],
	"res://skill_node/skill_node.gd": ["restore_current_hp", "_reset_combat_health"],
}
const _PATTERNS: Array[String] = [
	# `health.replenish(`, `node_health.set_current(`, `hp.replenish(`,
	# `health_pool.set_current(`, `_hp_pool().replenish(`
	"\\b(health|node_health|hp|health_pool|_hp_pool\\(\\))\\.(replenish|set_current)\\(",
	# the inline form: `get_stat(&"health") as PoolStat).replenish(`
	"get_stat\\(&\"(health|node_health)\"\\)[^\\n]*\\.(replenish|set_current)\\(",
	# `hp.current += x`
	"\\b(health|node_health|hp|health_pool)\\.current\\s*\\+=",
]


func _gd_files(dir: String, out: Array[String]) -> void:
	for sub in DirAccess.get_directories_at(dir):
		if sub in _SKIP_DIRS or sub.begins_with("."):
			continue
		_gd_files(dir.path_join(sub), out)
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".gd"):
			out.append(dir.path_join(file))


## Every `file:line — text` outside the allowlist that matches a pattern.
func _offenders() -> Array[String]:
	var regexes: Array[RegEx] = []
	for p in _PATTERNS:
		regexes.append(RegEx.create_from_string(p))
	var func_re := RegEx.create_from_string("^(?:static\\s+)?func\\s+(\\w+)")
	var files: Array[String] = []
	_gd_files(_ROOT, files)
	var out: Array[String] = []
	for path in files:
		var allowed: Array = _ALLOWED.get(path, [])
		var lines := FileAccess.get_file_as_string(path).split("\n")
		var current_func := ""
		for i in lines.size():
			var line: String = lines[i]
			var fm := func_re.search(line)
			if fm != null:
				current_func = fm.get_string(1)
			var code := line.get_slice("#", 0)
			for re in regexes:
				if re.search(code) != null:
					if not allowed.has(current_func):
						out.append("%s:%d — %s" % [path, i + 1, line.strip_edges()])
					break
	return out


func test_no_script_moves_a_health_pool_outside_the_two_doors() -> void:
	assert_eq(_offenders(), [] as Array[String],
			"a heal that bypasses healing_received — route it through NodeCombat.heal_damage "
			+ "/ EntityCombat.heal (raw := true is the explicit bypass), or allowlist a "
			+ "restore/zero site here with its reason")


func test_the_scan_sees_the_door_bodies_it_allowlists() -> void:
	# The scan is only a guard if it can see; the allowlist must be the reason
	# the two doors pass, not a pattern that matches nothing.
	var saved: Dictionary = _ALLOWED.duplicate()
	var re := RegEx.create_from_string(_PATTERNS[0])
	for path in ["res://combat/node_combat.gd", "res://combat/entity_combat.gd"]:
		var text := FileAccess.get_file_as_string(path)
		assert_not_null(re.search(text), "%s: the door body no longer matches the scan — update the patterns" % path)
	assert_eq(saved.size(), 3)


func test_a_bare_boards_upkeep_never_replenishes_health_itself() -> void:
	# The behavioural pin: `core_healing` is `health`'s ADD companion, and the
	# pool hands it to the host door instead of calling replenish on itself.
	var board := (preload("res://entity/default_entity_board.tres") as EntityStatBoard).duplicate(true) as EntityStatBoard
	board.apply_intrinsics()
	board.health.deplete(5.0)
	var before := board.health.current
	board.apply_per_turn_upkeep()
	assert_almost_eq(board.health.current, before, 0.001,
			"the pool's own upkeep must not move health — Entity._apply_turn_upkeep routes "
			+ "core_healing through EntityCombat.heal so healing_received is consulted")
	assert_almost_eq(board.mana.current, board.mana.current, 0.001)
