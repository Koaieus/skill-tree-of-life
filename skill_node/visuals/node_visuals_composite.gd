@tool
extends SkillNodeVisual
## Orchestration scene composing all SkillNode-visual components (#126,
## milestone #16). Children are scene-composed in
## node_visuals_composite.tscn (not instantiated in code) — this script
## forwards the knobs that must stay in sync *across* children (entity_tint,
## archetype_tint, allocation_level, the rim radii, stake level/alloc) and
## computes the node's current actual outer edge so [RuneRing] auto-clears
## grown stake rings.
##
## This is also the ONLY layer that knows both InnerDisk and RimRing exist:
## [member geom_inner_r] is handed to both, so the disk's edge and the
## ring's floor line up — RimRing itself carries no disk knowledge at all.
##
## Two tints, two jobs — never merge them back into one:
##   entity_tint    — the allocating entity's color ("player tint"). Drives
##                     InnerDisk (and its composed WeldSymbol) and CoreHalos,
##                     which read as "this is MINE", only visible/meaningful
##                     once allocated.
##   archetype_tint — the node's persistent type identity. Drives RimRing's
##                     tint_mix (mixed toward the ring's own bronze/gold at
##                     low mix), RuneRing, and RimBonuses — structural reads
##                     that stay legible whether or not the node is owned.
##
## Stake/cap depth has two wired approaches, both driven off the same
## stake_level/allocation_level: approach A (ring stacking / rim_growth,
## RimRing2-4) and approach B (RimBonuses' segmented glow dial, always
## synced but visible=false in this scene by default — flip it on a node
## when you want the dial instead of/alongside stacked rings). Well/groove
## (rimWell) remains a follow-up.

const MAX_STAKE_CAP := 4

## The disk is sized this many px LARGER than geom_inner_r so its faded outer
## edge tucks UNDER the innermost rim (drawn above it), instead of leaving a ~1px
## transparent seam where the disk has faded out but the rim's inner AA hasn't
## filled in yet — the dark background was peeking through that ring. The rim
## hides the overlap, so the disk still reads as ending at geom_inner_r.
const DISK_RIM_OVERLAP := 1.5

## Mix pushed into a filled vs. unfilled stake ring's [member RimRing.tint_mix]
## — filled reads as fully the archetype identity, unfilled mostly reads as
## the rim's own bronze/gold metal with only a hint of tint.
const FILLED_TINT_MIX := 1.0
const UNFILLED_TINT_MIX := 0.3

## The allocating entity's color ("player tint") — see class doc. Drives
## InnerDisk/WeldSymbol/CoreHalos.
@export var entity_tint: Color = Color(0.291, 0.5892, 1.0):
	set(value):
		entity_tint = value
		_sync_shared()

## Persistent type/archetype identity color — see class doc. Drives RimRing/
## RuneRing/RimBonuses.
@export var archetype_tint: Color = Color(0.65, 0.67, 0.72):
	set(value):
		archetype_tint = value
		_sync_shared()

## Max allocation slots for this node — 1 for the ~99% common case;
## staked nodes go up to [const MAX_STAKE_CAP].
@export_range(1, MAX_STAKE_CAP, 1) var stake_level: int = 1:
	set(value):
		stake_level = value
		_sync_stake()
## Current fill count (0..stake_level). [member allocated] is just
## `allocation_level > 0`.
@export_range(0, MAX_STAKE_CAP, 1) var allocation_level: int = 0:
	set(value):
		allocation_level = value
		_sync_stake()
		_sync_shared()

## `allocation_level > 0` — never set directly, so there's exactly one
## source of truth for "is this node owned" driving the visuals.
var allocated: bool:
	get(): return allocation_level > 0

## Pit/disc edge — shared by InnerDisk.disk_radius (WeldSymbol mirrors it
## internally) and RimRing.inner_radius (base ring only; stacked rings grow
## outward from here, see _sync_stake).
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
@export_range(0.0, 6.0, 0.1) var ring_gap: float = 2.0:
	set(value):
		ring_gap = value
		_sync_stake()

@onready var _children: Array[SkillNodeVisual] = [
	%InnerDisk, %RimRing, %RimRing2, %RimRing3, %RimRing4,
	%RimBonuses, %CoreHalos, %RuneRing,
]
@onready var _rim_rings: Array[SkillNodeRingVisual] = [%RimRing, %RimRing2, %RimRing3, %RimRing4]
@onready var _stake_label: Label = %StakeLabel

## The ONE shared shading source handed to every shaded child (InnerDisk —
## which forwards it to its own composed WeldSymbol — and every RimRing).
## The composite edits this object instead of poking each child's five
## shading properties — see [ShadingStyle]. Seeded from InnerDisk's
## scene-authored tint_mix / highlight_* (until a global light framework
## owns those) so the render is unchanged.
var _shading := ShadingStyle.new()


func _ready() -> void:
	_sync_shared()
	_sync_stake()


func configure(new_radius: float) -> void:
	super.configure(new_radius)
	for child in _children:
		if child != null:
			child.configure(new_radius)


## InnerDisk (and its composed WeldSymbol) is the source of truth for the
## shared gradient; RimRing only reads the light direction off the same
## object so the ring never drifts onto a second light.
func _sync_shared() -> void:
	if not is_node_ready():
		return
	_shading.tint_color = entity_tint
	_shading.allocated = allocated
	_shading.tint_mix = %InnerDisk.tint_mix
	_shading.highlight_position = %InnerDisk.highlight_position
	_shading.highlight_intensity = %InnerDisk.highlight_intensity
	# ONE object → every shaded child. Drift is impossible; adding a consumer is
	# one line, not "remember to mirror five props."
	%InnerDisk.shading = _shading
	%InnerDisk.visible = allocated
	for rw in _rim_rings:
		rw.shading = _shading
	# Non-shaded derivations off the archetype identity color.
	%RimBonuses.tone_tint = archetype_tint
	%RimBonuses.allocated = allocated
	%RuneRing.tint_color = archetype_tint
	# Entity identity, not archetype — the halo marks "this is YOUR core".
	%CoreHalos.halo_color = entity_tint
	# Stake-fill dial glows with entity color, same as a lit edge.
	%RimBonuses.fill_glow_tint = entity_tint


## Positions the (up to 4) pre-placed rim_ring instances outward per stake
## level, mixes unfilled rings mostly toward the rim's own bronze/gold metal
## (never flat gray — the design doc is explicit about that), then hands
## RuneRing the node's real current outer edge so it clears whatever the
## stake growth occupies.
func _sync_stake() -> void:
	if not is_node_ready():
		return
	# Disk tucks under the innermost rim (see DISK_RIM_OVERLAP).
	%InnerDisk.disk_radius = geom_inner_r + DISK_RIM_OVERLAP
	var ring_width := geom_outer_r - geom_inner_r
	var visible_count := stake_level if rim_growth else 1
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
		var filled := i < allocation_level
		rw.archetype_tint = archetype_tint
		rw.tint_mix = FILLED_TINT_MIX if filled else UNFILLED_TINT_MIX
		max_outer_r = maxf(max_outer_r, outer)
	%RuneRing.outer_edge_r = max_outer_r
	_sync_stake_label(max_outer_r)

	# Stake-fill dial (approach B) — current/max mirrors allocation_level/
	# stake_level directly; band sits at the same crest->outer span as the
	# base rim's own bevel-to-edge zone (see class doc's geom_crest_r).
	%RimBonuses.inner_radius = geom_crest_r
	%RimBonuses.outer_radius = geom_outer_r
	%RimBonuses.fill_max = stake_level
	%RimBonuses.fill_current = allocation_level


## "alloc/cap" under the node, only once stake_level > 1 — a level of 1 has
## nothing to count (matches rim_ring's own "single wedge reads as
## nothing" rule for the segmented-dial approach).
func _sync_stake_label(max_outer_r: float) -> void:
	_stake_label.visible = rim_growth and stake_level > 1
	if not _stake_label.visible:
		return
	_stake_label.text = "%d/%d" % [allocation_level, stake_level]
	_stake_label.position.y = max_outer_r + 6.0
