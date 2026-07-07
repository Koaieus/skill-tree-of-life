@tool
extends SkillNodeVisual
## Orchestration scene composing all SkillNode-visual components (#126,
## milestone #16). Children are scene-composed in
## node_visuals_composite.tscn (not instantiated in code) — this script
## forwards the knobs that must stay in sync *across* children (tint_color,
## allocated, the rim radii, stake cap/alloc) and computes the node's
## current actual outer edge so [RuneRing] auto-clears grown stake rings.
## Z-order in the .tscn already matches the final draw order: disk -> weld
## -> rim ring(s) -> rim bonuses -> halos -> rune ring.
##
## This is also the ONLY layer that knows both InnerDisk and RimRing exist:
## [member geom_inner_r] is handed to both, so the disk's edge and the
## ring's floor line up — RimRing itself carries no disk knowledge at all.
##
## Stake/cap depth: only approach A (ring stacking / rim_growth) is wired.
## Segmented dial (rimSegments) and well/groove (rimWell) are follow-up —
## rim_ring only draws full rings today, no wedge/arc-span support yet.

const MAX_STAKE_CAP := 4

## The disk is sized this many px LARGER than geom_inner_r so its faded outer
## edge tucks UNDER the innermost rim (drawn above it), instead of leaving a ~1px
## transparent seam where the disk has faded out but the rim's inner AA hasn't
## filled in yet — the dark background was peeking through that ring. The rim
## hides the overlap, so the disk still reads as ending at geom_inner_r.
const DISK_RIM_OVERLAP := 1.5

## Entity/archetype tint — see inner_disk.gd. Drives InnerDisk, WeldSymbol,
## and (desaturated per stake index) the RimRing band coloring. RimBonuses
## still runs on its own `hue` float (unconverted, out of this pass's
## scope); we derive it from tint_color.h rather than carrying two
## independent color exports.
@export var tint_color: Color = Color(0.291, 0.5892, 1.0):
	set(value):
		tint_color = value
		_sync_shared()
@export var allocated: bool = false:
	set(value):
		allocated = value
		_sync_shared()

## Pit/disc edge — shared by InnerDisk.disk_radius, WeldSymbol.disk_radius,
## and RimRing.inner_radius (base ring only; stacked rings grow outward
## from here, see _sync_stake).
@export_range(0.0, 128.0, 0.5) var geom_inner_r: float = 24.0:
	set(value):
		geom_inner_r = value
		_sync_stake()
## Interior bevel control point — see rim_ring.gd.
@export_range(0.0, 128.0, 0.5) var geom_crest_r: float = 28.0:
	set(value):
		geom_crest_r = value
		_sync_stake()
@export_range(0.0, 128.0, 0.5) var geom_outer_r: float = 32.0:
	set(value):
		geom_outer_r = value
		_sync_stake()

## Ring-stacking stake/cap depth (approach A). Off -> a single base rim
## (the always-visible RimRing), matching a pre-#126 node.
@export var rim_growth: bool = false:
	set(value):
		rim_growth = value
		_sync_stake()
@export_range(1, MAX_STAKE_CAP, 1) var stake_cap: int = 1:
	set(value):
		stake_cap = value
		_sync_stake()
@export_range(0, MAX_STAKE_CAP, 1) var stake_alloc: int = 0:
	set(value):
		stake_alloc = value
		_sync_stake()
@export_range(0.0, 6.0, 0.1) var ring_gap: float = 2.0:
	set(value):
		ring_gap = value
		_sync_stake()

@onready var _children: Array[SkillNodeVisual] = [
	%InnerDisk, %WeldSymbol, %RimRing, %RimRing2, %RimRing3, %RimRing4,
	%RimBonuses, %CoreHalos, %RuneRing,
]
@onready var _rim_rings: Array[SkillNodeRingVisual] = [%RimRing, %RimRing2, %RimRing3, %RimRing4]
@onready var _stake_label: Label = %StakeLabel

## The ONE shared shading source handed to every shaded child (InnerDisk,
## WeldSymbol, all RimRings). The composite edits this object instead of poking
## each child's five shading properties — see [ShadingStyle]. Seeded from
## InnerDisk's scene-authored tint_mix / highlight_* (until a global light
## framework owns those) so the render is unchanged.
var _shading := ShadingStyle.new()


func _ready() -> void:
	_sync_shared()
	_sync_stake()


func configure(new_radius: float) -> void:
	super.configure(new_radius)
	for child in _children:
		if child != null:
			child.configure(new_radius)


## InnerDisk is the source of truth for the shared gradient; WeldSymbol
## mirrors every one of its shading inputs (not just tint_color) so the two
## surfaces read as one continuous lit material — see weld_symbol.gd.
func _sync_shared() -> void:
	if not is_node_ready():
		return
	# Composite owns the shared archetype identity; tint_mix / highlight_* are
	# seeded from InnerDisk's scene-authored values until a global light
	# framework takes them over (render unchanged either way).
	_shading.tint_color = tint_color
	_shading.allocated = allocated
	_shading.tint_mix = %InnerDisk.tint_mix
	_shading.highlight_position = %InnerDisk.highlight_position
	_shading.highlight_intensity = %InnerDisk.highlight_intensity
	# ONE object → every shaded child. Drift is impossible; adding a consumer is
	# one line, not "remember to mirror five props."
	%InnerDisk.shading = _shading
	%WeldSymbol.shading = _shading
	for rw in _rim_rings:
		rw.shading = _shading
	# Non-shaded derivations off the same archetype color.
	%RimBonuses.hue = tint_color.h * 360.0
	%RimBonuses.allocated = allocated
	%RuneRing.tint_color = tint_color


## Positions the (up to 4) pre-placed rim_ring instances outward per stake
## cap, dims unfilled rings to the archetype tint (never flat gray — the
## design doc is explicit about that), then hands RuneRing the node's real
## current outer edge so it clears whatever the stake growth occupies.
func _sync_stake() -> void:
	if not is_node_ready():
		return
	# Disk tucks under the innermost rim (see DISK_RIM_OVERLAP); the weld stays
	# sized to the visible disk edge so its glyph doesn't grow with the overlap.
	%InnerDisk.disk_radius = geom_inner_r + DISK_RIM_OVERLAP
	%WeldSymbol.disk_radius = geom_inner_r
	var ring_width := geom_outer_r - geom_inner_r
	var visible_count := stake_cap if rim_growth else 1
	var max_outer_r := geom_outer_r
	for i in MAX_STAKE_CAP:
		var rw := _rim_rings[i]
		rw.visible = i < visible_count
		if not rw.visible:
			continue
		var inner := geom_inner_r + i * (ring_width + ring_gap)
		var outer := inner + ring_width
		rw.inner_radius = inner
		rw.outer_radius = outer
		#rw.crest_r = inner + (geom_crest_r - geom_inner_r)
		var filled := i < stake_alloc
		rw.ring_tint = _stake_tint_color(filled)
		max_outer_r = maxf(max_outer_r, outer)
	%RuneRing.outer_edge_r = max_outer_r
	_sync_stake_label(max_outer_r)


## "alloc/cap" under the node, only once stake_cap > 1 — a cap of 1 has
## nothing to count (matches rim_ring's own "single wedge reads as
## nothing" rule for the segmented-dial approach).
func _sync_stake_label(max_outer_r: float) -> void:
	_stake_label.visible = rim_growth and stake_cap > 1
	if not _stake_label.visible:
		return
	_stake_label.text = "%d/%d" % [stake_alloc, stake_cap]
	_stake_label.position.y = max_outer_r + 6.0


## Filled rings read as the bright tint; unfilled rings dim to a
## desaturated version of the SAME hue rather than flat gray.
func _stake_tint_color(filled: bool) -> Color:
	if filled:
		return Color.from_hsv(tint_color.h, 0.6, 0.9)
	return Color.from_hsv(tint_color.h, 0.22, 0.5)
