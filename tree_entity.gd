@tool
extends Node
class_name TreeEntity

# Represents an `entity` that lives on a skill tree by owning 1 or more skills on it

@onready var core: TreeNode:
	get(): 
		return get_parent() as TreeNode

## StatManager ref
@onready var _stats: EntityStatsManager = $EntityStatsManager

## Direct access to stats, but typed
@onready var stats: EntityStats:
	get():
		if _stats:
			return _stats._stats
		return null

#@onready var tree: TreeGraph:
	#get(): return core.get_parent()
	
@export_color_no_alpha var color: Color = Color.BLUE


func _ready() -> void:
	Game.game_ready.connect(_on_game_ready, CONNECT_ONE_SHOT)
	
	print('TreeEntity `%s` READY' % [name])
	
func _on_game_ready() -> void:
	Game.turn_manager.ticked.connect(_on_game_tick)
	Game.turn_manager.turn_started.connect(_on_entity_turn_started)
	assert(core != null, 'TREE ENTITY: MISSING CORE')
	if core is TreeNode:
		print_debug('[ALLOCATION]: Allocating initial skill on game_ready for Entity<%s>' % name)
		core.allocate_to(self)

## Happens each game "tick"
func _on_game_tick() -> void:
	_stats.progress_initiative()

#func initialize() -> void:
	#if core:
		#core.allocate_to(self)
		#print('Allocated core')
	#else:
		#push_error('TreeEntity has no Core ')

func _to_string() -> String:
	return 'Tree Entity'
	

func can_allocate_node(tree_node: TreeNode) -> bool:
	if tree_node.has_owner():
		return false
	
	for neighbor: TreeNode in tree_node.neighbors:
		if neighbor.owned_by == self:
			return true
	print('Node has no connected neighbors')
	return false
	
func can_deallocate_node(tree_node: TreeNode) -> bool:
	if tree_node.owned_by != self:
		return false
	return true
	
func can_take_turn() -> bool:
	return true
	
func _pay_allocation_cost(tree_node: TreeNode):
	return


func allocate_skill_node(tree_node: TreeNode):
	prints('Allocating', tree_node, 'to', self)
	if not can_allocate_node(tree_node):
		print('Cannot allocate!')
		return false
	_pay_allocation_cost(tree_node)
	tree_node.allocate_to(self)
	
func deallocate_skill_node(tree_node: TreeNode):
	prints('Deallocating', tree_node, 'from', self)
	tree_node.owned_by = null
	return false

func _get_configuration_warnings() -> PackedStringArray:
	var warnings: Array[String] = []
	#if not core:
		#warnings.append('No core TreeNode set')
	if not _stats:
		warnings.append('No stats manager configured')
	return warnings

#func _on_game_ready():
	#initialize()


func _on_initiative_ready_changed(state: bool) -> void:
	if state:
		add_to_group('initiative-ready')
	else:
		remove_from_group('initiative-ready')

func start_turn() -> void:
	print('[TURN START] %s is starting their turn!' % [self])
	assert(core != null, 'TREE ENTITY: MISSING CORE')

	var xp: ExpStat = stats.experience
	assert(stats.experience._value != null, 'BORKED XP VALUE')
	stats.experience._value += stats.experience_gain.current_value


func _on_entity_turn_started(entity: TreeEntity) -> void:
	if entity != self:
		return
		
	start_turn()
