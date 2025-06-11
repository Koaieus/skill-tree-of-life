@tool
extends TreeEntity
class_name Player

signal level_up(new_level: int, difference: int)
signal level_down(new_level: int, difference: int)

@export var player_name: String = "Player"

@export var level: int = 1:
	get(): return level
	set(value):
		var difference: int = level - value
		level = value
		if difference == 0:
			return
		if difference > 0:
			_on_level_up(value, difference)
		else:
			_on_level_down(value, difference)
		

func _to_string() -> String:
	return 'Player<%s>' % player_name

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	super()
	print('level: ', level)
	if level > 1:
		print_debug('Starting level: %s; increasing default max number of skill points accordingly' % level)
		#print('Current max skill points BEFORE increase to %s: %s' % [level, stats.skill_points._max.value])
		#stats.skill_points._max.value = level
		#stats.skill_points._max.base_value += 5 # <- works kinda
		stats.skill_points._max.default_value = level
		#stats.skill_points.increase(level-1)
		#print('Current max skill points AFTER increase to %s: %s' % [level, stats.skill_points._max.value])

		var x = 3
	#stats.stats_changed.connect(
		#func():
			#print('my stats changed!')
	#)
	#print('debugging: emitting `dexterity` "value_changed"...')
	#stats.get('dexterity').value_changed.emit()
	#stats.get('dexterity').value_changed.emit()
	#print('... emission done')
	
## Direct access to stats, but typed, via 
@onready var stats: EntityStats:
	get():
		if _stats:
			return _stats.stats
		return null

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func _on_level_up(new_level: int, difference: int) -> void:
	stats.skill_points.max.value += difference
	emit_signal("level_up", new_level, difference)

func _on_level_down(new_level: int, difference: int) -> void:
	emit_signal("level_down", new_level, difference)

func can_allocate_node(tree_node: TreeNode):
	if stats.skill_points.value == 0:
		print('No skill point available')
		return false
	return super(tree_node)
	
func _pay_allocation_cost(tree_node: TreeNode):
	#print('paying 1 skill point... (current: %s / %s)' % [stats.skill_points.value, stats.skill_points._max.value])
	stats.skill_points.decrease(1)
	var x = 3
	
	#print('cost paid... (current: %s / %s)' % [stats.skill_points.value, stats.skill_points._max.value])

func _get_property_list() -> Array:
	var arr = []
	if _stats:
		arr.append_array(_stats._get_property_list())
	return arr

	
func _on_turn_start() -> void:
	print('huzzah the turn started')
