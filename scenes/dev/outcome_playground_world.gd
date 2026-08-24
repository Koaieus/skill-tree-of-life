extends RefCounted

## The world the Outcome playground replays into (#539) — built in CODE, on
## purpose, and shared verbatim by the tab and by the headless fixture test.
##
## [b]Why not a `.tscn`.[/b] A recorded [LaunchAttackCommand] names nodes by
## `stable_id` and its attacker by `entity_id`, and both mint from per-[Graph]
## counters walking container CHILD ORDER ([method Graph._ensure_topology] /
## `_mint_entity_id`). So a fixture only replays if the world it lands on is
## reproduced *identically* — same nodes, same order, same allocation. One
## builder called from both places makes that true by construction; a scene
## plus two copies of "now arm it" is exactly where that drifts. This is the
## same call `scenes/dev/sandbox_world.gd` documents for the systems half, and
## like it this script carries **no `class_name`** — consumers preload it, and
## the global class cache stays out of it.
##
## [b]The shape, and why each piece is there.[/b]
##
## [codeblock]
##   a_core ── a_leaf ── d_gate ── d_core
##                          │
##                       d_limb1
##                          │
##                       d_limb2
## [/codeblock]
##
##   * Two factions, authored on both sides. Two entities that never set one
##     are ALLIES (`.claude/rules/melee-fixtures.md`), and an allied node is
##     dropped before a plan ever queries it.
##   * `d_gate` is a CUT VERTEX of the defender's territory: killing it islands
##     `d_limb1` + `d_limb2` while `d_core` survives. That is the point — the
##     forced-dealloc cascade then BFSs into THREE layers, which is what
##     acceptance 3 pins (the shatter stagger must survive the replay path),
##     and it is the "3 nodes turn to dead instantly" report #534 names.
##   * `a_leaf` carries LOCAL `spell_damage` + `range`, because
##     [method SpellResolver] reads `spell_damage` off the cast-from node
##     first. Overkill is deliberate: a cast that only chips HP leaves
##     ownership untouched and the fingerprint assertion passes vacuously.
##
## Crit is deliberately left ON. The record is captured post-roll and a replay
## re-rolls nothing (`crit_multiplier` comes back 1.0), so the fixture is
## reproducible with crit live — and zeroing it would hide the very asymmetry
## the replay path exists to prove.

const _SKILL_NODE_SCENE: PackedScene = preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE: PackedScene = preload("res://graph/graph.tscn")
const _BOARD: Resource = preload("res://entity/default_entity_board.tres")
const _PLAYER_FACTION: Resource = preload("res://entity/factions/player.tres")
const _NPC_FACTION: Resource = preload("res://entity/factions/npc.tres")

## Node name -> authored position. **Order is a contract**: `stable_id` mints
## in child order, and the record names nodes by that id.
const LAYOUT: Array[Array] = [
	["a_core", Vector2(0, 0)],
	["a_leaf", Vector2(170, 0)],
	["d_gate", Vector2(340, 0)],
	["d_core", Vector2(510, 0)],
	["d_limb1", Vector2(340, 150)],
	["d_limb2", Vector2(340, 300)],
]

## Undirected pairs, in the order they are added (edge order is not folded into
## a `stable_id`, but it is folded into the fingerprint's topology tier).
const EDGES: Array[Array] = [
	["a_core", "a_leaf"],
	["a_leaf", "d_gate"],
	["d_gate", "d_core"],
	["d_gate", "d_limb1"],
	["d_limb1", "d_limb2"],
]

const ATTACKER_OWNS: Array[String] = ["a_core", "a_leaf"]
const DEFENDER_OWNS: Array[String] = ["d_gate", "d_core", "d_limb1", "d_limb2"]

## Big enough that the seed landing kills `d_gate` outright, so the cascade the
## fixture is about actually runs. Read node-locally off the cast-from node.
const CAST_SPELL_DAMAGE: float = 9999.0
## Hop reach from `a_leaf`; the spell's own targeting is 3 hops, this is the
## board stat the range finder measures against.
const CAST_RANGE: float = 600.0
## Re-established on every [method arm], so a replay always starts from the
## same board rather than from whatever the last one left behind.
const SKILL_POINTS: float = 60.0
const ACTION_POINTS: float = 6.0
const MANA: float = 10.0

var graph: Graph
var attacker: Entity
var defender: Entity
## Node name -> the live [SkillNode]. Handy for a caller that wants to arm a
## plan without re-deriving the layout.
var nodes: Dictionary[String, SkillNode] = {}


## Instantiate `graph.tscn`, fill it, and hand it back. The caller parents it
## (a [SubViewport] in the tab, the test root headlessly) — this only builds.
##
## [param parent] must already be in the tree: [Entity.initialize] walks up for
## a [Graph] ancestor, and `entity_id` mints on entry to `entities_container`.
func build(parent: Node) -> Graph:
	graph = _GRAPH_SCENE.instantiate() as Graph
	graph.name = "Graph"
	parent.add_child(graph)
	for entry in LAYOUT:
		var node := _SKILL_NODE_SCENE.instantiate() as SkillNode
		node.name = str(entry[0])
		graph.add_skill_node(node)
		node.position = entry[1] as Vector2
		nodes[str(entry[0])] = node
	for pair in EDGES:
		graph.add_edge(nodes[str(pair[0])], nodes[str(pair[1])])
	attacker = _spawn("Attacker", _PLAYER_FACTION)
	defender = _spawn("Defender", _NPC_FACTION)
	_set_local(nodes["a_leaf"], &"spell_damage", CAST_SPELL_DAMAGE)
	_set_local(nodes["a_leaf"], &"range", CAST_RANGE)
	# Force the topology rebuild now, so every `stable_id` is minted before
	# anything captures or replays. They mint LAZILY (`.claude/rules/graph.md`)
	# and a capture that triggered the mint at a different moment than a replay
	# would hand the two worlds different ids for the same node.
	graph.get_stable_id(nodes["a_core"])
	return graph


## Reset to the canonical starting state: strip every claim, refill every node,
## restore both boards, re-apply the authored ownership through the REAL
## primitive, and seat both cores.
##
## Idempotent and total — it is the tab's Reset button, and it is what runs
## before every replay. A replay onto a world that still carries the last run's
## damage cannot match the recorded fingerprint.
##
## Mute [AllocationVFX] around this ([member AllocationVFX.muted]): the strips
## below are genuine `force_deallocate` calls and would otherwise shatter the
## whole board on every reset.
##
## [param turn_manager] is seated here rather than by each caller, because
## "whose turn is it" is part of the canonical pre-state: [method
## BattleSystem.build_launch_command] refuses outright with no `current_entity`,
## and a tab that seated it while a test did not would be two pre-states. Never
## TICKED — writing the plain var IS the whole of "it is the attacker's turn"
## (the standing sandbox rule).
func arm(alloc: AllocationSystem, turn_manager: TurnManager = null) -> void:
	for node in nodes.values():
		if node.owned_by != null:
			alloc.force_deallocate(node)
		node.refill(true)
	for entity in [attacker, defender]:
		entity.is_dead = false
		entity.core_location = null
		_reset_board(entity)
	for name_ in ATTACKER_OWNS:
		alloc.force_allocate(attacker, nodes[name_])
	for name_ in DEFENDER_OWNS:
		alloc.force_allocate(defender, nodes[name_])
	attacker.core_location = nodes["a_core"]
	defender.core_location = nodes["d_core"]
	if turn_manager != null:
		turn_manager.current_entity = attacker


## Arm a live Spark cast: `a_leaf` casts, `d_gate` is the seed. The same two
## left-clicks the click grammar routes in game — [MagicAttackPlan] takes the
## cast-from node first, then the target.
func arm_magic(battle: BattleSystem, spell: SpellDef = SpellCatalog.SPARK) -> void:
	battle.selected_spell = spell
	battle.request_attack_mode(BattleSystem.AttackMode.MAGIC)
	var plan := battle.attack_plan as MagicAttackPlan
	if plan == null:
		return
	plan._on_node_left_clicked(nodes["a_leaf"])
	plan._on_node_left_clicked(nodes["d_gate"])


func _spawn(display_name: String, faction: Resource) -> Entity:
	var entity := Entity.new()
	entity.name = display_name
	entity.display_name = display_name
	entity.faction = faction
	entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	# entities_container, never the Graph itself — `entity_id` mints on entry
	# to that container (#509), and a command naming an unminted id resolves to
	# nothing at all.
	graph.entities_container.add_child(entity)
	# Idempotent, and the editor never runs `_ready` — so calling it here is
	# what makes the tab's entity and the test's entity the same object.
	entity.initialize()
	return entity


func _reset_board(entity: Entity) -> void:
	var board: EntityStatBoard = entity.stat_board
	if board == null:
		return
	if board.skill_points != null:
		board.skill_points.wounded = 0
		board.skill_points.staked = 0
		board.skill_points.base_value = SKILL_POINTS
		board.skill_points.set_current(SKILL_POINTS)
	if board.action_points != null:
		board.action_points.base_value = ACTION_POINTS
		board.action_points.current = ACTION_POINTS
	if board.mana != null:
		board.mana.base_value = MANA
		board.mana.current = MANA
	for pool in [board.health, board.deallocation_points]:
		if pool != null:
			pool.restore_to_full()


func _set_local(node: SkillNode, stat_id: StringName, value: float) -> void:
	var mod := StatModifier.new()
	mod.stat_id = stat_id
	mod.operation = StatModifier.Operation.SET
	mod.value = value
	node.add_local_modifier(mod)
