extends GutTest

## #726 — a materialized blocker keeps the host's #586 PRUNED spellbook.
##
## The host's blocker book is a [method SpellBook.duplicate_pruned] slice of its
## tier's authored `.tres`: a fresh [code]SpellBook.new()[/code] with no
## `resource_path`, so [EntitySnapshot]'s intern table has nothing to carry.
## Since #715 the client runs no procgen, so it cannot re-derive the slice
## either — [method GameRoot.spawn_snapshot_entity] hands the rebuilt blocker
## its tier's WHOLE authored book. These tests pin the by-value channel that
## closes the gap: the kept [member SpellDef.id]s ride the row and
## [method EntitySnapshot._decode_identity] rebuilds a fresh book from them.
##
## The fixture mirrors the real join exactly: the SOURCE entity holds the pruned
## book the host drew, the TARGET entity holds the whole authored one the level
## just assigned it, and the assertion is that the target ends up narrower.

const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _AUTHORED := preload("res://entity/blocker/blocker_spellbook_medium.tres")


func _new_graph() -> Graph:
	var graph: Graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	await wait_physics_frames(1)
	return graph


func _entity_with(graph: Graph, book: SpellBook, entity_id := 0) -> Entity:
	var e: Entity = autofree(Entity.new())
	e.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	e.spellbook = book
	# Before `add_child`: `Graph._mint_entity_id` assigns only where the id is
	# still 0, which is the same door `EntitySnapshot._materialize` goes through.
	e.entity_id = entity_id
	graph.entities_container.add_child(e)
	return e


## A path-less book holding exactly [param ids] — what `duplicate_pruned`
## produces, without depending on the draw.
func _pruned(ids: Array) -> SpellBook:
	var book := SpellBook.new()
	var spells: Array[SpellDef] = []
	for id in ids:
		spells.append(SpellCatalog.by_id(StringName(id)))
	book.spells = spells
	return book


## Round-trip [param source]'s entity state onto [param target].
func _cross(source: Graph, target: Graph) -> void:
	EntitySnapshot.decode(EntitySnapshot.encode(source), target)


func _ids_of(book: SpellBook) -> Array:
	var out: Array = []
	for spell in book.spells:
		out.append(String(spell.id))
	return out


## The point of the issue: the client's copy is the host's SLICE, not the tier's
## whole authored book it started the decode holding.
func test_the_kept_slice_crosses_and_the_whole_book_does_not() -> void:
	var source := await _new_graph()
	var host := _entity_with(source, _pruned(["resonator"]))

	var target := await _new_graph()
	var peer := _entity_with(target, _AUTHORED, host.entity_id)
	assert_eq(peer.spellbook.spells.size(), 3, "sanity: it starts with the whole tier book")

	_cross(source, target)

	assert_eq(_ids_of(peer.spellbook), ["resonator"],
			"the client holds the host's slice, not its tier's authored book")


## The prune chain is documented to be able to run all the way to EMPTY — that
## is the case an "absent means say nothing" encoding silently turns back into
## the whole authored book, so `null` and `[]` must stay different answers.
func test_a_book_pruned_to_empty_crosses_as_empty() -> void:
	var source := await _new_graph()
	var host := _entity_with(source, _pruned([]))

	var target := await _new_graph()
	var peer := _entity_with(target, _AUTHORED, host.entity_id)

	_cross(source, target)

	assert_eq(peer.spellbook.spells.size(), 0,
			"an empty slice crosses as empty, not as 'no opinion'")


## The rebuild REPLACES rather than reconciles into whatever this peer was
## holding, so the result never depends on the level's tier default — and a
## fixture that handed over an authored `.tres` directly does not get that
## shared const narrowed under it for the rest of the process.
func test_the_rebuild_replaces_rather_than_narrows() -> void:
	var source := await _new_graph()
	var host := _entity_with(source, _pruned(["leafblower"]))

	var target := await _new_graph()
	var peer := _entity_with(target, _AUTHORED, host.entity_id)

	_cross(source, target)

	assert_eq(_AUTHORED.spells.size(), 3, "the authored const still holds its three spells")
	assert_ne(peer.spellbook, _AUTHORED, "the peer got a FRESH book, not the const narrowed")


## The by-value list is what carries EVERY book, pruned or not:
## [method Entity._ready] deep-copies whatever `spellbook` it was handed, and a
## `duplicate` has no `resource_path` — so [constant EntitySnapshot._R_SPELLBOOK]'s
## interned path has always been -1 for a live entity and the spellbook never
## actually crossed. That is why this is a fix and not a widening.
func test_even_a_plainly_authored_book_crosses_by_value() -> void:
	var source := await _new_graph()
	var host := _entity_with(source, _AUTHORED)
	assert_eq(host.spellbook.resource_path, "",
			"_ready duplicated it, so there is no path left to intern")

	var target := await _new_graph()
	var peer := _entity_with(target, null, host.entity_id)

	_cross(source, target)

	assert_eq(_ids_of(peer.spellbook), ["leafblower", "resonator", "trail_blazer"],
			"the whole authored membership crossed, by id")
	assert_eq(EntitySnapshot._encode_spell_ids(_AUTHORED), null,
			"a book that DOES have a path still says nothing by value")


## The rebuilt book holds the CONST defs [method SpellCatalog.by_id] returns,
## never a copy of them — which is what [SpellDef] identity comparisons against a
## live plan's `spell` need (#511).
func test_the_rebuilt_book_holds_the_canonical_defs() -> void:
	var source := await _new_graph()
	var host := _entity_with(source, _AUTHORED)

	var target := await _new_graph()
	var peer := _entity_with(target, null, host.entity_id)

	_cross(source, target)

	assert_true(is_same(peer.spellbook.spells[0], SpellCatalog.LEAFBLOWER),
			"the very same object, because it came back through by_id")


## The rebuilt book is a loot pool, exactly like `duplicate_pruned`'s output:
## every spell in it reads as innate, with no [SkillNode] source behind it.
func test_the_rebuilt_book_carries_no_sources() -> void:
	var source := await _new_graph()
	var host := _entity_with(source, _pruned(["trail_blazer"]))

	var target := await _new_graph()
	var peer := _entity_with(target, _AUTHORED, host.entity_id)

	_cross(source, target)

	var spell := SpellCatalog.by_id(&"trail_blazer")
	assert_eq(peer.spellbook.source_count(spell), 0, "no grant source behind a looted pool entry")
	assert_eq(peer.spellbook.permanent_spells(null).size(), 1, "so it reads as innate")
	assert_true(spell in peer.spellbook.permanent_spells(null), "and it is that spell")


## An id the catalog does not know is dropped with a warning rather than
## crossing as a null hole in `spells` — the failure a silent skip would hide.
func test_an_unknown_id_is_dropped_loudly() -> void:
	var target := await _new_graph()
	var peer := _entity_with(target, _AUTHORED, 0)
	var row: Array = []
	row.resize(12)
	row[EntitySnapshot._R_ENTITY_ID] = peer.entity_id
	row[EntitySnapshot._R_CORE_CLASS] = -1
	row[EntitySnapshot._R_FACTION] = -1
	row[EntitySnapshot._R_SPELLBOOK] = -1
	row[EntitySnapshot._R_TIER] = 2
	row[EntitySnapshot._R_SPELL_IDS] = ["bruiser", "no_such_spell"]

	EntitySnapshot._decode_identity(peer, row, [] as Array)

	assert_eq(_ids_of(peer.spellbook), ["bruiser"], "the known id survived, the unknown one did not")
