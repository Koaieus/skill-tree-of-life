extends RefCounted
class_name Easing

## Shared cubic easing curves. Was pasted byte-identically as `_ease_out` in
## 11 `ui/` files (#1005) — one copy here, everyone calls through.

static func out_cubic(t: float) -> float:
	var inv := 1.0 - clampf(t, 0.0, 1.0)
	return 1.0 - inv * inv * inv


static func in_cubic(t: float) -> float:
	var c := clampf(t, 0.0, 1.0)
	return c * c * c


static func in_out_cubic(t: float) -> float:
	var c := clampf(t, 0.0, 1.0)
	if c < 0.5:
		return 4.0 * c * c * c
	var f := -2.0 * c + 2.0
	return 1.0 - (f * f * f) / 2.0
