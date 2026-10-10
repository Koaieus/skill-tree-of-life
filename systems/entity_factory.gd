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


## Spawn a removable blocker entity (#300) owning [param core_location] and
## [param footprint]. A blocker is a plain [Entity] — no controller — whose
## tiered board ([param size] → CON/armor/health, no initiative) and the size's
## spellbook are authored under `entity/blocker/`.
##
## [b]The #777 falloff aura is NOT granted here.[/b] `blocker_entity.tscn`
## authors `core_class = blocker_core.tres`, whose `effects` array carries it,
## so [method Entity._ready] grants it on `add_child` below — the ordinary
## entity-wide effect seam, reached with no code. That class is deliberately
## not a pickable one: `pickable_in = 0`, absent from `core_class_roster.tres`,
## and filed under `entity/blocker/` rather than `entity/core/`.
##
## The aura is inert on a footprintless blocker — [ProportionalScale] puts the
## source itself at scale 0, so a lone core is the only node in scope and takes
## nothing. It is also inert at grant time on the [method spawn_snapshot_entity]
## path, which spawns with a null core; the snapshot's later `core_location`
## assignment is what fills it, since that setter dispatches `_on_core_moved`
## (a full recompute — see [member Entity.core_location]). Parents under
## `graph.entities_container` and force-allocates the core, exactly like
## [method spawn_entity] (procgen setup, not a gameplay action). Returns the
## entity, with [member Entity.entity_tier] set to size + 1 (1/2/3).
## Spawn one Dormant Core of [param size] onto [param core_location].
##
## [param spell_prune_m] is the #586 loot-book prune's shape parameter (see
## [method SpellBook.duplicate_pruned]); leaving it at `0.0` keeps the tier's
## authored book whole, which is what a hand-authored level or a fixture
## wants. [param spell_prune_seed] seeds that prune — procgen hands one out
## per placement, because every peer re-runs this and must land on the same
## book. The prune copies before it pops — the tier books are `preload`ed
## resources shared by every blocker of a size, so popping in place would
## strip the tier for the rest of the run.
##
## [param preassigned_id] adopts an [Entity] id decided elsewhere instead of
## letting [Graph] mint one (#715) — the authority's, when a snapshot is
## rebuilding a blocker on a peer that ran no procgen. `0`, the default, is
## every ordinary caller and mints as before.
##
## [param stake_level] is the #916 pre-stake (procgen rolls 1..3 per
## placement) and only RAISES the core node's cap — a node procgen already
## staked keeps its own. Ungated by the node's ceiling: a raise past it lifts
## [member SkillNode.stake_ceiling] (see [method set_procgen_stake]). The fill
## and kill-XP offset read that effective stake:
## the cap is stamped, `force_allocate` opens the 0→1 as usual, and
## [method AllocationSystem.force_fill] walks the fill to the cap — no SP
## minted for the fill, so the blocker's pool never says it bought it. A
## staked kill then frees a node already filled to 3, SP the killer never
## spent, so the kill XP is offset by a MULTIPLY on `core_kill_xp` clamped to
## `blockers_cfg.stake_xp_offset_floor` (owner's formula on #784; every input
## is a live board read). Only the CORE is staked, never the footprint. The
## snapshot adoption path ([method spawn_snapshot_entity]) leaves it at 1 and
## passes no core, so the row's own `stake_level`/`allocation_level` land
## untouched by anything here.
func spawn_blocker(size: BlockerSize, core_location: SkillNode,
		footprint: Array[SkillNode] = [], spell_prune_seed: int = 0,
		spell_prune_m: float = 0.0, preassigned_id: int = 0,
		stake_level: int = 1, stake_xp_offset_floor: float = 0.25) -> Entity:
	var ent := _BLOCKER_SCENE.instantiate() as Entity
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
