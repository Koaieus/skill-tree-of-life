extends Sprite2D

## The shots-left pip row (#959, Ranged2.0 C8): `●●●○○` under a leaf while
## the local attacker's plan is RANGED and this node is one of its leaves.
## A readout register, not a shell/structure band — it sits BELOW the node,
## outside the plan-view band budget (docs/domain/addon-visual-registers.md).
##
## Render budget (`.claude/rules/rendering-performance.md`): hundreds of
## nodes carry one of these, so it is ONE `Sprite2D` per node on ONE shared
## texture with the default material — a strip of [constant CAPACITY] lit
## dots followed by [constant CAPACITY] unlit ones. "How many lit of how
## many" is purely a `region_rect` (UV) pick into that strip; the owner tint
## is `modulate`. Nothing per-node is a material or a uniform, so every
## visible pip row in the frame batches into the same draw.
##
## Refreshed only by [method refresh] — off `shots_fired_this_turn` writes
## and BattleSystem's plan signals (see `SkillNode._sync_shot_pips`), never
## per frame.

## Dots per half of the strip; also the most pips one row can show
## (level 2 + Watchtower is 12 today).
const CAPACITY := 16
## Pixel pitch of one dot cell in the strip (the dot itself is smaller).
const PIP_PX := 8
## Unlit dots keep this alpha so the *count* stays readable without competing
## with the lit ones.
const UNLIT_ALPHA := 0.28
## Row centre sits this many radii below the node centre — clear of the
## SpikeRing band (`[1.00, 1.45]`) and every elevation piece (all above y=0).
const ROW_OFFSET_R := 1.7
## Lit-dot modulate is kept strictly below 1.0 (`.claude/rules/hdr-color.md`):
## a readout is not a glow.
const MAX_CHANNEL := 0.92

## Lit pips currently shown (== `shots_left()` while shown).
var lit: int = 0
## Pips in the row (== node-local `max_shots_per_leaf` while shown).
var total: int = 0

static var _strip: ImageTexture


static func _shared_strip() -> ImageTexture:
	if _strip == null:
		var img := Image.create(2 * CAPACITY * PIP_PX, PIP_PX, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		var r := PIP_PX * 0.5 - 1.0
		for cell in 2 * CAPACITY:
			var alpha := 1.0 if cell < CAPACITY else UNLIT_ALPHA
			var cx := cell * PIP_PX + PIP_PX * 0.5
			var cy := PIP_PX * 0.5
			for y in PIP_PX:
				for x in PIP_PX:
					var d := Vector2(cell * PIP_PX + x + 0.5 - cx, y + 0.5 - cy).length()
					# 1px soft edge so the dot reads round at 1:1 and at zoom.
					var cover := clampf(r + 0.5 - d, 0.0, 1.0)
					if cover > 0.0:
						img.set_pixel(cell * PIP_PX + x, y, Color(1, 1, 1, alpha * cover))
		_strip = ImageTexture.create_from_image(img)
	return _strip


func _ready() -> void:
	texture = _shared_strip()
	region_enabled = true
	centered = true


## Positions the row for a node of [param radius] (SkillNode.radius, which
## stake level scales).
func configure(radius: float) -> void:
	position = Vector2(0.0, radius * ROW_OFFSET_R)


## [param lit_count] of [param total_count] pips, or hidden when
## [param shown] is false. Pure state + one `region_rect` write; no redraw
## of our own, so calling it every time nothing changed is cheap.
func refresh(lit_count: int, total_count: int, shown: bool, tint: Color = Color.WHITE) -> void:
	total = clampi(total_count, 0, CAPACITY)
	lit = clampi(lit_count, 0, total)
	visible = shown and total > 0
	if not visible:
		return
	# The strip is [CAPACITY lit][CAPACITY unlit]; a window of `total` cells
	# ending `lit` cells into the unlit half shows exactly `lit` lit dots
	# first, then `total - lit` unlit ones.
	region_rect = Rect2((CAPACITY - lit) * PIP_PX, 0, total * PIP_PX, PIP_PX)
	var c := tint
	c.r = minf(c.r, MAX_CHANNEL)
	c.g = minf(c.g, MAX_CHANNEL)
	c.b = minf(c.b, MAX_CHANNEL)
	c.a = 1.0
	modulate = c
