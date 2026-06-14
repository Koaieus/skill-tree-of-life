class_name AttackVFX
extends Node2D

## Spawns per-attack VFX (tracers, hit-flashes, debris) and bridges resolver
## → on-screen feedback. Mounted as a sibling of [AttackHighlightOverlay] so
## tracers share its world coord space.
##
## Public coroutines `await` until the visual sequence completes — the
## resolver awaits them to keep damage timing in sync with the animation.

const _STAGGER_PER_TRACER: float = 0.06


## Spawn one tracer per [member AttackOutcome.hits]. Each tracer applies its
## own hit's damage on arrival, so floating numbers + hit flash stagger
## naturally. Returns when the last tracer arrives.
##
## NOTE: `pending` is an `Array[int]` rather than a bare `int` because GDScript
## lambdas capture locals by value — a closure mutating a bare int would not
## propagate back to the loop condition. The single-element array gives the
## closure something it can index into (by-reference for elements).
func play_ranged_volley(outcome: AttackOutcome) -> void:
	if outcome == null or outcome.hits.is_empty():
		return
	var pending: Array[int] = [outcome.hits.size()]
	for i in outcome.hits.size():
		var hit: DamageInstance = outcome.hits[i]
		var tracer := RangedTracer.new()
		add_child(tracer)
		var stagger: float = float(i) * _STAGGER_PER_TRACER
		# Tracer fires `arrived` when it lands; we apply damage + tally.
		tracer.arrived.connect(func() -> void:
			if hit.target != null:
				hit.target.take_damage(hit.amount, hit)
			pending[0] -= 1)
		tracer.launch(hit, stagger)
	while pending[0] > 0:
		await get_tree().process_frame
