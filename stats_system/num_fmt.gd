class_name NumFmt
extends RefCounted

## The one display rule for a game number. STUB — the old copies' shape.
static func num(v: float) -> String:
	if is_equal_approx(v, roundf(v)):
		return str(int(v))
	return "%.1f" % v
