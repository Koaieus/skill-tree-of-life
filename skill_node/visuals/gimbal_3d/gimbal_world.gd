class_name GimbalWorld
extends Node2D
## Stub — see the spike test; filled in next commit.

const ZLayers := preload("res://ui/z_layers.gd")

## Camera distance above the ring plane, in world px (= 3D units).
const CAMERA_Z := 1000.0


static func map_view(_world_to_pixels: Transform2D, _pixel_size: Vector2) -> Dictionary:
	return {}
