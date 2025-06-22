extends IntStat
class_name ExperienceGainStat

#static func name:
	#return "Experience per turn"
	#
#static func abbreviation():
	#return "EXP/turn"
	#
#static func description():
	#return "Experience points per turn."

#func _ready():
	#Game.turn_started.connect(_on_turn_start)
	#
#func _on_turn_start() -> void:
	#print('huzzah the turn started')
