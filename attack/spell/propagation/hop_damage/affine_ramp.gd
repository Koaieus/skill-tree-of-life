@tool
class_name AffineRamp
extends HopDamage

## Combines an additive and a multiplicative term per hop. Composition order
## is [code](d + increment) × factor[/code] (add-then-multiply) — matching
## Trailblazer's historical [code]accumulated = payload.damage +
## per_hop_increment[/code] then slam-multiply behaviour. See #351 fork 1.

@export var increment: float = 0.0
@export var factor: float = 1.0


func apply(damage: float, _hop_index: int) -> float:
	return (damage + increment) * factor


func get_description() -> String:
	var parts: PackedStringArray = []
	if not is_equal_approx(increment, 0.0):
		var ip := "+%d" if is_equal_approx(increment, roundf(increment)) else "+%.1f"
		parts.append(ip % increment)
	if not is_equal_approx(factor, 1.0):
		var fp := "×%d" if is_equal_approx(factor, roundf(factor)) else "×%.1f"
		parts.append(fp % factor)
	return " ".join(parts) + " per hop" if not parts.is_empty() else ""