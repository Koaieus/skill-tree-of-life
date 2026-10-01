@tool
class_name TargetGhost
extends TargetReticle

## A target candidate: the reticle's arms alone, still and dim. The overlay
## pushes the role's tint; this marker greys it by [member desaturation]
## before the tier applies — saturation, not glow, so the tier stays named.

## 0 = the pushed tint as-is, 1 = its luminance grey.
@export_range(0.0, 1.0, 0.01) var desaturation: float = 0.6:
	set(value):
		desaturation = value
		_update_modulate()


func _update_modulate() -> void:
	var grey := tint.get_luminance()
	var muted := tint.lerp(Color(grey, grey, grey, tint.a), desaturation)
	modulate = Emissive.at(muted, Emissive.stops(tier))
