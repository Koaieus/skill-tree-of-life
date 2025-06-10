## Global singleton to manage game turns and other typical global stuff
extends Node

signal game_ready
signal turn_ended(for_entity: TreeEntity)
signal turn_started(for_entity: TreeEntity)
signal player_selected(new_player: Player)
#signal player_stats_changed(new_stats: Stats)

@export var player: Player:
	get():
		return player
	set(v):
		if v and player != v:
			player = v
			print('aaaaaaaaaaaaaaaaaaaaaaaaa')
			player_selected.emit(player)
			#player.stats.stats_changed.connect(
				#func(stats: Stats):
					#print('BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB')
					##player_stats_changed.emit(stats)
			#)

@export var turn_number: int = 0
@export var turn_order: Array[TreeEntity] = []

## Entity that has the turn
var _entity_at_turn: TreeEntity:
	get():
		return _entity_at_turn
	set(value):
		turn_ended.emit(_entity_at_turn)
		_entity_at_turn = value
		print('[TURN]: It is now %s\'s turn' % [_entity_at_turn])
		turn_started.emit(value)

## Readonly version of the entity that currently has the turn
var entity_at_turn: TreeEntity:
	get(): return _entity_at_turn

## Checks whether an entity currently has the turn
func has_turn(entity: TreeEntity) -> bool:
	if not entity or not _entity_at_turn:
		return false
	return _entity_at_turn == entity

## Ends turn for entity that currently has the turn
func end_turn() -> void:
	print('ENDING TURN!')
	# Add current entity to back of turn order
	turn_order.push_back(_entity_at_turn)
	# Get next entity in turn order list, skipping ones that are NULL
	var next: TreeEntity = null
	while not next:
		next = turn_order.pop_front()
	_entity_at_turn = next


## Called when the node enters the scene tree for the first time.
#func _ready() -> void:
	#

## Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta: float) -> void:
	#pass
