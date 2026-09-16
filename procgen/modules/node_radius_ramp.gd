@tool
class_name NodeRadiusRamp
extends Resource

## Budget → `base_radius` ramp (#783). A node's modifier budget is invisible
## until hovered; radius is the cheapest legibility channel there is, so a
## generated node's size is a documented function of its rolled budget.
##
## Radius formula:
##   budget ≤ knee_budget:  min_radius + px_per_budget · (budget − 1)
##   budget > knee_budget:  knee_radius + (cap − knee_radius)
##                          · (1 − exp(−px_per_budget · (budget − knee_budget)
##                                     / (cap − knee_radius)))
## where `knee_radius = min_radius + px_per_budget · (knee_budget − 1)`. The
## soft tail is continuous and slope-1 at the knee and approaches `cap` but
## never reaches it — an anomalous rim node stays legibly fatter than a plain
## rim node instead of clamping into it.
##
## Assigned to [member GraphProcgenTopology.node_radius_ramp]; unset there
## means every node gets the uniform [member GraphProcgenTopology.node_radius].
## Spacing sizes for [method max_radius] so no ramped node can overlap.

## Radius at budget 1. Below 32 (the golden default) on purpose — the band is
## −4..+12 around 32, more growth on the + side.
@export_range(1.0, 64.0, 0.5) var min_radius: float = 28.0
## Linear growth per budget unit up to the knee.
@export_range(0.0, 8.0, 0.25) var px_per_budget: float = 1.0
## Budget where linear growth stops and the soft tail begins.
@export_range(1, 64, 1) var knee_budget: int = 16
## Asymptote of the soft tail; never reached. Spacing sizes for this.
@export_range(1.0, 96.0, 0.5) var cap: float = 50.0


## Radius for a rolled budget ≥ 1. Callers decide what a budget of 0 means
## ([GraphProcgenTopology] maps it to the uniform default).
func radius_for(budget: int) -> float:
	var linear := min_radius + px_per_budget * float(budget - 1)
	if budget <= knee_budget:
		return linear
	var knee_radius := min_radius + px_per_budget * float(knee_budget - 1)
	var headroom := cap - knee_radius
	if headroom <= 0.0:
		# A cap tuned at or below the knee has no tail to bend into — clamp
		# instead of handing the collision shape a NaN from a ≤ 0 divisor.
		return minf(linear, cap)
	var past_knee := px_per_budget * float(budget - knee_budget)
	return knee_radius + headroom * (1.0 - exp(-past_knee / headroom))


## Largest radius the ramp can ever hand out — the asymptote.
func max_radius() -> float:
	return cap
