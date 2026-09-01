@tool
class_name BunkerAddon
extends SkillNodeAddon

## Hardness, not mass — the authored `armor` bonus and `min_damage_taken` floor
## cut in bunker_addon.tscn mean "shots glance off", so the visual is PLATING:
## four heavy chamfered casemate plates hugging the carrier's rim, each with a
## dark firing slit. The tooltip icon (game-icons `quoting/bunker-assault`, see
## assets/icons/addons/mapping.txt) is a flat slab roof over a slit with fire
## converging on it; this is that object seen from above.
##
## [b]Read it against [FortificationAddon][/b] — the pair has to be
## distinguishable at a glance or the two defensive addons are one blur:
##
## [codeblock]
##            Bunker                    Fortification
## count      4, discrete               12, continuous
## band       [0.90, 1.12] r (over rim)  [1.14, 1.36] r (outboard)
## profile    thick, chamfered, faceted thin, toothed
## shading    per-plate, faceted        flat chrome + drop shadow
## value      dark body, bright bevel   bright teeth, dark curtain
## [/codeblock]
##
## [b]Deliberately non-emissive.[/b] Every colour below stays under 1.0, so
## this never enters the bloom pass (.claude/rules/hdr-color.md). Dull steel
## that does NOT glow is the statement — on a board where payload and identity
## announce themselves with light, armour is the thing that absorbs it.
##
## No [method SkillNodeAddon.get_emblem] contribution, for the same reason
## [FortificationAddon] makes none: CARVE is single-winner and outranked by
## SPELL/LOOT/KEYSTONE, so routing defensive state through it would make a
## bunker invisible on exactly the high-value nodes worth bunkering.

## Plate count. Four reads as deliberate armour; more turns the ring
## continuous and steals Fortification's silhouette.
@export_range(3, 8, 1) var plate_count: int = 4:
	set(value):
		plate_count = value
		queue_redraw()
## Fraction of each angular step a plate spans; the remainder is the seam
## between plates. The seams are what keep it faceted rather than annular.
@export_range(0.3, 0.95, 0.05) var plate_fill: float = 0.72:
	set(value):
		plate_fill = value
		queue_redraw()

## Band radii as fractions of the carrier radius. Starts INSIDE the carrier's
## own rim: plating is bolted over the structure, not parked beside it, and the
## overlap is what stops a dark steel band from disappearing. The first cut sat
## at [1.00, 1.10] — a 3px band of dark steel abutting the node's own dark rim,
## which rendered as very nearly nothing. Don't narrow it back.
const _R_IN := 0.90
const _R_OUT := 1.12
## Where the firing slit sits within the plate, and how thick it is.
const _R_SLIT := 1.055
const _SLIT_WIDTH := 2.0
## Bright bevel drawn along each plate's outer arc. A single lit edge is what
## sells "thick and angled" at the zoom where the facet shading has flattened
## into one average grey.
const _BEVEL_WIDTH := 2.2

## Chamfer taken off each end of a plate's OUTER arc, as a fraction of the
## plate's own angular span. This is the whole bevelled-plate read.
const _CHAMFER := 0.22
## Fraction of the plate span the slit stops short of at each end.
const _SLIT_INSET := 0.34

const _SHADOW_THROW := 0.05
const _SHADOW_COLOR := Color(0.02, 0.02, 0.03, 0.6)
## Steel, shaded between these two by the plate's facing against the house
## light. Both well under 1.0 — see the non-emissive note above.
## DARK COOL steel under a bright cool bevel — the plate body carries almost no
## value, the lit edge carries the read. That split is what lets one band work
## against both rim states: `rim_ring.gd` blends its bronze BASE_COLOR toward
## `archetype_tint` when the node is ALLOCATED and dims to silver when it isn't,
## and this band sits directly on top of it. A warm mid-tone plate (the previous
## cut) separated cleanly from the dim silver rim and then disappeared into the
## bronze one — and since procgen and players both put addons on owned nodes,
## allocated is the primary case, not the edge. Dark-cool-on-warm-bright works
## on bronze; the bevel is what keeps it off the dark rim.
##
## It also stays clear of [FortificationAddon]'s bright cool chrome by VALUE
## rather than hue: dark plates over the rim, bright teeth outboard of it.
## Every value is still well under 1.0 — see the non-emissive note above, which
## this cut serves better than the bright one did.
const _STEEL_DARK := Color(0.13, 0.14, 0.18)
const _STEEL_LIT := Color(0.40, 0.44, 0.53)
const _BEVEL_DARK := Color(0.40, 0.45, 0.55)
const _BEVEL_LIT := Color(0.74, 0.81, 0.92)
const _SLIT_COLOR := Color(0.03, 0.03, 0.05)

var _radius: float = 32.0


func _ready() -> void:
	super._ready()
	if carrier != null:
		_radius = carrier.radius
	queue_redraw()


func configure_visual(r: float) -> void:
	_radius = r
	queue_redraw()


func _draw() -> void:
	if _radius <= 0.0 or plate_count <= 0:
		return

	var r_in := _radius * _R_IN
	var r_out := _radius * _R_OUT
	var r_slit := _radius * _R_SLIT
	var step := TAU / float(plate_count)
	var span := step * plate_fill
	var half := span * 0.5
	var light := AddonGeometry.light_dir()
	var shadow_offset := -light * (_radius * _SHADOW_THROW)

	# Offset by half a step so plates sit on the diagonals rather than on the
	# cardinals — nothing else on the node keys off the diagonals, and the
	# health bars own straight-up.
	var bearing_offset := step * 0.5

	var plates: Array[PackedVector2Array] = []
	var bearings := PackedFloat32Array()
	for i in plate_count:
		var mid := i * step + bearing_offset
		bearings.append(mid)
		plates.append(
			AddonGeometry.annular_sector(r_in, r_out, mid - half, mid + half, 4, span * _CHAMFER)
		)

	for poly in plates:
		draw_colored_polygon(AddonGeometry.translated(poly, shadow_offset), _SHADOW_COLOR)

	for i in plates.size():
		# Faceted shading: a plate facing the light is bright steel, one facing
		# away is dark. Lambert on the plate's outward normal, remapped off zero
		# so the unlit side stays legible rather than going to black.
		var facing := Vector2.from_angle(bearings[i]).dot(light)
		var lit := clampf(facing * 0.5 + 0.5, 0.0, 1.0)
		draw_colored_polygon(plates[i], _STEEL_DARK.lerp(_STEEL_LIT, lit))
		# Bevel along the outer arc, inset by the same chamfer the plate is cut
		# with so it stops where the plate's corner does.
		var bevel_half := half - span * _CHAMFER
		draw_arc(
			Vector2.ZERO,
			r_out - _BEVEL_WIDTH * 0.5,
			bearings[i] - bevel_half,
			bearings[i] + bevel_half,
			8,
			_BEVEL_DARK.lerp(_BEVEL_LIT, lit),
			_BEVEL_WIDTH,
			true
		)

	# Firing slits, drawn last so they cut through the plating.
	var slit_half := half * (1.0 - _SLIT_INSET)
	for bearing in bearings:
		draw_arc(
			Vector2.ZERO,
			r_slit,
			bearing - slit_half,
			bearing + slit_half,
			8,
			_SLIT_COLOR,
			_SLIT_WIDTH,
			true
		)
