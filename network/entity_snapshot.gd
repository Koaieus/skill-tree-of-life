class_name EntitySnapshot
extends RefCounted

## The ENTITY half of the join handshake (#560), sibling to [GraphSnapshot] —
## one encoder, one subject, composed alongside at the same handshake point
## with its own [constant CommandLink.KIND_ENTITIES] envelope. Child of #521;
## the tiering vocabulary and the reasons for it are [GraphSnapshot]'s docblock,
## and this class obeys the same three tiers.
##
## [b]The bug this closes.[/b] [method GraphSnapshot._decode_node] sets
## `node.owned_by` directly, bypassing [AllocationSystem], and nothing rebuilt
## the owner's [EntityStatBoard] from that decoded ownership. A client joining
## mid-run therefore held boards missing every allocated node's grants AND every
## looted relic. [method NodeCombat.get_local_value] merges a node's board with
## its OWNER's, and `node_health` is a borrowed stat — the entity carries the
## baseline — so a missing `+5 CON` moved every health bar that entity owns at
## once, silently, from the client's first frame.
##
## [b]Three tiers.[/b]
## - Authored ([CoreClass], [Faction], [SpellBook], each granted [Effect])
##   crosses as an INTERNED REF into a per-snapshot path table, exactly as
##   archetypes and addons do next door.
## - Accumulated (per-stat `base_value` and the applied modifier list, every
##   [member PoolStat.current], [SkillPointStat]'s `wounded`/`staked`,
##   [member SurplusPoolStat.surplus], the granted [EffectInstance]s with their
##   source node's `stable_id`, active tags, [member Entity.entity_tier],
##   [member Entity.core_location] by `stable_id`) crosses BY VALUE.
## - Derived (board totals, [member Stat.bins], aura contributions, vision)
##   NEVER crosses. The receiver recomputes.
##
## [b]Modifiers cross by value, not interned, and that is not a tier violation.[/b]
## [method Entity.initialize] does `stat_board = stat_board.duplicate(true)`, and
## a duplicated sub-resource carries no `resource_path` — so a LIVE board's
## intrinsics and class modifiers have nothing to intern. The authored/accumulated
## split collapses to by-value for modifiers on any board that is actually in
## play, which is the only kind this class ever encodes.
##
## [b]It DECORATES; it never spawns and never mints an `entity_id` (#560 D7) —
## but since #561 it does REMOVE.[/b]
## #528 (roster replication) and #553 (the level spawns from the session roster)
## both shipped, so a joining client's entities exist by the time state arrives.
## Every row resolves through [method Graph.get_by_entity_id] and a row whose
## entity is absent is SKIPPED with a warning — mirroring how
## [method GraphSnapshot._decode_node] decodes an unresolvable `owner_id` as
## unowned rather than inventing an entity. A snapshot that spawned would be a
## second entity-minting path racing the roster's. The reverse direction is
## different and is not symmetric with it: an entity the payload does NOT name
## does not exist in the authority's world at all, and
## [method _prune_entities] drops it. Join never needed that (the roster spawns
## exactly the named set); a resync does.
##
## [b]Two passes, and the order is load-bearing (#560 D5).[/b]
## [method decode] runs BEFORE the graph decodes (it needs no nodes);
## [method resolve_graph_refs] runs AFTER, because `core_location` and an
## effect's `source_node` resolve entity->node, the opposite direction from
## [method GraphSnapshot._decode_node]'s `owner_id`. Both passes are idempotent:
## effects are granted only if an equal grant is not already present, tags only
## if not already held, and [method StatBoard.read_dict] reconciles rather than
## rebuilds. That is what lets pass 2 re-run the board restore to absorb the
## node-sourced effects it just granted.
##
## [b]Effects are granted BEFORE the board is restored, in each pass.[/b]
## [method EffectContext.grant] puts a modifier on the board and records the
## HANDLE in the [EffectInstance] ledger, which revokes by object identity. Grant
## first, then reconcile, and the reconcile recognises the effect's own modifier
## by wire form and leaves the handle in place — so a later
## [method Entity.revoke_effects_from] on the client actually removes something.
## Restoring the board first and granting after would double every effect's
## contribution instead, which is the very failure mode this issue exists to
## kill.
##
## No `var_to_bytes(obj, full_objects = true)` anywhere: it instantiates
## arbitrary objects from script paths in the payload (#560 D6). Everything
## object-shaped goes through [StatModifierCodec] or an interned resource path.

## Entity row indices — same positional-row convention as [GraphSnapshot]'s
## `_R_*` consts, and for the same reason (string keys roughly double a naive
## payload).
const _R_ENTITY_ID := 0
const _R_BOARD := 1      ## StatBoard.to_dict() — keyed by stat id, not positional
const _R_CORE_CLASS := 2 ## index into `res`, -1 for none
const _R_FACTION := 3    ## index into `res`, -1 for none
const _R_SPELLBOOK := 4  ## index into `res`, -1 for none
const _R_TIER := 5       ## Entity.entity_tier
const _R_CORE_LOC := 6   ## core_location's stable_id, 0 for none — pass 2 only
const _R_EFFECTS := 7    ## Array of [res_idx, source_stable_id] (0 = entity-wide)
const _R_TAGS := 8       ## Array of [name, refcount] — see [method _restore_tags]
const _R_SCENE := 9      ## `scene_file_path` interned into `res`, -1 for none — see [method _materialize]
const _R_NAME := 10      ## Entity.display_name — carried only so a materialized row is not nameless


## Build the payload for every [Entity] under `graph.entities_container`.
static func encode(graph: Graph) -> PackedByteArray:
	var table := GraphSnapshot._InternTable.new()
	var rows: Array = []
	for e in entities_of(graph):
		rows.append(_encode_entity(graph, e, table))
	return GraphSnapshot._pack({"res": table.paths, "entities": rows})


## Pass 1 — everything that needs no [SkillNode]. Run this BEFORE
## [method GraphSnapshot.decode]; run [method resolve_graph_refs] with the same
## bytes after.
## [param spawner] is how a row this peer has no [Entity] for gets one — see
## [method _materialize]. Optional: left unset (every existing caller, every
## test) this class behaves exactly as it did before #715 and a missing entity is
## skipped with a warning.
static func decode(bytes: PackedByteArray, graph: Graph, spawner := Callable()) -> void:
	if graph == null or bytes.is_empty():
		return
	var payload := GraphSnapshot._unpack(bytes)
	var res: Array = payload.get("res", [])
	var rows: Array = payload.get("entities", [])
	_prune_entities(graph, rows)
	for row in rows:
		var e := _resolve(graph, row as Array, res, spawner)
		if e == null:
			continue
		_decode_identity(e, row as Array, res)
		# Entity-wide grants only (source_stable_id 0) — a node-sourced effect
		# has nothing to resolve against yet.
		_grant_effects(e, graph, row as Array, res, false)
		_restore_board(e, row as Array)


## An [Entity] the payload does not name does not exist in the authority's
## world, so it does not exist here (#561 gap 1). It runs FIRST, before any row
## is decorated, so [method GraphSnapshot.decode] — which resolves `owner_id`
## through [method Graph.get_by_entity_id] — can never hand a node to a
## corpse this peer was about to drop.
##
## [b]This is a repair, not a death.[/b] It is deliberately NOT
## [method Entity.die]: no [signal Events.entity_dying], no loot, no victory
## check. The entity was never supposed to be here, so nothing about its
## leaving is an event anyone should see (#561 acceptance 6).
##
## Nothing on the JOIN path reaches this — the roster (#528/#553) spawns
## exactly the entities the payload names.
static func _prune_entities(graph: Graph, rows: Array) -> void:
	if rows.is_empty():
		return
	var named: Dictionary[int, bool] = {}
	for row in rows:
		named[int((row as Array)[_R_ENTITY_ID])] = true
	for e in entities_of(graph):
		if named.has(e.entity_id):
			continue
		# `remove_child` before `queue_free`: the id index drops on
		# `child_exiting_tree`, and a deferred free would leave
		# [method Graph.get_by_entity_id] answering with a doomed entity for
		# the rest of this frame — which is exactly the window the graph half
		# of the resync decodes in.
		e.get_parent().remove_child(e)
		e.queue_free()


## Pass 2 — the entity->node references, after [method GraphSnapshot.decode]
## has built the nodes: `core_location`, and every effect a node granted. The
## board is reconciled again afterwards so the modifiers those grants just put
## on it are recognised rather than churned; see this class's docblock.
static func resolve_graph_refs(
	bytes: PackedByteArray, graph: Graph, spawner := Callable()
) -> void:
	if graph == null or bytes.is_empty():
		return
	var payload := GraphSnapshot._unpack(bytes)
	var res: Array = payload.get("res", [])
	for row in (payload.get("entities", []) as Array):
		var e := _resolve(graph, row as Array, res, spawner)
		if e == null:
			continue
		var loc_id := int((row as Array)[_R_CORE_LOC])
		if loc_id != 0:
			var node := graph.get_by_stable_id(loc_id)
			if node != null:
				e.core_location = node
		_grant_effects(e, graph, row as Array, res, true)
		_restore_board(e, row as Array)
		_restore_tags(e, row as Array)


## Bytes-per-entity at the CURRENT roster size — the sibling of
## [method GraphSnapshot.bytes_per_node], so a size guard extrapolates rather
## than generating a huge roster inside the unit suite. Excludes the once-sent
## `res` table, for the same reason that one does: interning is exactly what
## stops it being per-entity.
static func bytes_per_entity(graph: Graph) -> float:
	var entities := entities_of(graph)
	if entities.is_empty():
		return 0.0
	var table := GraphSnapshot._InternTable.new()
	var rows: Array = []
	for e in entities:
		rows.append(_encode_entity(graph, e, table))
	return float(GraphSnapshot._pack({"entities": rows}).size()) / float(entities.size())


## Every [Entity] under the graph's `entities_container`, in child order. Public
## because a caller measuring or logging a snapshot wants the same set the
## encoder walked, and re-deriving it invites the two to drift.
static func entities_of(graph: Graph) -> Array[Entity]:
	var out: Array[Entity] = []
	if graph == null or graph.entities_container == null:
		return out
	for child in graph.entities_container.get_children():
		if child is Entity:
			out.append(child)
	return out


static func _encode_entity(graph: Graph, e: Entity, table: GraphSnapshot._InternTable) -> Array:
	var effects: Array = []
	for inst in e.get_effects():
		if inst == null or inst.effect == null or inst.effect.resource_path == "":
			# Same rule GraphSnapshot applies to a `.new()`-built keystone: real
			# content is always a shared `.tres`, so a path-less resource is a
			# test fixture and is dropped rather than crossing broken.
			continue
		var src := 0
		if inst.source_node != null and is_instance_valid(inst.source_node):
			src = graph.get_stable_id(inst.source_node)
		effects.append([table.intern(inst.effect.resource_path), src])
	var tags: Array = []
	for t in e.get_active_tags():
		tags.append([String(t), e.get_tag_count(t)])
	var row: Array
	row.resize(11)
	row[_R_SCENE] = table.intern(e.scene_file_path) if e.scene_file_path != "" else -1
	row[_R_NAME] = e.display_name
	row[_R_ENTITY_ID] = e.entity_id
	row[_R_BOARD] = e.stat_board.to_dict() if e.stat_board != null else {}
	row[_R_CORE_CLASS] = _intern_of(table, e.core_class)
	row[_R_FACTION] = _intern_of(table, e.faction)
	row[_R_SPELLBOOK] = _intern_of(table, e.spellbook)
	row[_R_TIER] = e.entity_tier
	row[_R_CORE_LOC] = graph.get_stable_id(e.core_location) if e.core_location != null else 0
	row[_R_EFFECTS] = effects
	row[_R_TAGS] = tags
	return row


static func _intern_of(table: GraphSnapshot._InternTable, r: Resource) -> int:
	if r == null or r.resource_path == "":
		return -1
	return table.intern(r.resource_path)


static func _resolve(graph: Graph, row: Array, res: Array, spawner: Callable) -> Entity:
	var id := int(row[_R_ENTITY_ID])
	var e := graph.get_by_entity_id(id)
	if e == null:
		e = _materialize(row, res, spawner)
	if e == null:
		push_warning(
			"EntitySnapshot: no entity with id %d to decorate — the roster (#528) must land before entity state does"
			% id
		)
	return e


## Ask [param spawner] for the [Entity] a row names when this peer does not have
## it (#715). Null when there is no spawner, or when it declines.
##
## [b]This relaxes #560 D7, and the premise D7 rested on is what changed.[/b]
## That decision — "it decorates, it never spawns" — was justified by "#528 and
## #553 both shipped, so a joining client's entities exist by the time state
## arrives": the roster spawns exactly the named set, so a spawning snapshot
## would be a second minting path racing it. That held while BOTH peers ran
## procgen. Since #715 the client runs none, and procgen spawns entities the
## ROSTER NEVER NAMES — one [Entity] per removable blocker (#477), ~120 of them
## on the shipped 800-node preset. They have no other way to arrive, and without
## them the client decodes their nodes as UNOWNED, which moves
## [method WorldFingerprint.compute]'s ownership fold on the very first compare.
##
## [b]It is not a second minting path.[/b] The id is the AUTHORITY's, taken from
## the row and stamped before the entity enters `entities_container` —
## [method Graph._mint_entity_id] assigns only to an entity whose `entity_id` is
## still `0`. It is the exact mirror of [method _prune_entities], which already
## deletes an entity the payload does not name: the payload is the authority's
## entity SET, and both directions of that set now cross.
##
## [b]Why a CALLBACK and not an `instantiate()` here.[/b] The row's scene path is
## carried ([constant _R_SCENE]) and this class could instantiate it — but a
## blocker's [EntityStatBoard] is assigned in CODE per tier
## (`GameRoot.spawn_blocker`), not authored in `blocker_entity.tscn`, and
## [method StatBoard.read_dict] cannot rebuild a board from nothing:
## [EntityStatBoard] refuses to mint a stat it has no field for, by design. A
## bare instantiate would therefore produce a blocker with no board and no
## health, which the accumulated fold would then disagree about instead. So the
## LEVEL builds it — it is the one that knows what a blocker is — and this class
## keeps knowing only about rows. See [method GameRoot.spawn_snapshot_entity].
static func _materialize(row: Array, res: Array, spawner: Callable) -> Entity:
	if not spawner.is_valid() or row.size() <= _R_SCENE:
		return null
	var scene_path := ""
	var idx := int(row[_R_SCENE])
	if idx >= 0 and idx < res.size():
		scene_path = String(res[idx])
	if scene_path.is_empty():
		return null
	return spawner.call(
			int(row[_R_ENTITY_ID]), scene_path, int(row[_R_TIER]),
			String(row[_R_NAME])) as Entity


## The authored tier. [member Entity.core_class] is assigned but NOT re-applied:
## `CoreClass.apply()` pushes its identity modifiers onto the board, and those
## already ride in the board payload by value. Applying here would double them —
## the same trap the effect ordering avoids one method down.
static func _decode_identity(e: Entity, row: Array, res: Array) -> void:
	var cc := _load_interned(res, int(row[_R_CORE_CLASS])) as CoreClass
	if cc != null:
		e.core_class = cc
	var f := _load_interned(res, int(row[_R_FACTION])) as Faction
	if f != null:
		e.faction = f
	var sb := _load_interned(res, int(row[_R_SPELLBOOK])) as SpellBook
	if sb != null:
		e.spellbook = sb
	e.entity_tier = int(row[_R_TIER])


static func _load_interned(res: Array, idx: int) -> Resource:
	if idx < 0 or idx >= res.size():
		return null
	return load(String(res[idx]))


## Grant the rows this pass owns — [param node_sourced] false picks the
## entity-wide grants (pass 1), true picks the node-sourced ones (pass 2).
## Skips a grant the entity already carries, which is what makes both passes
## re-runnable (and a #561 resync cheap).
static func _grant_effects(
	e: Entity, graph: Graph, row: Array, res: Array, node_sourced: bool
) -> void:
	for pair in (row[_R_EFFECTS] as Array):
		var src_id := int((pair as Array)[1])
		if (src_id != 0) != node_sourced:
			continue
		var effect := _load_interned(res, int((pair as Array)[0])) as Effect
		if effect == null:
			continue
		var src: SkillNode = graph.get_by_stable_id(src_id) if src_id != 0 else null
		if src_id != 0 and src == null:
			continue
		if _has_grant(e, effect, src):
			continue
		e.grant_effect(effect, src)


static func _has_grant(e: Entity, effect: Effect, src: SkillNode) -> bool:
	for inst in e.get_effects():
		if inst.effect == effect and inst.source_node == src:
			return true
	return false


static func _restore_board(e: Entity, row: Array) -> void:
	if e.stat_board == null:
		return
	e.stat_board.read_dict(row[_R_BOARD] as Dictionary)


## Tags reconcile to the authority's REFCOUNT, not merely to its name set
## (#561 gap 2). [member Entity._tags] is refcounted — a tag applied twice and
## removed once is still active — so a restore that only asked `has_tag` would
## silently collapse every stacked marker to one application, and a resync
## would be the thing that broke it.
##
## Reading the LIVE count and moving it to the wanted one is also what keeps
## this composable with the grants above: an effect re-granted in pass 2 has
## already put its own tag row back, so this sees the count it produced and
## adds nothing on top. That is the double-count the name-only version avoided
## by being lossy instead.
##
## Runs in pass 2, after the node-sourced effects, for that reason.
static func _restore_tags(e: Entity, row: Array) -> void:
	var wanted: Dictionary[StringName, int] = {}
	for entry in (row[_R_TAGS] as Array):
		wanted[StringName((entry as Array)[0])] = int((entry as Array)[1])
	for tag in wanted:
		var have := e.get_tag_count(tag)
		for _i in maxi(0, wanted[tag] - have):
			e.add_tag(tag)
		for _i in maxi(0, have - wanted[tag]):
			e.remove_tag(tag)
	for tag in e.get_active_tags():
		if wanted.has(tag):
			continue
		for _i in e.get_tag_count(tag):
			e.remove_tag(tag)
