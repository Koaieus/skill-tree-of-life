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
## It is also the sole authority on the node's identity — `entity_tint`,
## `archetype_tint` and `allocated`, all inherited from [SkillNodeVisual] and
## pushed into every child by `_sync_shared()`. Never merge the two tints back
## into one: entity color says "this is MINE" (the central disk, the core
## halos), archetype color says "this is what I AM" (every rim, the rune ring),
## and a component decides for itself which it reads.
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

## Max allocation slots for this node — 1 for the ~99% common case;
## staked nodes go up to [const MAX_STAKE_CAP].
@export_range(1, MAX_STAKE_CAP, 1) var stake_level: int = 1:
	set(value):
		stake_level = value
		_sync_stake()
## Current fill count (0..stake_level), and the ONE source of truth for the
## inherited [member SkillNodeVisual.allocated] — which this setter derives
## rather than anyone assigning it directly.
@export_range(0, MAX_STAKE_CAP, 1) var allocation_level: int = 0:
	set(value):
		allocation_level = value
		allocated = allocation_level > 0
		_sync_stake()
		_sync_shared()

## Pit/disc edge — shared by InnerDisk.disk_radius (the weld glyph scales its
## own weld_k relative to this same radius) and RimRing.inner_radius (base
## ring only; stacked rings grow outward from here, see _sync_stake).
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

## The ONE shared light handed to every lit child (InnerDisk — whose weld glyph
## is folded into its own shader, so it rides the same uniforms, not a second
## object — and every RimRing). See [LightingStyle]. Seeded from InnerDisk's
## scene-authored highlight_* until a global light framework owns them.
var _lighting := LightingStyle.new()


## The composite's own identity inputs fan out to its children rather than
## being drawn with.
func _on_identity_changed() -> void:
	_sync_shared()


func _ready() -> void:
	_sync_shared()
	_sync_stake()


func configure(new_radius: float) -> void:
	super.configure(new_radius)
	for child in _children:
		if child != null:
			child.configure(new_radius)


## Pushes the node's identity — both tints and `allocated` — into EVERY child
## uniformly, then hands the shaded ones the one shared light. Which of the two
## tints a child actually reads is the child's own business (see
## [SkillNodeVisual]'s identity contract); this loop only guarantees both are
## reachable and in sync, so no component can be added and then silently left
## out of a hand-written fan-out.
func _sync_shared() -> void:
	if not is_node_ready():
		return
	for child in _children:
		child.entity_tint = entity_tint
		child.archetype_tint = archetype_tint
		child.allocated = allocated
	# InnerDisk is the source of truth for the faked light; ONE object carries
	# it to every surface lit by it, so disk and rim can't drift apart.
	_lighting.highlight_position = %InnerDisk.highlight_position
	_lighting.highlight_intensity = %InnerDisk.highlight_intensity
	%InnerDisk.lighting = _lighting
	for rw in _rim_rings:
		rw.lighting = _lighting


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
