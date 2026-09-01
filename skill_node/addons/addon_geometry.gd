@tool
class_name AddonGeometry
## Polygon builders shared by the plan-view structure addons (Bunker,
## Fortification). Statics only — never instanced.
##
## Lives here rather than on [SkillNodeVisual] (which already carries
## `polar_point` / `polar_steps`) because addons are NOT part of the
## `node_visuals_composite` family: they hang off the [SkillNode] directly and
## are driven by [method SkillNodeAddon.configure_visual], not by the
## composite's identity fan-out. Borrowing that base class's statics would
## imply a membership that doesn't exist.


## Filled polygon covering the annulus band [param inner_r]..[param outer_r]
## between angles [param from]..[param to] (radians, CCW). Both arcs are
## subdivided so the band stays smooth at the zoom levels a SkillNode is
## actually inspected at.
##
## [param outer_inset] shrinks the OUTER arc's angular span by that many
## radians at each end, chamfering the sector into a trapezoid — the "heavy
## bevelled plate" read Bunker wants. 0 gives a plain annular sector.
static func annular_sector(
	inner_r: float,
	outer_r: float,
	from: float,
	to: float,
	segments: int = 8,
	outer_inset: float = 0.0,
) -> PackedVector2Array:
	var out := PackedVector2Array()
	if segments < 1 or outer_r <= inner_r:
		return out
	# Inner arc, from -> to.
	for i in segments + 1:
		var t := float(i) / float(segments)
		out.append(Vector2.from_angle(lerpf(from, to, t)) * inner_r)
	# Outer arc back, to -> from, optionally pulled in at both ends.
	var o_from := from + outer_inset
	var o_to := to - outer_inset
	if o_to < o_from:
		# Inset swallowed the whole span — collapse to the midpoint so the
		# polygon degenerates to a triangle instead of folding inside out.
		var mid := (from + to) * 0.5
		o_from = mid
		o_to = mid
	for i in segments + 1:
		var t := float(i) / float(segments)
		out.append(Vector2.from_angle(lerpf(o_to, o_from, t)) * outer_r)
	return out


## [param poly] translated by [param offset]. Used for the drop-shadow pass
## every plan-view structure draws underneath itself: the shadow falls OPPOSITE
## the house light (see [LightingStyle.highlight_position]), which is what makes
## a flat top-down band read as raised off the board.
static func translated(poly: PackedVector2Array, offset: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(poly.size())
	for i in poly.size():
		out[i] = poly[i] + offset
	return out


## The one faked light direction the whole SkillNode-visuals family is lit by,
## in node-local xy. Read off a default-constructed [LightingStyle] rather than
## copied as a literal so a retune of that default carries here — addons sit
## outside the composite's light fan-out and have no injected style to read.
static func light_dir() -> Vector2:
	if _light_dir == Vector2.ZERO:
		_light_dir = LightingStyle.new().highlight_position.normalized()
	return _light_dir

static var _light_dir: Vector2 = Vector2.ZERO
