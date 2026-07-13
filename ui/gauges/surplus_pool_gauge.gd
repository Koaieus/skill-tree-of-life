@tool
class_name SurplusPoolGauge
extends PoolGauge

## A [PoolGauge] that also renders a [SurplusPoolStat]'s out-of-cap surplus bin
## (#152) as trailing battery cells past the cap, in [member surplus_color]. The
## base gauge is untouched (AP still uses a plain PoolGauge); this subclass just
## drives the shader's `surplus` / `surplus_color` uniforms.

@export var surplus: float = 0.0:
	set(v):
		surplus = v
		_push(&"surplus", v)

@export var surplus_color: Color = Color(0.9084, 0.6684, 0.3042, 0.85):
	set(v):
		surplus_color = v
		_push(&"surplus_color", v)


func _ready() -> void:
	super()
	# _push_all() on the base doesn't know about these; push them after the
	# base wiring (and material duplicate) is done.
	_push(&"surplus", surplus)
	_push(&"surplus_color", surplus_color)
