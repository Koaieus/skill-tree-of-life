class_name BladeTrajectory
extends RefCounted

## Per-step snapshot of particle positions. Pure data; replayable.

var sample_dt: float = 0.0
## samples[step_idx] = PackedVector2Array of particle positions
var samples: Array[PackedVector2Array] = []


func duration() -> float:
	return samples.size() * sample_dt


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
