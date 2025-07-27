@tool 
extends TextureProgressBar
class_name BarWidget

const ROWS: int = 8

var region_size := Vector2(32, 32)
var bar_rect := Rect2(7, 7, 18, 18)

@export_range(-1, ROWS) var kind: int = 0:
	set(v):
		if v>=ROWS:
			v = 0
		elif v<0:
			v = ROWS -1
		kind = v
		
		print('!!')
		update_regions()
		notify_property_list_changed()

var block_offset: Vector2:
	get():
		var region: Rect2 = texture_under.get_region()
		return Vector2(0, region.size[1])

func update_regions():
	#texture_under.set_region(Rect2(Vector2(224, kind * region_size[0]), region_size))
	#texture_under.notify_property_list_changed()
	#print('Region now:', texture_under.get_region())
	#texture_under.margin.position[1] = - region_size[1] * kind
	pass
		
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	update_regions()

## Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta: float) -> void:
	#pass


func _on_property_list_changed() -> void:
	update_regions()
