@tool
extends SkillNodeVisual
## Orchestration scene composing all SkillNode-visual components (#126,
## milestone #16). Children are scene-composed in
## node_visuals_composite.tscn (not instantiated in code) — this script
## forwards the knobs that must stay in sync *across* children (entity_tint,
## archetype_tint, allocation_level, the rim radii, stake level/alloc) and
## computes the node's current actual outer edge so [RuneRing] clears the rim.
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
## Stake/cap depth is the [RimBonuses] segmented glow dial (driven off
## stake_level/allocation_level), the sole stake visualization since #172
## retired the ring-stacking approach (the extra RimRing2-4 placeholders — a
## per-node cost we didn't want at 2000+ nodes/level). Growing the node radius
## with stake is a possible visual follow-up (#178).

const MAX_STAKE_CAP := 4

## The disk is sized this many px LARGER than geom_inner_r so its faded outer
## edge tucks UNDER the rim (drawn above it), instead of leaving a ~1px
## transparent seam where the disk has faded out but the rim's inner AA hasn't
## filled in yet — the dark background was peeking through that ring. The rim
## hides the overlap, so the disk still reads as ending at geom_inner_r.
const DISK_RIM_OVERLAP := 1.5

## Rim [member RimRing.tint_mix] by allocation: an allocated node's rim reads as
## fully the archetype identity; an unallocated one mostly as the rim's own
## bronze/gold metal with only a hint of tint (never flat gray — the design doc
## is explicit). The disk carries entity color, the rim carries archetype — so
## the rim "activating" toward its archetype hue on allocation is a second,
## independent allocation read alongside the disk lighting up.
const FILLED_TINT_MIX := 1.0
const UNFILLED_TINT_MIX := 0.3

## Base width of the RimBonuses segmented-glow band when stake_level == 1.
## The band sits anchored at [member geom_outer_r] (outer rim edge) and extends
## inward; this is the default inward extent in pixels.
const RIM_BONUS_DEFAULT_WIDTH := 4.0

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
## own weld_k relative to this same radius) and RimRing.inner_radius.
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

## Extra inward growth (pixels per stake level above 1) applied to the
## RimBonuses segmented-glow band. The band's outer edge stays anchored at
## [member geom_outer_r]; only the inner edge moves inward, widening the glow.
## 0.0 = constant band width regardless of stake.
@export_range(0.0, 6.0, 0.5) var bonus_inward_growth: float = 2.0:
	set(value):
		bonus_inward_growth = value
		_sync_stake()

@onready var _children: Array[SkillNodeVisual] = [
	%InnerDisk, %RimRing, %RimBonuses, %CoreHalos, %RuneRing,
]

## The ONE shared light handed to every lit child (InnerDisk — whose weld glyph
## is folded into its own shader, so it rides the same uniforms, not a second
## object — and the RimRing). See [LightingStyle]. Seeded from InnerDisk's
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
	%RimRing.lighting = _lighting


## Lines the base rim up with the disk edge, clears the rune ring past the rim,
## and drives the RimBonuses stake dial. RimBonuses is the sole stake/cap depth
## visualization since #172 retired ring-stacking (approach A).
func _sync_stake() -> void:
	if not is_node_ready():
		return
	# Disk tucks under the rim (see DISK_RIM_OVERLAP).
	%InnerDisk.disk_radius = geom_inner_r + DISK_RIM_OVERLAP
	%RimRing.inner_radius = geom_inner_r
	%RimRing.outer_radius = geom_outer_r
	%RimRing.tint_mix = FILLED_TINT_MIX if allocation_level > 0 else UNFILLED_TINT_MIX
	%RuneRing.outer_edge_r = geom_outer_r

	# Stake-fill dial: outer edge stays anchored at geom_outer_r (grows outward
	# with radius), inner edge shifts inward by bonus_inward_growth per stake level
	# above 1 for a more pronounced glow as the node physically expands (#178).
	var bonus_inner := geom_outer_r - RIM_BONUS_DEFAULT_WIDTH - float(stake_level - 1) * bonus_inward_growth
	%RimBonuses.inner_radius = maxf(bonus_inner, 0.0)
	%RimBonuses.outer_radius = geom_outer_r
	%RimBonuses.fill_max = stake_level
	%RimBonuses.fill_current = allocation_level
