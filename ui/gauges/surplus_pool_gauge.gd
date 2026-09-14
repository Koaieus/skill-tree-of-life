@tool
class_name SurplusPoolGauge
extends PoolGauge

## A [PoolGauge] that also renders a [SurplusPoolStat]'s out-of-cap surplus bin
## (#152) as trailing battery cells past the cap, in [member surplus_color]. The
## base gauge is untouched (AP still uses a plain PoolGauge); this subclass just
## drives the shader's `surplus` / `surplus_color` uniforms.

## The MODEL surplus; [member shown_surplus] is what the shader draws.
@export var surplus: float = 0.0:
	set(v):
		surplus = v
		# The surplus bin is spent FIRST (SurplusPoolStat's burn-it-or-lose-it
		# contract), so for MP this — not `current` — is the bin a Movement point
		# usually leaves from, and the cell that has to sweep out. It is also
		# the bin that refills at turn end, hence it sweeps back in too. Its
		# cells are already strip cells, so the distance needs no conversion.
		# The shader keeps a partially-receded surplus cell's slot until it is
		# gone, so the strip never re-lays out under the sweep (#882).
		_spark.sweep(self, ^"shown_surplus", v, v - shown_surplus,
				cell_step_time, spark_time, EDGE_SURPLUS)

## The surplus the shader is drawing right now — lags [member surplus] while a
## trailing cell sweeps. [GaugeSpark] tweens it.
var shown_surplus: float = 0.0:
	set(v):
		shown_surplus = v
		_push(&"surplus", v)

@export var surplus_color: Color = Color(0.9084, 0.6684, 0.3042, 0.85):
	set(v):
		surplus_color = v
		_push(&"surplus_color", v)


func _ready() -> void:
	# A surplus pool is always a battery — even at cap 0 (Pacifist), where its
	# entire budget is the out-of-cap surplus. Set before super() so _push_all
	# carries it. Without it, cell_count 0 would route to the smooth branch that
	# never draws surplus.
	force_cells = true
	super()
	# _push_all() on the base doesn't know about these; push them after the
	# base wiring (and material duplicate) is done.
	_push(&"surplus", shown_surplus)
	_push(&"surplus_color", surplus_color)
