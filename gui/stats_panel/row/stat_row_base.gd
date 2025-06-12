extends HBoxContainer
class_name StatRowBase

@export var stat_manager: StatsManager:
	get():
		return stat_manager
	set(value):
		if stat_manager == value:
			return
		stat_manager = value
		initialize_binding()
		notify_property_list_changed()

@export var stat_key: GDScript:
	get():
		return stat_key
	set(value):
		if stat_key == value:
			return
		stat_key = value
		initialize_binding()
		notify_property_list_changed()


@export var stat: Stat:
	get():
		return stat
	set(value):
		if stat == value:
			return
		if stat:
			stat.value_changed.disconnect(_on_stat_value_changed)
		stat = value
		if stat:
			_on_stat_value_changed()
			stat.value_changed.connect(_on_stat_value_changed)
		notify_property_list_changed()

@onready var stat_bind: StatBind = %StatBind

@export var text_display: String:
	get(): return text_display
	set(value):
		if text_display != value:
			#print('setting row text to "%s"' % value)
			text_display = value
			$LabelText.text = text_display


## Handler to process stat value change
func _on_stat_value_changed():
	#print('[STAT ROW]: value_changed signal received from stat %s' % stat)
	if not stat:
		return
	compute()

## Update this row according to current stat properties
func compute() -> void:
	pass
	
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	initialize_binding()
	
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
	
func initialize_binding() -> void:
	if not stat_manager or not stat_key or not stat_bind:
		return
	if stat_manager is not StatsManager:
		push_error('ERROR: %s is not a StatsManager' % stat_manager)
	
	#print('Initializing binding of %s to %s' % [stat_key.get_global_name, stat_manager])
	stat_bind.stats_manager = stat_manager
	stat_bind.stat_key = stat_key
	#stat_bind.bind()
	#print('Current value: %s' % stat_manager.get_stat(stat_key).value)
