extends GameRoot

## Procgen sandbox with a live player + AI starters. Inherits the
## [code]game_root.tscn[/code] skeleton; populates entities via
## [method GameRoot._setup_level] so generation runs *after* the systems
## are in the tree but *before* HudRoot composes (it reads player stats).
##
## Random-walk territory expansion below skips [AllocationSystem.allocate]
## because that's gated on SP/AP — fine in-game, hostile to one-shot setup.
## Uses [method AllocationSystem.force_allocate], the same primitive
## [method GameRoot.spawn_entity] composes for the initial core.

const _STARTER_GROUP := &"procgen_starter"
const _DEFAULT_CORE_CLASS := preload("res://entity/core/balanced_core.tres")
const _DEFAULT_ENEMY_CORE_CLASS := preload("res://entity/core/basic_enemy_core.tres")
const _STARTING_SPELLS: Array[SpellDef] = [
	preload("res://attack/spell/defs/spark.tres"),
	preload("res://attack/spell/defs/lightning_bolt.tres"),
]


# Runtime-built spellbook for sandbox starts. Once a "player profile" lands
# this should come from there instead.
static func _make_starting_spellbook() -> SpellBook:
	var book := SpellBook.new()
	book.spells = _STARTING_SPELLS.duplicate()
	return book

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

## Random-walk expansion steps per entity, after core allocation.
@export var expansion_steps: int = 6

const SPECIMEN_POOL_SET = preload("res://procgen/pools/specimen_pool_set.tres")


func _setup_level() -> void:
	if preset == null:
		push_warning("ProcgenPlaySandbox: assign `preset` in inspector")
		return
	var cfg: GraphProcgenConfig = preset.duplicate(true)
	if node_count_override > 0:
		cfg.node_count = node_count_override
	cfg.n_random_starters = n_random_starters
	cfg.viability_radius = viability_radius
	cfg.modifier_pool_set = SPECIMEN_POOL_SET.duplicate(true)

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

	player = spawn_entity("Player", player_color, starting_nodes[0], core_class)
	#player.spellbook = _make_starting_spellbook()

	var enemies: Array[Entity] = []
	for i in range(1, starting_nodes.size()):
		var color: Color = enemy_colors[(i - 1) % enemy_colors.size()] if not enemy_colors.is_empty() else Color.RED
		enemies.append(spawn_entity("Enemy_%d" % i, color, starting_nodes[i], enemy_core_class, true))

	# Wire the player into the interaction layer (input / vision / highlight /
	# faction) now that it exists — edit-time NodePaths can't bind to a node
	# spawned at runtime. `_ready` calls `bind_player` again idempotently; doing
	# it here too sets vision before `_expand` + the fade so the initial fog is
	# correct.
	bind_player(player)

	# Derive expansion RNG from the config seed so identical `preset.seed`
	# produces identical content + starter walks. Salting with a constant
	# keeps the expansion stream independent of the procgen content stream
	# (so adding/removing modifier rolls upstream doesn't shift expansion).
	var rng := RandomNumberGenerator.new()
	rng.seed = (cfg.seed if cfg.seed != 0 else hash("procgen_play_sandbox")) ^ 0x57AB02D
	_expand(player, rng, expansion_steps)
	for e in enemies:
		_expand(e, rng, expansion_steps)

	SceneTransition.fade_in()


func _expand(ent: Entity, rng: RandomNumberGenerator, steps: int) -> void:
	for _i in steps:
		var owned: Array[SkillNode] = []
		for n in graph.get_skill_nodes():
			if n.owned_by == ent:
				owned.append(n)
		if owned.is_empty():
			return
		var pick: SkillNode = owned[rng.randi() % owned.size()]
		var candidates: Array[SkillNode] = []
		for nb in graph.get_neighbours(pick):
			if nb.owned_by == null:
				candidates.append(nb)
		if candidates.is_empty():
			continue
		var target: SkillNode = candidates[rng.randi() % candidates.size()]
		allocation_system.force_allocate(ent, target)
