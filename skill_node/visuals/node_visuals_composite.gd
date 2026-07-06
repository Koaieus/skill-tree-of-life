@tool
extends SkillNodeVisual
## Orchestration scene composing all SkillNode-visual components (#126,
## milestone #16). Children are scene-composed in
## node_visuals_composite.tscn (not instantiated in code) — this script
## forwards the knobs that must stay in sync *across* children (hue,
## allocated, the rim radii, stake cap/alloc) and computes the node's
## current actual outer edge so [RuneRing] auto-clears grown stake rings.
## Z-order in the .tscn already matches the final draw order: disk -> weld
## -> wall(s) -> rim bonuses -> halos -> rune ring.
##
## Stake/cap depth: only approach A (ring stacking / rim_growth) is wired.
## Segmented dial (rimSegments) and well/groove (rimWell) are follow-up —
## ring_wall only draws full rings today, no wedge/arc-span support yet.

const MAX_STAKE_CAP := 4

@export_range(0.0, 360.0, 1.0) var hue: float = 220.0:
	set(value):
		hue = value
		_sync_shared()
@export var allocated: bool = false:
	set(value):
		allocated = value
		_sync_shared()

@export var geom_crest_r: float = 28.0:
	set(value):
		geom_crest_r = value
		_sync_stake()
@export var geom_rim_r: float = 32.0:
	set(value):
		geom_rim_r = value
		_sync_stake()

## Ring-stacking stake/cap depth (approach A). Off -> a single base rim
## (the always-visible RingWall), matching a pre-#126 node.
@export var rim_growth: bool = false:
	set(value):
		rim_growth = value
		_sync_stake()
@export_range(1, MAX_STAKE_CAP, 1) var stake_cap: int = 1:
	set(value):
		stake_cap = value
		_sync_stake()
@export var stake_alloc: int = 0:
	set(value):
		stake_alloc = value
		_sync_stake()
@export_range(0.0, 6.0, 0.1) var ring_gap: float = 2.0:
	set(value):
		ring_gap = value
		_sync_stake()

@onready var _children: Array[SkillNodeVisual] = [
	%InnerDisk, %WeldSymbol, %RingWall, %RingWall2, %RingWall3, %RingWall4,
	%RimBonuses, %CoreHalos, %RuneRing,
]
@onready var _ring_walls: Array[SkillNodeRingVisual] = [%RingWall, %RingWall2, %RingWall3, %RingWall4]


func _ready() -> void:
	_sync_shared()
	_sync_stake()


func configure(new_radius: float) -> void:
	super.configure(new_radius)
	for child in _children:
		if child != null:
			child.configure(new_radius)


func _sync_shared() -> void:
	if not is_node_ready():
		return
	%InnerDisk.hue = hue
	%InnerDisk.allocated = allocated
	%RimBonuses.hue = hue
	%RimBonuses.allocated = allocated


## Positions the (up to 4) pre-placed ring_wall instances outward per stake
## cap, dims unfilled rings to the archetype hue (never flat gray — the
## design doc is explicit about that), then hands RuneRing the node's real
## current outer edge so it clears whatever the stake growth occupies.
func _sync_stake() -> void:
	if not is_node_ready():
		return
	var ring_width := geom_rim_r - geom_crest_r
	var visible_count := stake_cap if rim_growth else 1
	var max_rim_r := geom_rim_r
	for i in MAX_STAKE_CAP:
		var rw := _ring_walls[i]
		rw.visible = i < visible_count
		if not rw.visible:
			continue
		var crest := geom_crest_r + i * (ring_width + ring_gap)
		var rim := crest + ring_width
		rw.geom_crest_r = crest
		rw.geom_rim_r = rim
		var filled := i < stake_alloc
		rw.wall_color = _stake_hue_color(filled)
		max_rim_r = maxf(max_rim_r, rim)
	%RuneRing.outer_edge_r = max_rim_r


## Filled rings read as the bright archetype hue; unfilled rings dim to a
## desaturated tint of the SAME hue rather than flat gray.
func _stake_hue_color(filled: bool) -> Color:
	if filled:
		return Color.from_hsv(hue / 360.0, 0.6, 0.9)
	return Color.from_hsv(hue / 360.0, 0.22, 0.5)
