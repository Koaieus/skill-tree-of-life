@tool
class_name ShadingStyle
extends Resource

## Shared per-node shading inputs for the SkillNode-visuals height-field+light
## model (milestone #16). Bundled as a Resource — the same pattern as
## [GlowStyle] — so InnerDisk / WeldSymbol / RimRing each hold ONE object and
## connect ONCE to [signal Resource.changed], instead of the composite
## imperatively mirroring five separate properties onto each child in
## `_sync_shared()` (the exact drift risk .claude/rules/skill-node-visuals.md
## warns about). Adding a new shaded consumer is then one `child.shading = …`
## line, and the single source object makes drift impossible.
##
## IMPORTANT (per GlowStyle): a custom Resource does NOT auto-emit `changed`
## when a field is assigned, so every setter below calls `emit_changed()`.
##
## `highlight_position` is the faked main-light direction. It lives here for now
## because the composite forwards one value to the disk and its rim; a later
## global-uniform light framework can take ownership of it without changing the
## consumers.

## Entity/archetype tint — only visible when [member allocated]; unallocated
## nodes stay neutral-dark regardless (see inner_disk.gdshader).
@export var tint_color: Color = Color(0.291, 0.5892, 1.0):
	set(value):
		tint_color = value
		emit_changed()

## Saturation of the metal/disk tint (0 = grey, 1 = fully saturated).
@export_range(0.0, 1.0, 0.01) var tint_mix: float = 0.6:
	set(value):
		tint_mix = value
		emit_changed()

## Owned/lit (true) vs neutral-dark (false).
@export var allocated: bool = false:
	set(value):
		allocated = value
		emit_changed()

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
