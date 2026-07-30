@tool
class_name LightingStyle
extends Resource

## The one faked light every SkillNode-visuals component is lit by (milestone
## #16). Bundled as a Resource — the same pattern as [GlowStyle] — so InnerDisk
## (carve glyph included) and every RimRing hold ONE object and connect ONCE to
## [signal Resource.changed], and the disk and its rim can't drift onto two
## different light directions.
##
## This carries the LIGHT, not identity. Identity colors travel the other
## channel: [member SkillNodeVisual.entity_tint] / [member
## SkillNodeVisual.archetype_tint], loop-set by the composite. Two data-flows,
## two mechanisms, on purpose — a light is one shared thing many surfaces
## sample; an identity color is a per-component choice of which provided value
## to read.
##
## IMPORTANT (per GlowStyle): a custom Resource does NOT auto-emit `changed`
## when a field is assigned, so every setter below calls `emit_changed()`.
##
## `highlight_position` lives here for now because the composite forwards one
## value to the disk and its rim; a later global-uniform light framework can
## take ownership of it without changing the consumers.

## Faked main-light direction in normalized (-1..1) disk space. Drives the
## disk specular and the rim bevel sheen from ONE value.
@export var highlight_position: Vector2 = Vector2(-0.35, -0.35):
	set(value):
		highlight_position = value
		emit_changed()

@export_range(0.0, 1.0, 0.01) var highlight_intensity: float = 0.85:
	set(value):
		highlight_intensity = value
		emit_changed()
