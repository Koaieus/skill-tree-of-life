class_name InfusionExchange
extends RefCounted

## The exchange line one infusion socket reads: `spent → +gained <rate>` —
## `40 → +80 ×2`, `40 → +20 ½`, `40 → +40` at rate 1 — plus `· n wasted` when
## the floor drops points, or `refused` at rate 0. Gained is the same
## `floor(points × rate)` [method Infusion.affinity_of] folds, so the line and
## the cast cannot disagree. Pure statics.


## [param points] of [param aspect_id] spent on [param spell], as one line.
static func line(spell: SpellDef, aspect_id: StringName, points: int) -> String:
	var rate := Infusion.rate_of(spell, aspect_id)
	if rate <= 0.0:
		return "refused"
	var gained := floori(points * rate)
	var out := "%d → +%d" % [points, gained]
	var suffix := rate_text(rate)
	if not suffix.is_empty():
		out += " " + suffix
	var wasted := wasted_of(rate, points)
	if wasted > 0:
		out += " · %d wasted" % wasted
	return out


## Points of [param points] the floor discards at [param rate]: how many could
## be taken back without lowering `floor(points × rate)`.
static func wasted_of(rate: float, points: int) -> int:
	var gained := floori(points * rate)
	var wasted := 0
	while wasted < points and floori((points - wasted - 1) * rate) == gained:
		wasted += 1
	return wasted


## The rate suffix: empty at 1, `½` at one half, `×<rate>` otherwise.
static func rate_text(rate: float) -> String:
	if is_equal_approx(rate, 1.0):
		return ""
	if is_equal_approx(rate, 0.5):
		return "½"
	return "×%s" % NumFmt.num(rate)
