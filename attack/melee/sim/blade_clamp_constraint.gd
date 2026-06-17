class_name BladeClampConstraint
extends BladeConstraint

## Constrains `arm`'s angle around `pivot` to [min_angle, max_angle].
## Stub for the future SkillNode-addon hook (a "hinge" node injects one
## of these when used in a blade). Distance to pivot is preserved.

var pivot: int
var arm: int
var min_angle: float
var max_angle: float

func _init(pivot_: int, arm_: int, min_angle_: float, max_angle_: float) -> void:
	pivot = pivot_
	arm = arm_
	min_angle = min_angle_
	max_angle = max_angle_


func project(
		positions: PackedVector2Array,
		inv_masses: PackedFloat32Array) -> void:
	var rel := positions[arm] - positions[pivot]
	var dist := rel.length()
	if dist < 1e-6:
		return
	var angle := rel.angle()
	var clamped := clampf(angle, min_angle, max_angle)
	if is_equal_approx(clamped, angle):
		return
	var target_pos := positions[pivot] + Vector2.from_angle(clamped) * dist
	var wa := inv_masses[arm]
	var wp := inv_masses[pivot]
	var w := wa + wp
	if w == 0.0:
		return
	var corr := target_pos - positions[arm]
	positions[arm] += corr * (wa / w)
	positions[pivot] -= corr * (wp / w)
