extends GameRoot
## The integration tier's shared level fixture (#979): a purpose-built,
## hand-authored level nobody tunes. Inherits `scenes/game_root.tscn` the way
## `dev_sandbox.tscn` does — NOT `level.tscn` + `RunBootstrap`, which generates
## its graph from a run and is the procgen door this fixture exists to avoid.
##
## Determinism by authorship: the eight-node graph sits in the `.tscn`, the two
## entities are spawned here from the same `spawn_entity` seam
## `scenes/procgen_play_sandbox.gd` uses, `crit_chance` is zeroed on both
## boards, the enemy's AI pacing delay is zeroed, and the battle system runs on
## the instant logical clock. No `GameSession` is consulted.
##
## Geometry (a fact of this fixture, not of any `.tres`): `PlayerCore` —
## `Step1` — `Step2` in a line 200 apart; `EnemyCore` sits 200 from `Step1` at
## +40° of the `Step1`→`Step2` ray, so after allocating `Step1` and `Step2` a
## blade pivoted on `Step1` with `Step2` as its one member meets the enemy core
## on the default (CCW) sweep — the same layout
## `test/unit/attack/test_ai_swing_direction.gd` proves a swing reaches.

const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _ENEMY_FACTION := preload("res://entity/factions/camp_1.tres")
const _CORE_CLASS := preload("res://entity/core/balanced_core.tres")
## Flat blade damage granted to the player so ONE swing kills the enemy core
## and one kill levels. A fixture fact: sized against the default node board's
## core health with headroom, never read back by a test as a number. The same
## `grant_core_modifier` seam `scenes/dev_sandbox.gd` uses for its blade size.
const _FIXTURE_BLADE_DAMAGE_BONUS := 80.0

## The one AI-driven opponent; typed so a test never walks
## `entities_container` by name.
var enemy: Entity

## The two allocation steps and the enemy core, exposed so a test speaks in
## the fixture's vocabulary rather than in scene paths.
@onready var player_core: SkillNode = %PlayerCore
@onready var step1: SkillNode = %Step1
@onready var step2: SkillNode = %Step2
@onready var enemy_core: SkillNode = %EnemyCore
## The enemy's two outer nodes, force-allocated at setup so a core kill has a
## territory to cascade over (every node it owned goes unowned), not just the
## core. Both sit beyond the blade's reach from `Step1`, so the swing itself
## lands on the core alone.
@onready var enemy_out: SkillNode = %EnemyOut
@onready var enemy_out2: SkillNode = %EnemyOut2


func _setup_level() -> void:
	await super()
	# Spawn order is opening order (`_opening_entity`): the player spawns
	# first so it holds the first turn.
	player = spawn_entity("Player", Color(0.945, 0.271, 0.247), player_core, _CORE_CLASS)
	player.faction = _PLAYER_FACTION
	player.is_human_controlled = true
	# `with_ai = true` mounts the AIController here, so its pacing delay can be
	# zeroed in this same hook; `_ensure_controllers` then skips the enemy.
	enemy = spawn_entity("Enemy", Color(0.318, 0.776, 0.447), enemy_core, _CORE_CLASS, true)
	enemy.faction = _ENEMY_FACTION
	enemy.is_human_controlled = false
	allocation_system.force_allocate(enemy, enemy_out)
	allocation_system.force_allocate(enemy, enemy_out2)
	# `turn_delay` is host-local presentation pacing between an AI's actions —
	# irrelevant on a logical clock, and seconds of wall time per enemy turn
	# if left at its default.
	(enemy.get_node("AIController") as AIController).turn_delay = 0.0
	for ent: Entity in [player, enemy]:
		ent.stat_board.crit_chance.base_value = 0.0
	var m := StatModifier.new()
	m.stat_id = &"blade_damage"
	m.operation = StatModifier.Operation.ADD_BASE
	m.value = _FIXTURE_BLADE_DAMAGE_BONUS
	player.grant_core_modifier(m)
	battle_system.instant_mutation = true

