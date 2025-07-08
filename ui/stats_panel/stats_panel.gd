extends Control
class_name StatsPanel

## Player whose stats to display
@export var player: Player:
	set = set_player

## UI nodes
@onready var _name_label: Label = %NameLabel
@onready var _description_label: Label = %DescriptionLabel
@onready var _stats_list: VBoxContainer = %StatsList

func _ready() -> void:
	Game.main_player_selected.connect(_on_main_player_selected)
	Game.game_ready.connect(_on_game_ready)
	if Game.player:
		set_player(Game.player)

func set_player(p: Player) -> void:
	player = p
	_rebuild_panel()

func _on_main_player_selected(p: Player) -> void:
	set_player(p)

func _on_game_ready() -> void:
	if not player and Game.main_player:
		set_player(Game.main_player)

## Clear existing rows
func _clear_rows() -> void:
	for child in _stats_list.get_children():
		_stats_list.remove_child(child)
		child.queue_free()

## Rebuild the stats UI
func _rebuild_panel() -> void:
	_clear_rows()
	if not player:
		_name_label.text = "No Main Player configured"
		_description_label.hide()
		return
	_name_label.text = player.player_name

	var stats_mgr: StatsManager = player._stats
	if not stats_mgr:
		return

	for stat in stats_mgr.stats.get_stats(true):
		## Use StatBind for live updates
		#var bind = StatBind.new(stat)
		# Choose widget from metadata or defaults
		var meta: StatMetaData = StatMetaDataRepository.get_for_stat(stat)
		var scene: PackedScene = meta.widget_overrides.get(
			meta.display_type, 
			StatUIConfig.widget_defaults.get(meta.display_type)
		)
		var widget = scene.instantiate()
		#if widget.has_method("set_stat_bind"):
			#widget.set_stat_bind(bind)
		if widget.has_method("set_stat_owner"):
			widget.set_stat_owner(player)
		_stats_list.add_child(widget)



#extends Control
#class_name StatsPanel
#
#@export var player: Player
#
## Called when the node enters the scene tree for the first time.
#func _ready() -> void:
	#Game.main_player_selected.connect(_on_main_player_selected)
	#Game.game_ready.connect(_on_game_ready)
	##Game.player_stats_changed.connect(compute)
#
#func clear_rows() -> void:
	#for c in %StatsList.get_children():
		#c.queue_free()
#
#func initialize():
	#print_debug("[STATS PANEL]: initializing")
	#
	#clear_rows()
	#if player:
		#%NameLabel.text = player.player_name
	#else:
		#%NameLabel.text = "No Main Player configured"
		#return
	#
	#if not player._stats:
		#return
	#var stat_manager: StatsManager = player._stats
	#for stat in stat_manager.stats.get_stats(true):
		#var row := stat._generate_row(stat_manager)
		#%StatsList.add_child(row)
#
#func _on_main_player_selected(player: Player): 
	#self.player = player
#
#func _on_game_ready() -> void:
	#initialize()
