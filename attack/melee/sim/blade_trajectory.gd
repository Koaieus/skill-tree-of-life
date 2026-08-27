class_name BladeTrajectory
extends RefCounted

## Per-step snapshot of particle positions. Pure data; replayable.

var sample_dt: float = 0.0
## samples[k] = PackedVector2Array of particle positions at simulated time
## k*sample_dt. samples[0] is the pre-step pose (t=0) — [BladeSim.simulate]
## prepends it, so this array always means what it says (#633).
var samples: Array[PackedVector2Array] = []


## samples[0] is t=0 (the pre-step pose); samples[N-1] is the last simulated
## step, at t=(N-1)*sample_dt — so the span is N-1 steps, not N (#633).
func duration() -> float:
	if samples.is_empty():
		return 0.0
	return float(samples.size() - 1) * sample_dt


## Linear-interp positions at time t in [0, duration]. Clamps at the
## endpoints so playback past the end stays at the final pose.
func sample(t: float) -> PackedVector2Array:
	if samples.is_empty():
		return PackedVector2Array()
	if t <= 0.0:
		return samples[0]
	var dur := duration()
	if t >= dur:
		return samples[samples.size() - 1]
	var f := t / sample_dt
	var i0 := int(f)
	var i1 := mini(i0 + 1, samples.size() - 1)
	var frac := f - float(i0)
	var a := samples[i0]
	var b := samples[i1]
	var out := PackedVector2Array()
	out.resize(a.size())
	for j in a.size():
		out[j] = a[j].lerp(b[j], frac)
	return out
