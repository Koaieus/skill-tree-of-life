extends GameRoot

## Procgen sandbox with a live player + AI starters. Inherits the
## [code]game_root.tscn[/code] skeleton; populates entities via
## [method GameRoot._setup_level] so generation runs *after* the systems
## are in the tree but *before* UIRoot composes (it reads player stats).
##
## Random-walk territory expansion below skips [AllocationSystem.allocate]
## because that's gated on SP/AP — fine in-game, hostile to one-shot setup.
## Uses [method AllocationSystem.force_allocate], the same primitive
## [method GameRoot.spawn_entity] composes for the initial core.

const _STARTER_GROUP := &"procgen_starter"
const _DEFAULT_CORE_CLASS := preload("res://entity/core/balanced_core.tres")

@export var preset: GraphProcgenConfig
@export var player_color: Color = Color(0.4, 0.8, 1.0)
@export var enemy_colors: Array[Color] = [Color(0.95, 0.4, 0.4), Color(1.0, 0.6, 0.2)]
## Class wired onto every spawned entity. The .tres is shared safely — apply()
## duplicates each modifier before installing it on the entity's stat board.
@export var core_class: CoreClass = _DEFAULT_CORE_CLASS

## Overrides applied to a duplicate of `preset` — leaves the on-disk preset
## untouched so the same resource can serve multiple sandboxes at different
## sizes. 0 = inherit from preset.
@export var node_count_override: int = 50
@export var n_random_starters: int = 1
@export var viability_radius: float = 400.0

## Random-walk expansion steps per entity, after core allocation.
@export var expansion_steps: int = 6


func _setup_level() -> void:
	if preset == null:
		push_warning("ProcgenPlaySandbox: assign `preset` in inspector")
		return
	var cfg: GraphProcgenConfig = preset.duplicate(true)
	if node_count_override > 0:
		cfg.node_count = node_count_override
	cfg.n_random_starters = n_random_starters
	cfg.viability_radius = viability_radius

	var result := GraphProcgen.generate(cfg, graph)
	var starting_nodes: Array = result.get("starting_nodes", [])
	if starting_nodes.is_empty():
		push_warning("ProcgenPlaySandbox: procgen returned no starting nodes")
		return
	for n in starting_nodes:
		(n as Node).add_to_group(_STARTER_GROUP)

	player = spawn_entity("Player", player_color, starting_nodes[0], core_class)

	var enemies: Array[Entity] = []
	for i in range(1, starting_nodes.size()):
		var color: Color = enemy_colors[(i - 1) % enemy_colors.size()] if not enemy_colors.is_empty() else Color.RED
		enemies.append(spawn_entity("Enemy_%d" % i, color, starting_nodes[i], core_class))

	# Wire systems that needed live entities (edit-time NodePaths can't bind
	# to nodes that don't exist yet).
	input_ctl.player = player
	var vs := %VisionSystem as VisionSystem
	vs.viewers = [player]

	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_expand(player, rng, expansion_steps)
	for e in enemies:
		_expand(e, rng, expansion_steps)


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
