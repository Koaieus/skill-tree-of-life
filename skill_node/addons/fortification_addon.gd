@tool
class_name FortificationAddon
extends SkillNodeAddon

## Mass, not hardness — the authored `node_health` bonus in
## fortification_addon.tscn means "more wall to chew through", so the visual is
## a WALL: a crenellated curtain ring sitting just outboard of the carrier's
## rim, merlons up top, embrasures between them. Straight off the tooltip
## icon's own metaphor (game-icons `heavenly-dog/defensive-wall`, see
## assets/icons/addons/mapping.txt) so the hover icon and the thing on the
## board read as the same object.
##
## [b]Plan view, outboard, never central.[/b] The disk's centre is the CARVE
## slot (docs/domain/skillnode-emblem.md) — a single-winner register that
## KEYSTONE/LOOT/SPELL all outrank. Defensive state that vanishes the moment a
## node also grants a spell is worse than no visual, so this contributes no
## [method SkillNodeAddon.get_emblem] and draws its own band instead, the way
## SpikeRing does. The addon it replaced pasted a side-view building sprite
## across the busiest pixels on the node; this is the fix for both faults.
##
## [b]Neutral chrome, ignoring tint and allocation[/b] — the `rimHolder`
## convention from `rim_bonuses.gd` ("always neutral chrome ... the stable
## basket pinning things down"). A wall is a wall regardless of who currently
## holds the node, and the two identity channels (entity tint on the disk,
## archetype tint on the rim) are already spoken for.
##
## Band budget: this occupies [1.14, 1.36] × radius. [BunkerAddon] deliberately
## hugs closer and overlaps the rim, at [0.90, 1.12], so a node carrying both
## reads as plating under a wall rather than one indistinct crust.

## Merlon count around the ring. Read as texture rather than as a number, so
## this is a look knob, not a magnitude channel — the authored bonus is fixed.
@export_range(6, 32, 1) var merlon_count: int = 12:
	set(value):
		merlon_count = value
		queue_redraw()
## Fraction of each angular step the merlon fills; the remainder is the
## embrasure gap. Above ~0.75 the crenellation stops reading as toothed.
@export_range(0.2, 0.9, 0.05) var merlon_fill: float = 0.50:
	set(value):
		merlon_fill = value
		queue_redraw()

## Band radii as fractions of the carrier radius: the curtain wall's footing,
## the walkway line merlons rise from, and the merlon tops.
## Sits outboard of [BunkerAddon]'s [0.90, 1.12] plating band, so a node
## carrying both reads as plating under a wall rather than one indistinct crust.
const _R_FOOT := 1.14
const _R_WALK := 1.24
const _R_TOP := 1.36

## How far the drop shadow is thrown, as a fraction of the carrier radius.
## Cast opposite [method AddonGeometry.light_dir], which is what makes a
## flat top-down band read as standing proud of the board.
const _SHADOW_THROW := 0.045

## Deliberately darker than the merlons AND than the carrier's own grey rim:
## a mid-grey curtain under mid-grey chrome teeth read as one dotted ring when
## zoomed out. The contrast between the two is what keeps it a wall.
const _CURTAIN_COLOR := Color(0.24, 0.24, 0.27)
## `rim_bonuses.gd`'s NEUTRAL_CHROME — the same stable-basket grey, on purpose.
const _MERLON_COLOR := Color(0.72, 0.74, 0.78)
const _SHADOW_COLOR := Color(0.02, 0.02, 0.03, 0.55)

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
	if _radius <= 0.0 or merlon_count <= 0:
		return

	var foot := _radius * _R_FOOT
	var walk := _radius * _R_WALK
	var top := _radius * _R_TOP
	var step := TAU / float(merlon_count)
	var half := step * merlon_fill * 0.5
	var shadow_offset := -AddonGeometry.light_dir() * (_radius * _SHADOW_THROW)

	# Curtain wall: one continuous band. `draw_arc` with a width, rather than a
	# 64-gon polygon, keeps this to a single primitive.
	var curtain_width := walk - foot
	var curtain_r := (foot + walk) * 0.5
	draw_arc(shadow_offset, curtain_r, 0.0, TAU, 48, _SHADOW_COLOR, curtain_width, true)
	draw_arc(Vector2.ZERO, curtain_r, 0.0, TAU, 48, _CURTAIN_COLOR, curtain_width, true)

	# Merlons: the teeth that make it read as fortification and not as one more
	# concentric ring. Shadow pass first, whole ring, then the lit pass — so a
	# merlon never casts onto the merlon drawn after it.
	var merlons: Array[PackedVector2Array] = []
	for i in merlon_count:
		var mid := i * step
		merlons.append(AddonGeometry.annular_sector(walk, top, mid - half, mid + half, 3))
	for poly in merlons:
		draw_colored_polygon(AddonGeometry.translated(poly, shadow_offset), _SHADOW_COLOR)
	for poly in merlons:
		draw_colored_polygon(poly, _MERLON_COLOR)
