class_name EntitySnapshot
extends RefCounted

## The ENTITY half of the join handshake, sibling to [GraphSnapshot]: what each
## entity has ACCUMULATED (board, effects, tags, core), so a joining peer's
## boards match the authority's from the first frame. Three tiers — authored
## crosses as an interned ref, accumulated by value, derived never. It
## decorates the entities the roster spawned, prunes the ones the payload does
## not name, and materializes (blockers only, via a spawner callback) the ones
## it names that are absent. Two passes: [method decode] before the graph
## decodes, [method resolve_graph_refs] after — both idempotent — and in each
## pass effects are granted BEFORE the board is restored. Never
## `var_to_bytes(..., full_objects = true)`.
## See docs/domain/entity-snapshot.md.

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
const _R_SCENE := 8      ## `scene_file_path` interned into `res`, -1 for none — see [method _materialize]
const _R_NAME := 9       ## Entity.display_name — carried only so a materialized row is not nameless
const _R_SPELL_IDS := 10 ## Array of indices into `spells`, or null — see [method _encode_spell_ids]
const _R_TURNS := 11     ## Entity.turns_taken — see [method restore_turn_cursor]
const _R_VOLLEYS := 12   ## Entity.volleys_launched_this_turn — a mid-turn arrival keeps the budget spent
const _R_TURN_LEAVES := 13 ## Entity.get_turn_start_leaves() as stable_ids — pass 2 only
const _R_CORE_MOVED := 14 ## Entity.core_moved_this_turn — a mid-turn arrival must not exert a second time
const _R_RING_SPENT := 15 ## Entity.ring_spent as Strings (ring cell names); the ring_points pool rides _R_BOARD
## Row length: one past the last `_R_*` index.
const _ROW_SIZE := 16


## Build the payload for every [Entity] under `graph.entities_container`.
## [b]Two intern tables, deliberately not one.[/b] `res` holds resource PATHS
## and is the only thing [method _load_interned] ever calls `load()` on; `spells`
## holds [member SpellDef.id]s, which are wire names and not loadable. Folding
## them together would save one small array and put a string in `res` that a
## future reader is entitled to assume is a path.
static func encode(graph: Graph) -> PackedByteArray:
	var table := GraphSnapshot._InternTable.new()
	var spell_table := GraphSnapshot._InternTable.new()
	var rows: Array = []
	for e in entities_of(graph):
		rows.append(_encode_entity(graph, e, table, spell_table))
	return GraphSnapshot._pack({
		"res": table.paths, "spells": spell_table.paths, "entities": rows,
		"turn": _encode_turn_cursor(graph),
	})


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
	var spells: Array = payload.get("spells", [])
	var rows: Array = payload.get("entities", [])
	_prune_entities(graph, rows)
	for row in rows:
		var e := _resolve(graph, row as Array, res, spawner)
		if e == null:
			continue
		_decode_identity(e, row as Array, res, spells)
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
		_restore_turn_start_leaves(e, graph, row as Array)
		_grant_effects(e, graph, row as Array, res, true)
		_restore_board(e, row as Array)


## The per-turn reload producer set, by stable_id. Replaced wholesale, so a
## second pass is idempotent; a leaf the graph no longer has is dropped, as
## [method Entity.reload_yield] would skip it anyway. Width-guarded like
## [constant _R_TURNS].
static func _restore_turn_start_leaves(e: Entity, graph: Graph, row: Array) -> void:
	if row.size() <= _R_TURN_LEAVES:
		return
	var leaves: Array[SkillNode] = []
	for id in (row[_R_TURN_LEAVES] as Array):
		var node := graph.get_by_stable_id(int(id))
		if node != null:
			leaves.append(node)
	e.restore_turn_start_leaves(leaves)


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
	var spell_table := GraphSnapshot._InternTable.new()
	var rows: Array = []
	for e in entities:
		rows.append(_encode_entity(graph, e, table, spell_table))
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


static func _encode_entity(
	graph: Graph, e: Entity, table: GraphSnapshot._InternTable,
	spell_table: GraphSnapshot._InternTable
) -> Array:
	var effects: Array = []
	for inst in e.get_effects():
		if inst == null or inst.effect == null or inst.effect.resource_path == "":
			# Same rule GraphSnapshot applies to a `.new()`-built effect: real
			# content is always a shared `.tres`, so a path-less resource is a
			# test fixture and is dropped rather than crossing broken.
			continue
		var src := 0
		if inst.source_node != null and is_instance_valid(inst.source_node):
			src = graph.get_stable_id(inst.source_node)
		effects.append([table.intern(inst.effect.resource_path), src])
	var leaves: Array = []
	for n in e.get_turn_start_leaves():
		if is_instance_valid(n) and graph.get_stable_id(n) != 0:
			leaves.append(graph.get_stable_id(n))
	var row: Array
	row.resize(_ROW_SIZE)
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
	row[_R_SPELL_IDS] = _encode_spell_ids(e.spellbook, spell_table)
	row[_R_TURNS] = e.turns_taken
	row[_R_VOLLEYS] = e.volleys_launched_this_turn
	row[_R_TURN_LEAVES] = leaves
	row[_R_CORE_MOVED] = e.core_moved_this_turn
	var ring: Array = []
	for cell in e.ring_spent:
		ring.append(String(cell))
	row[_R_RING_SPENT] = ring
	return row


## The membership of a spellbook that has no `resource_path` to intern, by value;
## `null` for every book that HAS one. `null` and `[]` are different answers. Ids
## (`SpellDef.id`), never paths, are the cross-process reference, and are interned
## through `spell_table`.
## See docs/domain/snapshot-encoding.md
static func _encode_spell_ids(
	book: SpellBook, spell_table: GraphSnapshot._InternTable
) -> Variant:
	if book == null or book.resource_path != "":
		return null
	var ids: Array = []
	for spell in book.spells:
		if spell != null and spell.id != &"":
			ids.append(spell_table.intern(String(spell.id)))
	return ids


## The level's [TurnManager] cursor — `[current_entity_id, turns_taken,
## rounds_completed, round_open, [waiting entity ids]]`, with 0 for "nobody is
## holding the turn". The round state (#1257) rides with the tally for the same
## reason the tally does: a mirror counting its own would end a turn-limited
## run on a different turn. Payload-level rather than a row, because
## it is the LEVEL's state and not any one entity's.
##
## [b]Why it crosses at all (#756).[/b] Who holds the turn, and how many turns
## have been served, are host DECISIONS. A joining peer whose world was encoded
## after the host opened its first turn has no way to reproduce either — it
## heard none of the emits — and every [EndTurnCommand] after that reproduces
## [method TurnManager._tick_until_ready] from whatever cursor it invented for
## itself. Turn-start upkeep then runs for the wrong entity on the wrong turn,
## which moves node HP caps, regen stacks and pool currents: exactly the
## accumulated-tier drift #756 measured. [member RunOutcome.turn_count] is the
## same gap read out loud (host 48, client 38).
static func _encode_turn_cursor(graph: Graph) -> Array:
	var tm := _turn_manager_of(graph)
	if tm == null:
		return [0, 0]
	var holder := 0
	if tm.current_entity != null and is_instance_valid(tm.current_entity):
		holder = tm.current_entity.entity_id
	var waiting: Array = []
	for e in tm.round_waiting():
		if is_instance_valid(e):
			waiting.append(e.entity_id)
	return [
		holder, tm.turns_taken, tm.rounds_completed, tm.is_round_open(), waiting,
		tm.world_turn_progress,
	]


## Adopt the authority's turn cursor. A FIFTH decode step, run last — after
## [method GraphSnapshot.restore_hp] — because [method TurnManager.adopt_turn]
## emits [signal TurnManager.turn_started] and every listener of it (the HUD
## banner, the initiative bar, the action cluster, the seat handover) reads a
## world that must already be whole.
##
## [param turn_manager] is passed in rather than looked up: this class knows
## about rows, and [WorldSyncChannel] is the one that holds the level's wiring.
## Optional only in the sense that a null one is a no-op — a caller that has no
## [TurnManager] has no cursor to repair.
static func restore_turn_cursor(
	bytes: PackedByteArray, graph: Graph, turn_manager: TurnManager
) -> void:
	if graph == null or turn_manager == null or bytes.is_empty():
		return
	var payload := GraphSnapshot._unpack(bytes)
	var cursor: Array = payload.get("turn", [])
	if cursor.size() < 2:
		return
	var holder_id := int(cursor[0])
	var holder: Entity = graph.get_by_entity_id(holder_id) if holder_id != 0 else null
	if holder_id != 0 and holder == null:
		push_warning(
			"EntitySnapshot: turn cursor names entity %d, which this peer does not have"
			% holder_id
		)
		return
	if cursor.size() < 5:
		turn_manager.adopt_turn(holder, int(cursor[1]))
		return
	# The open round's roster, by id (#1257). A member this peer does not have
	# is skipped: it cannot take a turn here to close the round anyway.
	var waiting: Array[Entity] = []
	for id in cursor[4]:
		var e := graph.get_by_entity_id(int(id))
		if e != null:
			waiting.append(e)
	# The world turn's progress (ADR 0055); a five-element cursor predates it.
	var world_progress := int(cursor[5]) if cursor.size() >= 6 else 0
	turn_manager.adopt_turn(
		holder, int(cursor[1]), int(cursor[2]), bool(cursor[3]), waiting, world_progress)


## The level's single [TurnManager], found the same way [Entity] finds it — by
## group, never by scene-tree depth. Null in a bare-graph fixture, which is why
## [method _encode_turn_cursor] has a zero answer.
static func _turn_manager_of(graph: Graph) -> TurnManager:
	if graph == null or not graph.is_inside_tree():
		return null
	return graph.get_tree().get_first_node_in_group(TurnManager.GROUP) as TurnManager


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


## Ask `spawner` for the `Entity` a row names when this peer lacks it; null when
## there is no spawner or it declines. The id is the authority's, stamped before
## the entity enters `entities_container`. A callback, not `instantiate()`: the
## level knows how to build a board.
## See docs/domain/snapshot-encoding.md
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
static func _decode_identity(e: Entity, row: Array, res: Array, spells: Array) -> void:
	var cc := _load_interned(res, int(row[_R_CORE_CLASS])) as CoreClass
	if cc != null:
		e.core_class = cc
	var f := _load_interned(res, int(row[_R_FACTION])) as Faction
	if f != null:
		e.faction = f
	var sb := _load_interned(res, int(row[_R_SPELLBOOK])) as SpellBook
	if sb != null:
		e.spellbook = sb
	else:
		_restore_pruned_spellbook(e, row, spells)
	e.entity_tier = int(row[_R_TIER])
	# #756. Accumulated, not derived: it gates the first-turn upkeep skip, and a
	# peer whose world arrived as a snapshot never heard the `turn_started`s that
	# produced it. Guarded on width so a hand-built fixture row predating the
	# slot decodes as "says nothing" rather than as 0.
	if row.size() > _R_TURNS:
		e.turns_taken = int(row[_R_TURNS])
	if row.size() > _R_VOLLEYS:
		e.volleys_launched_this_turn = int(row[_R_VOLLEYS])
	if row.size() > _R_CORE_MOVED:
		e.core_moved_this_turn = bool(row[_R_CORE_MOVED])
	# Replaced, never appended: decode runs once per pass and must stay idempotent.
	if row.size() > _R_RING_SPENT and row[_R_RING_SPENT] is Array:
		var spent: Array[StringName] = []
		for cell in (row[_R_RING_SPENT] as Array):
			spent.append(StringName(cell))
		e.ring_spent = spent


## Rebuild the by-value book `_encode_spell_ids` sent. A no-op when membership
## already agrees (idempotent); otherwise always a FRESH `SpellBook`, compared by
## id and in order. Assumes no `SpellGrant` crosses (a tripwire test pins it).
## See docs/domain/snapshot-encoding.md
static func _restore_pruned_spellbook(e: Entity, row: Array, interned: Array) -> void:
	if row.size() <= _R_SPELL_IDS or row[_R_SPELL_IDS] == null:
		return
	var spells: Array[SpellDef] = []
	for idx in (row[_R_SPELL_IDS] as Array):
		if int(idx) < 0 or int(idx) >= interned.size():
			push_warning(
				"EntitySnapshot: entity %d's spellbook names intern slot %d, which the payload does not have"
				% [e.entity_id, int(idx)]
			)
			continue
		var id := StringName(interned[int(idx)])
		var spell := SpellCatalog.by_id(id)
		if spell == null:
			push_warning(
				"EntitySnapshot: entity %d's spellbook names spell '%s', which SpellCatalog does not know — dropping it"
				% [e.entity_id, id]
			)
			continue
		spells.append(spell)
	if _same_membership(e.spellbook, spells):
		return
	var book := SpellBook.new()
	book.spells = spells
	e.spellbook = book


## Does [param book] already hold exactly [param wanted], same ids in the same
## order? A null book never does — not even against an empty list, since "no
## book" and "an empty book" are different things to [method Entity.get_spellbook].
static func _same_membership(book: SpellBook, wanted: Array[SpellDef]) -> bool:
	if book == null or book.spells.size() != wanted.size():
		return false
	for i in wanted.size():
		var have := book.spells[i]
		if have == null or have.id != wanted[i].id:
			return false
	return true


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
