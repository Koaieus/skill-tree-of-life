class_name EntityFactory
extends Node

## Builds and places a level's runtime [Entity]s: heroes/NPCs
## ([method spawn_entity]), removable Dormant Cores ([method spawn_blocker]) and
## the blockers an arriving snapshot names ([method spawn_snapshot_entity],
## [member WorldSyncChannel.entity_spawner]'s production implementation). It never
## attaches a controller — that is the composition root's.

const _ENTITY_SCENE := preload("res://entity/entity.tscn")

## Removable blocker sizes (#300). Tier = size + 1 (SMALL → 1, MEDIUM → 2,
## LARGE → 3); see [method spawn_blocker]. Procgen blocker placements carry
## this enum's int value as the per-node `size` marker.
enum BlockerSize { SMALL, MEDIUM, LARGE }

const _BLOCKER_SCENE := preload("res://entity/blocker/blocker_entity.tscn")
const _STAKE_CEILING_LIFT := preload("res://skill_node/stake_ceiling_lift_modifier.tres")
const _BLOCKER_BOARDS: Dictionary = {
	BlockerSize.SMALL: preload("res://entity/blocker/blocker_small_board.tres"),
	BlockerSize.MEDIUM: preload("res://entity/blocker/blocker_medium_board.tres"),
	BlockerSize.LARGE: preload("res://entity/blocker/blocker_large_board.tres"),
}
const _BLOCKER_SPELLBOOKS: Dictionary = {
	BlockerSize.SMALL: preload("res://entity/blocker/blocker_spellbook_small.tres"),
	BlockerSize.MEDIUM: preload("res://entity/blocker/blocker_spellbook_medium.tres"),
	BlockerSize.LARGE: preload("res://entity/blocker/blocker_spellbook_large.tres"),
}

@export var graph: Graph
@export var allocation_system: AllocationSystem


## Spawn an [Entity] under `graph.entities_container` with a duplicated copy
## of the default stat board. If [param core_location] is given, force-allocates
## it as the entity's first node and sets `core_location`. If [param core_class]
## is given, assigns it as `core_class` so its modifier set + on_turn_started
## hook fire from Entity._ready. Returns the entity.
##
## Skips [method AllocationSystem.allocate] gating — this is dev/procgen
## setup, not a gameplay action. Mid-game spawning should still route through
## the gated path. Never attaches a controller — that is the composition
## root's, run after the level is populated.
func spawn_entity(
	ent_name: String,
	color: Color,
	core_location: SkillNode = null,
	core_class: CoreClass = null,
) -> Entity:
	var ent := _ENTITY_SCENE.instantiate() as Entity
	ent.name = ent_name
	ent.display_name = ent_name
	ent.color = color
	ent.core_class = core_class
	graph.entities_container.add_child(ent)
	if core_location != null:
		allocation_system.force_allocate(ent, core_location)
		ent.core_location = core_location
	return ent


## Spawn one Dormant Core of [param size] onto [param core_location]: a plain
## [Entity] (no controller) with the tier's board and spellbook from
## `entity/blocker/`, parented under `graph.entities_container` with its core
## force-allocated. The falloff aura comes from the scene's `core_class`, not
## from here. Returns the entity with `entity_tier` = size + 1.
## See docs/domain/dormant-core.md "spawn_blocker (EntityFactory)".
func spawn_blocker(size: BlockerSize, core_location: SkillNode,
		footprint: Array[SkillNode] = [], spell_prune_seed: int = 0,
		spell_prune_m: float = 0.0, preassigned_id: int = 0,
		stake_level: int = 1, stake_xp_offset_floor: float = 0.25,
		face: CoreClass = null, face_seed: int = 0) -> Entity:
	var ent := _BLOCKER_SCENE.instantiate() as Entity
	# A face overrides the scene's faceless class before `add_child`, so
	# `Entity.initialize` applies it exactly once; its per-placement seed rides
	# the entity's meta (the class is a shared resource).
	if face != null:
		ent.core_class = face
		ent.set_meta(BlockerCoreClass.FACE_SEED_META, face_seed)
		var faced := face as BlockerCoreClass
		if faced != null and faced.identity != null:
			ent.color = faced.identity.tint
	# Before `add_child`: `Graph._mint_entity_id` assigns only to an entity whose
	# id is still 0, so stamping first is adoption rather than a second mint.
	ent.entity_id = preassigned_id
	ent.name = "Blocker_%s" % BlockerSize.keys()[size].to_lower()
	# #587 — the player-facing name is "Dormant Core", never "Blocker": these
	# hold a patch of territory but never move or act, and `blocker` is the
	# mechanic, not the thing. The node NAME stays `Blocker_*`
	# so scene-tree lookups and the group are untouched; only `display_name`
	# reaches a tooltip.
	ent.display_name = "Dormant Core (%s)" % BlockerSize.keys()[size].capitalize()
	ent.entity_tier = int(size) + 1
	ent.stat_board = _BLOCKER_BOARDS[size] as EntityStatBoard
	var book := _BLOCKER_SPELLBOOKS[size] as SpellBook
	if spell_prune_m > 0.0:
		var prune_rng := RandomNumberGenerator.new()
		prune_rng.seed = spell_prune_seed
		book = book.duplicate_pruned(prune_rng, spell_prune_m)
	ent.spellbook = book
	graph.entities_container.add_child(ent)
	if core_location != null:
		# Raise-only: a core landing on a node procgen already staked (a
		# repeat addon draw, possibly past the ceiling) keeps that stake.
		var stake := maxi(core_location.stake_level, maxi(stake_level, 1))
		# Cap BEFORE the allocate: the fill is clamped to the cap, and the
		# stake_level setter re-derives the radius the halo reads.
		set_procgen_stake(core_location, stake)
		allocation_system.force_allocate(ent, core_location)
		ent.core_location = core_location
		if stake > 1:
			allocation_system.force_fill(core_location, stake)
			_offset_kill_xp_for_stake(ent, stake, stake_xp_offset_floor)
		# The core FIRST, then the bonus nodes: `force_allocate` is the setup
		# primitive, so nothing here checks adjacency — but the footprint is
		# grown connected at placement time and the class's falloff aura measures
		# hops over the owned subgraph, which only reads right with the core in it.
		for node in footprint:
			if node != null and node != core_location:
				allocation_system.force_allocate(ent, node)
	return ent


## The one procgen stake write: sets [param node]'s [member SkillNode.stake_level]
## to [param level], ungated by its ceiling, and grants one +1 `stake_ceiling`
## local modifier per level the write lands past it, so the ceiling never sits
## below a level procgen wrote. A fresh modifier per raise —
## [method SkillNode.add_local_modifier] dedupes by instance.
static func set_procgen_stake(node: SkillNode, level: int) -> void:
	node.stake_level = level
	while node.stake_level > node.stake_ceiling:
		var before := node.stake_ceiling
		node.add_local_modifier(_STAKE_CEILING_LIFT.duplicate() as StatModifier)
		if node.stake_ceiling <= before:
			push_error("EntityFactory.set_procgen_stake: a stake_ceiling lift did not land")
			return


## The #916 kill-XP offset for a pre-staked blocker, owner's formula verbatim
## (#784): `core_kill_xp × clamp(1 − (stake − 1) · XP_PER_SP / core_kill_xp,
## floor, 1)` with `XP_PER_SP = xp.value / sp_gain_on_levelup.value` — what one
## SP is worth in XP on THIS blocker's board, so the freed fill is priced in
## the board's own currency and no literal number lives here. Granted as a
## core modifier: per-entity (the board is duplicated at `initialize`), and
## it rides [EntitySnapshot] with the rest of them.
func _offset_kill_xp_for_stake(ent: Entity, stake: int, floor_: float) -> void:
	var board := ent.stat_board
	if board == null or board.core_kill_xp == null or board.xp == null \
			or board.sp_gain_on_levelup == null:
		return
	var sp_gain: float = board.sp_gain_on_levelup.value
	var kill_xp: float = board.core_kill_xp.value
	if sp_gain <= 0.0 or kill_xp <= 0.0:
		return
	# `Stat.value` is Variant-typed — cast, or an int/int pair divides as ints.
	var xp_per_sp: float = float(board.xp.value) / sp_gain
	var m := StatModifier.new()
	m.stat_id = &"core_kill_xp"
	m.operation = StatModifier.Operation.MULTIPLY
	m.value = clampf(1.0 - float(stake - 1) * xp_per_sp / kill_xp, clampf(floor_, 0.0, 1.0), 1.0)
	ent.grant_core_modifier(m)


## Rebuild an [Entity] an arriving snapshot names and this peer does not have
## (#715) — [member WorldSyncChannel.entity_spawner]'s one production implementation.
##
## [b]Only a BLOCKER, and refusing anything else is the point.[/b] Since #715 a
## joining client runs no procgen, so the entities procgen spawns that the roster
## never names — one per removable blocker (#477), 50 on the shipped preset since
## #777's density rebalance — have no other way to exist here, and their nodes
## would otherwise decode as
## unowned and move the ownership fold. Every OTHER entity is the roster's, and
## the roster spawns the same set on every peer by construction
## ([method ProcgenPlaySandbox._seat_the_roster]): a row asking for one of those
## means the two peers disagree about who is playing, which is a fault to
## surface, not to paper over by inventing a hero.
##
## The tier is what names the size — [method spawn_blocker] writes
## `entity_tier = size + 1` — and everything else the blocker needs (its tiered
## [EntityStatBoard], its scene, its `scenery` group) comes from that same call,
## which is exactly why this lives here and not in [EntitySnapshot].
##
## [b]The #586 PRUNED spellbook crosses by value (#726).[/b] The tier book this
## assigns is the WHOLE authored one; the host's is a `duplicate_pruned` slice
## of it, with no `resource_path` to intern. [method EntitySnapshot._decode_identity]
## overwrites what this hands out with a fresh book rebuilt from the row's
## [member SpellDef.id] list, so nothing here needs to know about the prune.
func spawn_snapshot_entity(
	entity_id: int, scene_path: String, tier: int, _display_name: String
) -> Entity:
	if scene_path != _BLOCKER_SCENE.resource_path:
		push_warning(
			"EntityFactory: snapshot names entity %d from '%s', which is not a blocker — "
			% [entity_id, scene_path]
			+ "the roster should have spawned it. Refusing to invent one.")
		return null
	var size := clampi(tier - 1, 0, BlockerSize.size() - 1) as BlockerSize
	# Empty footprint: on a joining peer every owned node arrives through
	# `GraphSnapshot`'s per-node `owner_id`, so there is nothing to allocate
	# here and nothing about the footprint to serialize (#777 decision 9).
	return spawn_blocker(size, null, [], 0, 0.0, entity_id)
