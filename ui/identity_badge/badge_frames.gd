@tool
class_name BadgeFrames
extends Resource

## The frame shape per [Identity.Kind] — the frame *is* the kind (a hexagon
## says "aspect") — plus the stroke and icon inset every badge shares.
## Analytic polygons, no art: `ui/identity_badge/badge_frames.tres`.

const PATH := "res://ui/identity_badge/badge_frames.tres"

@export var frames: Dictionary[Identity.Kind, BadgeFrame] = {}:
	set(value):
		frames = value
		emit_changed()
## Frame stroke width in pixels, at every badge size.
@export_range(0.5, 8.0, 0.5) var stroke_px: float = 2.0:
	set(value):
		stroke_px = value
		emit_changed()
## Margin around the icon/letter, as a fraction of the badge size per side.
@export_range(0.0, 0.45, 0.01) var icon_inset: float = 0.22:
	set(value):
		icon_inset = value
		emit_changed()

## Letter-fallback weight ([member FontVariation.variation_embolden]) so a
## thin body-font capital holds its own beside the frame stroke.
@export_range(0.0, 2.0, 0.05) var letter_embolden: float = 0.8:
	set(value):
		letter_embolden = value
		emit_changed()


static func shared() -> BadgeFrames:
	return load(PATH) as BadgeFrames


## The kind's frame; a hexagon when the kind has none authored.
func frame_for(kind: Identity.Kind) -> BadgeFrame:
	var frame: BadgeFrame = frames.get(kind)
	return frame if frame != null else BadgeFrame.new()
