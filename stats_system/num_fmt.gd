class_name NumFmt
extends RefCounted

## The one display rule for a game number. It never rounds a value: game
## values are already floored once at their source (INT coerce, HP doors), so
## a display that rounds again would be a second rounding step. It only snaps
## float noise — a value approximately whole prints as that whole (`roundi`,
## never `int()`, which truncates 2.9999999 to 2). Anything else prints with
## [param decimals] places, trailing zeros and a bare point trimmed.
static func num(v: float, decimals: int = 2) -> String:
	if is_equal_approx(v, roundf(v)):
		return str(roundi(v))
	var s := String.num(v, decimals)
	if s.contains("."):
		s = s.rstrip("0").trim_suffix(".")
	return s
