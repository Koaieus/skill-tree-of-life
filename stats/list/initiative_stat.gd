extends IntStat
class_name InitiativeStat

signal initiative_ready(state: bool)

const MAX_PROGRESS: int = 100
@export var progress: int = 0:
	get():
		return progress
	set(value):
		progress = value
		notify_property_list_changed()
		_is_ready = progress >= MAX_PROGRESS
		
var _is_ready: bool = false:
	set(value):
		if value != _is_ready:
			_is_ready = value
			initiative_ready.emit(value)
			

#class InitiativeProgressStat extends IntStat:
	#pass
