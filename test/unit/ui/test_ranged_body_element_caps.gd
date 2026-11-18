extends GutTest

## The quiver HUD shows each element bin's cap beside its count: the card of a
## fire / ice / lightning arrow carries `AmmoType.stock_cap` of that type's
## reload mint, and the goo (catalyst) card, no element bin, shows none.
## Real default board; the mint is granted by a modifier and read back.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _ROSTER: AmmoTypeRoster = preload("res://attack/ammo/ammo_type_roster.tres")
const _BODY_SCENE := preload("res://ui/hud/command_tray/bodies/ranged_body.tscn")

const _ELEMENTS: Array[StringName] = [&"fire", &"ice", &"lightning"]
const _GOO := &"catalyst"

var _entity: Entity
var _body: RangedBody


func before_each() -> void:
	var graph: Graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	_entity = autofree(Entity.new())
	_entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	graph.entities_container.add_child(_entity)
	var quiver: Quiver = _entity.stat_board.arrows
	for id in _ELEMENTS:
		var t := _ROSTER.by_id(id)
		var m := StatModifier.new()
		m.stat_id = t.per_reload_stat_id()
		m.value = 3.0
		_entity.stat_board.add_modifier(m)
		quiver.add(id, 1, t.stock_cap(int(_entity.reload_yield().get(id, 0))))
	quiver.add(_GOO, 2, Quiver.DEFAULT_MAX_STOCK)
	# Bins seeded before the bind: the first paint sets labels without a roll.
	_body = _BODY_SCENE.instantiate() as RangedBody
	add_child_autofree(_body)
	_body.bind(_entity, null, null)


func _card(type_id: StringName) -> AmmoCard:
	for c in _body.cards():
		if c.type.id == type_id:
			return c
	return null


func test_each_element_card_shows_its_bin_and_the_stock_cap_of_its_mint() -> void:
	var mint: Dictionary = _entity.reload_yield()
	for id in _ELEMENTS:
		var t := _ROSTER.by_id(id)
		var card := _card(id)
		assert_not_null(card, "%s has a card" % id)
		if card == null:
			continue
		var want := t.stock_cap(int(mint.get(id, 0)))
		assert_gt(int(mint.get(id, 0)), 0, "fixture: %s mints per reload" % id)
		assert_eq(card.bin_cap, want, "%s card's cap is stock_cap of its mint" % id)
		var label := card.get_node("%StockLabel") as Label
		assert_string_contains(label.text, "%d/%d" % [_entity.stat_board.arrows.stock_of(id), want],
				"%s card shows count / cap" % id)


func test_the_goo_card_shows_no_element_cap() -> void:
	var card := _card(_GOO)
	assert_not_null(card, "the goo bin has a card")
	if card == null:
		return
	assert_eq(card.bin_cap, 0, "goo is no element bin: no cap")
	var label := card.get_node("%StockLabel") as Label
	assert_false(label.text.contains("/"), "goo's stock label carries no cap")
