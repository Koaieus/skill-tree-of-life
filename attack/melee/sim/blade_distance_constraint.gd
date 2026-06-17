class_name BladeDistanceConstraint
extends BladeConstraint

## Standard PBD distance constraint — the pin-joint replacement. With
## compliance = 0 it's perfectly rigid (one iteration solves it
## exactly for an isolated pair); larger compliance softens the
## response so the constraint behaves like a stiff spring.

var a: int
var b: int
var rest: float
var compliance: float

func _init(a_: int, b_: int, rest_: float, compliance_: float = 0.0) -> void:
	a = a_
	b = b_
	rest = rest_
	compliance = compliance_


func project(
		positions: PackedVector2Array,
		inv_masses: PackedFloat32Array) -> void:
	var pa := positions[a]
	var pb := positions[b]
	var delta := pb - pa
	var dist := delta.length()
	if dist < 1e-6:
		return
	var wa := inv_masses[a]
	var wb := inv_masses[b]
	var w := wa + wb
	if w == 0.0:
		return
	# stiffness coefficient (XPBD-flavoured, not exact): compliance scales
	# the correction down so the constraint takes more iterations to settle.
	var k := 1.0 / (1.0 + compliance)
	var diff := (dist - rest) / dist
	var corr := delta * diff * k
	positions[a] = pa + corr * (wa / w)
	positions[b] = pb - corr * (wb / w)
