@tool
class_name ArrowEmitterPart
extends ArrowPart

## The shared half of the two particle parts: a `%Particles`
## [GPUParticles2D] child whose knobs are forwarded from exports here, so a look
## overrides them on its part instance without editable children. The part
## scene's own [member process_material] sub-resource is the ONE material every
## instance of that scene shares; per-arrow colour rides
## [member CanvasItem.modulate] at [member tier], so a volley stays batched
## (`.claude/rules/rendering-performance.md`).

@export var process_material: ParticleProcessMaterial:
	set(v):
		process_material = v
		_sync()
@export var texture: Texture2D:
	set(v):
		texture = v
		_sync()
@export_range(1, 256) var amount: int = 16:
	set(v):
		amount = v
		_sync()
## Seconds a particle lives — also this part's drain.
@export_range(0.05, 4.0, 0.01) var lifetime: float = 0.35:
	set(v):
		lifetime = v
		_sync()
@export var tier: Emissive.Tier = Emissive.Tier.LABEL:
	set(v):
		tier = v
		_sync()

var _tint: Color = Color(0, 0, 0, 0)


func _ready() -> void:
	_sync()


func paint(tint: Color, dud: bool, absorbed: bool) -> void:
	super.paint(tint, dud, absorbed)
	_tint = tint
	_sync()


func drain_seconds() -> float:
	return lifetime


func particles() -> GPUParticles2D:
	return get_node_or_null(^"%Particles") as GPUParticles2D


## Push the exports onto the emitter. `amount` is only written on a change —
## writing it restarts the emitter's buffer.
func _sync() -> void:
	var p := particles()
	if p == null:
		return
	if process_material != null:
		p.process_material = process_material
	if texture != null:
		p.texture = texture
	if p.amount != amount:
		p.amount = amount
	p.lifetime = lifetime
	p.modulate = ArrowPart.lit(_tint, tier)
	_sync_extra(p)


func _sync_extra(_p: GPUParticles2D) -> void:
	pass
