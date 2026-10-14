class_name InfusionExchange
extends RefCounted

## The exchange line one infusion socket reads: `spent → +gained <rate>` —
## `40 → +80 ×2`, `40 → +20 ½`, `40 → +40` at 1:1 — plus `· n wasted` when
## the floor drops points, or `refused` at affinity or ingest 0. The rate is the
## concept's affinity × the spell's ingest rate ([method Infusion.ratio_of]) and
## gained is the same [method Infusion.gained] [method Infusion.load_of] folds,
## so the line and the cast cannot disagree. Pure statics.


## [param points] of [param aspect_id] spent on [param spell], as one line.
static func line(spell: SpellDef, aspect_id: StringName, points: int) -> String:
	var ratio := Infusion.ratio_of(spell, aspect_id)
	if ratio.x <= 0:
		return "refused"
	var gained := Infusion.gained(spell, aspect_id, points)
	var out := "%d → +%d" % [points, gained]
	var suffix := rate_text(ratio)
	if not suffix.is_empty():
		out += " " + suffix
	var wasted := wasted_of(ratio, points)
	if wasted > 0:
		out += " · %d wasted" % wasted
	return out


## Points of [param points] the floor discards at `gain:cost` [param ratio]:
## how many could be taken back without lowering `floor(points × gain / cost)`.
@warning_ignore("integer_division")
static func wasted_of(ratio: Vector2i, points: int) -> int:
	if ratio.x <= 0 or points <= 0:
		return 0
	var gained := (points * ratio.x) / ratio.y
	# The fewest points that still buy `gained`: ceil(gained × cost / gain).
	var needed := (gained * ratio.y + ratio.x - 1) / ratio.x
	return points - needed


## The rate suffix: empty at 1:1, `½` at 1:2, `×<n>` at a whole multiple,
## `gain:cost` otherwise.
static func rate_text(ratio: Vector2i) -> String:
	var g := ratio.x
	var c := ratio.y
	if g == c:
		return ""
	if g * 2 == c:
		return "½"
	if g % c == 0:
		@warning_ignore("integer_division")
		return "×%d" % (g / c)
	return "%d:%d" % [g, c]
