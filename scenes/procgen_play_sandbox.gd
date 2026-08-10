extends GameRoot

## Procgen sandbox with a live player + AI starters. Inherits the
## [code]game_root.tscn[/code] skeleton; populates entities via
## [method GameRoot._setup_level] so generation runs *after* the systems
## are in the tree but *before* HudRoot composes (it reads player stats).
##
## Enemy territory is grown by [member territory_seeder] (#275, D-19/D-24) —
## a shared, injectable [TerritorySeeder] / [AllocationPolicy] pair, not a
## private random walk. It skips [AllocationSystem.allocate] because that's
## gated on SP/AP -- fine in-game, hostile to one-shot setup -- and uses
## [method AllocationSystem.force_allocate], the same primitive
## [method GameRoot.spawn_entity] composes for the initial core.
##
## The player is seeded with the core node ONLY (D-16's pinned "starting
## nodes: 1") -- it is never handed to [member territory_seeder].

const _STARTER_GROUP := &"procgen_starter"
const _DEFAULT_CORE_CLASS := preload("res://entity/core/balanced_core.tres")
const _DEFAULT_ENEMY_CORE_CLASS := preload("res://entity/core/basic_enemy_core.tres")
const _DEFAULT_TERRITORY_SEEDER := preload("res://procgen/placement/territory_seeder.tres")

@export var preset: GraphProcgenConfig
@export var player_color: Color = Color(0.4, 0.8, 1.0)
@export var enemy_colors: Array[Color] = [Color(0.95, 0.4, 0.4), Color(1.0, 0.6, 0.2)]
## Class wired onto every spawned entity. The .tres is shared safely — apply()
## duplicates each modifier before installing it on the entity's stat board.
@export var core_class: CoreClass = _DEFAULT_CORE_CLASS
@export var enemy_core_class: CoreClass = _DEFAULT_ENEMY_CORE_CLASS

## Overrides applied to a duplicate of `preset` — leaves the on-disk preset
## untouched so the same resource can serve multiple sandboxes at different
## sizes. 0 = inherit from preset.
@export var node_count_override: int = 50
@export var n_random_starters: int = 1
@export var viability_radius: float = 400.0

## Shared allocation-pick strategy (#275, D-24) — greedy BFS ball by default.
## Injectable so a different level scene can swap in another AllocationPolicy
## without touching this script.
@export var territory_seeder: TerritorySeeder = _DEFAULT_TERRITORY_SEEDER

## Target owned-node count for each spawned enemy (core included). D-19:
## enemy level == starting nodes, so this also becomes each enemy's spawn
## level once seeding completes. The player is NEVER expanded — D-16 pins
## player starting nodes at 1 (the core only).
@export var enemy_territory_size: int = 20


func _setup_level() -> void:
	if preset == null:
		push_warning("ProcgenPlaySandbox: assign `preset` in inspector")
		return
	var cfg: GraphProcgenConfig = preset.duplicate(true)
	if node_count_override > 0:
		cfg.node_count = node_count_override
	cfg.n_random_starters = n_random_starters
	cfg.viability_radius = viability_radius

	# Show the loading bar over a black fade so the procgen wall-clock has a
	# visible heartbeat. SceneTransition is the global fade/progress autoload.
	# `set_faded(true)` snaps to opaque-black (no fade animation needed here —
	# we're populating an empty level, no prior content to fade away from).
	SceneTransition.set_faded(true)
	SceneTransition.progress_bar.show()
	SceneTransition.set_progress(0.0)
	var progress_cb := func(frac: float, _label: String) -> void:
		SceneTransition.set_progress(frac * 100.0)
	var result: Dictionary = await GraphProcgen.generate(cfg, graph, progress_cb)
	var starting_nodes: Array = result.get("starting_nodes", [])
	if starting_nodes.is_empty():
		push_warning("ProcgenPlaySandbox: procgen returned no starting nodes")
		return
	for n in starting_nodes:
		(n as Node).add_to_group(_STARTER_GROUP)

	# Player: core only. D-16 pins starting nodes at 1 — no seeding call here.
	player = spawn_entity("Player", player_color, starting_nodes[0], core_class)

	var enemies: Array[Entity] = []
	for i in range(1, starting_nodes.size()):
		var color: Color = enemy_colors[(i - 1) % enemy_colors.size()] if not enemy_colors.is_empty() else Color.RED
		enemies.append(spawn_entity("Enemy_%d" % i, color, starting_nodes[i], enemy_core_class, true))

	# Wire the player into the interaction layer (input / vision / highlight /
	# faction) now that it exists — edit-time NodePaths can't bind to a node
	# spawned at runtime. `_ready` calls `bind_player` again idempotently; doing
	# it here too sets vision before territory seeding + the fade so the
	# initial fog is correct.
	bind_player(player)

	# Derive seeding RNG from the config seed so identical `preset.seed`
	# produces identical content + enemy territory. Salting with a constant
	# keeps the seeding stream independent of the procgen content stream
	# (so adding/removing modifier rolls upstream doesn't shift seeding).
	var rng := RandomNumberGenerator.new()
	rng.seed = (cfg.seed if cfg.seed != 0 else hash("procgen_play_sandbox")) ^ 0x57AB02D
	for e in enemies:
		var achieved := territory_seeder.seed_territory(e, graph, allocation_system, enemy_territory_size, rng)
		# D-19: enemy_level = starting_nodes. Uses the ACTUAL claimed count —
		# a graph that runs dry before `enemy_territory_size` still yields a
		# self-consistent level rather than an inflated one.
		e.level = achieved

	SceneTransition.fade_in()
