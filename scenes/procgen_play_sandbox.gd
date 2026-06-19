extends GameRoot

## Procgen sandbox with a live player + AI starters. Inherits the
## [code]game_root.tscn[/code] skeleton; populates entities via
## [method GameRoot._setup_level] so generation runs *after* the systems
## are in the tree but *before* UIRoot composes (it reads player stats).
##
## Random-walk territory expansion below skips [AllocationSystem.allocate]
## because that's gated on SP/AP — fine in-game, hostile to one-shot setup.
## Setting `node.owned_by` directly + mirroring + pushing modifiers is the
## same primitive AllocationSystem composes on top of.

const _DEFAULT_BOARD := preload("res://entity/default_entity_board.tres")

@export var preset: GraphProcgenConfig
@export var player_color: Color = Color(0.4, 0.8, 1.0)
@export var enemy_colors: Array[Color] = [Color(0.95, 0.4, 0.4), Color(1.0, 0.6, 0.2)]

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

	# Entities live under Graph so Entity._find_graph() resolves.
	var entities_root := Node.new()
	entities_root.name = "Entities"
	graph.add_child(entities_root)

	player = _spawn_entity(entities_root, "Player", player_color, starting_nodes[0])

	var enemies: Array[Entity] = []
	for i in range(1, starting_nodes.size()):
		var color: Color = enemy_colors[(i - 1) % enemy_colors.size()] if not enemy_colors.is_empty() else Color.RED
		enemies.append(_spawn_entity(entities_root, "Enemy_%d" % i, color, starting_nodes[i]))

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


func _spawn_entity(parent: Node, ent_name: String, color: Color, core: SkillNode) -> Entity:
	var ent := Entity.new()
	ent.name = ent_name
	ent.display_name = ent_name
	ent.color = color
	ent.stat_board = _DEFAULT_BOARD.duplicate(true) as StatBoard
	parent.add_child(ent)
	# add_child triggers Entity._ready synchronously (parent is already in
	# tree), so ent.navigator is live by the time we allocate the core.
	_force_allocate(ent, core)
	ent.core_location = core
	return ent


## Skips AllocationSystem gating (SP cost, adjacency) — direct primitive
## suitable for dev setup. AllocationSystem.allocate composes the same
## three side-effects plus the gates.
func _force_allocate(ent: Entity, node: SkillNode) -> void:
	node.owned_by = ent
	if ent.navigator != null:
		ent.navigator.mirror_add(node)
	if ent.stat_board != null:
		for m in node.modifiers:
			ent.stat_board.add_modifier(m)


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
		_force_allocate(ent, target)
