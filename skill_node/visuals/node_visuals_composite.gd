@tool
extends SkillNodeVisual
## Orchestration scene composing all SkillNode-visual components (#126,
## milestone #16). Children are scene-composed in
## node_visuals_composite.tscn (not instantiated in code) — this script
## forwards the knobs that must stay in sync *across* children (entity_tint,
## archetype_tint, allocation_level, the rim radii, stake level/alloc).
##
## This is also the ONLY layer that knows both InnerDisk and RimRing exist:
## [member geom_inner_r] is handed to both, so the disk's edge and the
## ring's floor line up — RimRing itself carries no disk knowledge at all.
##
## It is also the sole authority on the node's identity — `entity_tint`,
## `archetype_tint` and `allocated`, all inherited from [SkillNodeVisual] and
## pushed into every child by `_sync_shared()`. Never merge the two tints back
## into one: entity color says "this is MINE" (the central disk, the core
## halos), archetype color says "this is what I AM" (every rim), and a component
## decides for itself which it reads.
##
## SHELVED ENCODERS (#238, verdict in #132). RimBonuses (rim gems + the
## segmented stake dial) and RuneRing were instanced here as *alternate* looks
## the design labs authored, never as simultaneous layers, and they crowded each
## other out. Both are cut from the production stack — the scenes stay in the
## repo and stay previewable in the sandbox host's Node Visuals tab, which is
## the shelf. Nothing hidden-but-instanced was left behind on purpose: a level
## carries ~500-2500 of these, so an unused child is tree nodes, `_ready` work
## and potentially an instance-uniform slot (#172) on every one of them (see
## .claude/rules/skill-node-scale.md).
##
## #341 reclaimed the DIAL'S FUNCTION (not the RimBonuses scene, which stays
## shelved) as a shader term on [RimRing] itself: [method _sync_stake] forwards
## `allocation_level`/`stake_level` straight into `%RimRing.fill_current` /
## `.fill_max`, so "1/3 vs 3/3 allocated" is visualized again without
## re-instancing anything. `rim_bonuses.tscn`/`rune_ring.tscn` are still the
## shelf for the OTHER encoders (rim gems, the rune band) that never got a
## reclaim.

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
##
## The swing WAS 0.3 → 1.0. It is now 0.8 → 0.9: both states are deliberately
## far more colourful, because the tinted rim is what makes a node legible at
## board zoom — bronze-dominant at 0.3 did not read. Confirmed as intended by
## the owner 2026-08-14; the paragraph that used to sit here claimed #341 "kept
## these two ratios as-is" and pointed at a test pinning 0.3, both of which had
## been false since whoever retuned them for visibility.
##
## So allocation is now a NARROW tint step (0.8 → 0.9) carried mostly by other
## channels — the disk lighting up, RimRing._effective_tint's saturate/brighten,
## and the additive fill glow. Don't widen it back for contrast without checking
## legibility at 500-2500 nodes first; the unallocated end is the constraint.
const FILLED_TINT_MIX := 0.9
const UNFILLED_TINT_MIX := 0.8

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

## Pit/disc edge — shared by InnerDisk.disk_radius (the carve glyph scales its
## own circumradius relative to this same radius) and RimRing.inner_radius.
@export_range(0.0, 128.0, 0.5) var geom_inner_r: float = 24.0:
	set(value):
		geom_inner_r = value
		_sync_stake()
## Interior bevel control point — see rim_ring.gd.
##
## Defaults to 0.0, NOT to rim_ring.gd's own 28.0, and that is deliberate: this
## export was inert until 2026-08-14 (`_sync_stake` never forwarded it), so
## every rim the game has ever drawn ran at rim_ring.tscn's authored 0.0 —
## including the one #341's legibility sweep was judged against. Wiring the
## forward at 28.0 would have silently retuned every node on the board on the
## strength of a value that had never been rendered. What crest_r SHOULD be is
## an owner call: see triage item B9.
@export_range(0.0, 128.0, 0.5) var geom_crest_r: float = 0.0:
	set(value):
		geom_crest_r = value
		_sync_stake()
@export_range(0.0, 128.0, 0.5) var geom_outer_r: float = 32.0:
	set(value):
		geom_outer_r = value
		_sync_stake()

## The central-emblem shape this composite carves — the ONE knob for previewing
## a shape, on the node you'd expect to find it on. Authoring this in
## skill_node.tscn or the node-visuals panel gives live in-editor feedback.
## The composite composes and ROUTES it down to the leaf [InnerDisk]'s own
## authored [member InnerDisk.carve_shape] — it doesn't interpret it, same as it
## doesn't interpret entity_tint for its children. Before this export existed
## the only shape control was [InnerDisk]'s scalar carve knobs, which are
## documented as standalone-preview fallbacks that [method set_carve]
## overwrites — so a designer's inspector edit silently reverted the moment
## anything resynced.
##
## RUNTIME PRECEDENCE: [SkillNode] pushes a fully RESOLVED carve through
## [method set_carve] on every `_sync_visuals()`, and that resolution (archetype
## vs. keystone vs. spell, by priority — see [EmblemResolver]) wins. This export
## is the authored default that stands in when nothing has resolved a carve yet,
## which is exactly the in-editor and standalone-panel case.
@export var carve_shape: CarveShape = null:
	set(value):
		if carve_shape == value:
			return
		carve_shape = value
		_apply_carve_shape()

## Whether [method _apply_carve_shape] has pushed a shape down to InnerDisk.
## Distinguishes "never authored a shape" (leave the disk's own authored
## [member InnerDisk.carve_shape] alone) from "authored one, then cleared it"
## (actually clear the carve).
var _applied_a_shape: bool = false

# Cached child refs — `%Name` compiles to a scene-tree lookup, and the _sync_*
# paths below run on every radius / owner / allocation change, so resolve once.
# NOTE: these are `@onready` (null until in-tree) and so must NOT be used by
# `_apply_sensed`, which runs pre-tree — it resolves by direct child path, see
# there.
@onready var _inner_disk := %InnerDisk
@onready var _rim_ring := %RimRing
# CorePresence is now its own reusable scene (core_presence.tscn, shared with
# the core-move drag ghost) rather than inline nodes here, so CoreHalos/
# CoreSigilBloom's unique names are scoped to CorePresence's OWN root, not
# this composite's — resolve them by direct child path off _core_presence,
# not `%Name`.
@onready var _core_presence := %CorePresence
@onready var _core_halos := _core_presence.get_node(^"CoreHalos")
@onready var _core_sigil_bloom := _core_presence.get_node(^"CoreSigilBloom")

@onready var _children: Array[SkillNodeVisual] = [
	%InnerDisk, %RimRing, _core_halos, _core_sigil_bloom, %SensedOutline,
]

## Sensed-but-not-visible: the node reads as an archetype-only outline
## ([SensedOutline]) with the full shader stack hidden — a real display state on
## the composite, not "hide everything and let a legacy renderer stand in" (the
## #141 bug this fixes). The archetype-only guarantee is structural: SensedOutline
## can only draw `archetype_tint`, so no owner info can leak through the fog.
var sensed: bool = false:
	set(value):
		sensed = value
		_apply_sensed()

## Transient feedback tint (hit-flash on damage, dealloc-denied blink/shake,
## #304) — applied as THIS node's own `modulate` rather than a shared child's,
## so [SkillNodeVisual]'s HoverRing sibling (a child of Visuals, not of this
## composite) is never touched: a `visuals.modulate` tint would multiply the
## hover glow down to near-black and read as "the glow vanished" (see
## skill_node.gd's denial-feedback section). Driven by SkillNode the same way
## `sensed` / `core_active` are, rather than SkillNode tweening a grandchild's
## modulate directly (the old target, `_base_circle`, is what BaseCircle
## retired).
var feedback_tint: Color = Color.WHITE:
	set(value):
		feedback_tint = value
		modulate = value


## Whether this node currently hosts its owner's core. Gates the core-only
## presence visuals — CoreHalos today (CoreSigilBloom next, #128) — so they draw
## on the ONE core node, not every node (the gimbal pass dropped this gate, which
## put a halo on all nodes and tanked fps: each gimbal is hundreds of draw calls).
## Fed by SkillNode. Nested under ShaderStack, so `sensed` still hides it for free.
var core_active: bool = false:
	set(value):
		core_active = value
		if is_node_ready():
			_apply_core_active()

## The ONE shared light handed to every lit child (InnerDisk — whose carve glyph
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
	_apply_carve_shape()
	_apply_sensed()
	_apply_core_active()


## Gate the core-only presence visuals ([CorePresence]: halos + bloom) on
## `core_active`. Nested inside ShaderStack, so `sensed` (which hides the whole
## stack) still wins — a fogged core shows no halo/bloom.
func _apply_core_active() -> void:
	_core_presence.visible = core_active


## Swaps between the full shader stack and the archetype-only outline. Resolves
## the two nodes by DIRECT child path (not a `%`-unique-name `@onready`) so the
## `sensed` setter works before this node is in the tree: a caller can
## `instantiate()` then set `sensed = true` and have ShaderStack already hidden
## when the shader children's `_ready` runs — so they never bind a material and
## a start-sensed node claims ZERO instance-uniform slots (#172), the same gate
## as a fog-hidden `visible = false` node. A `%`-name would return null until the
## node enters the tree, leaving the stack visible through the children's `_ready`.
func _apply_sensed() -> void:
	var stack := get_node_or_null(^"ShaderStack") as Node2D
	var outline := get_node_or_null(^"SensedOutline") as Node2D
	if stack == null or outline == null:
		return
	stack.visible = not sensed
	outline.visible = sensed


## Forwards a resolved central-emblem CARVE (see [method SkillNode.get_emblem_contributions],
## [EmblemResolver], docs/domain/skillnode-emblem.md) to [InnerDisk] — the
## composite doesn't interpret it, same as it doesn't interpret entity_tint
## for its children; it just routes to the one child that renders the dome.
func set_carve(carve: Variant) -> void:
	_inner_disk.set_carve(carve)


## Routes [member carve_shape] down to the leaf [InnerDisk]'s own authored
## [member InnerDisk.carve_shape] — the composite composes and routes, it
## doesn't interpret (see the export's doc). Kept separate from
## [method set_carve] so the resolved-runtime path and the authored-default
## path stay distinguishable; the disk's own [member InnerDisk._has_carve] is
## what lets a runtime resolution outrank this authored value.
func _apply_carve_shape() -> void:
	if not is_node_ready():
		return
	if carve_shape == null:
		# Null means "nothing authored HERE", NOT "carve nothing" — leave the
		# disk's own authored carve_shape alone. Pushing null unconditionally
		# would flatten the dome on every composite at _ready and silently
		# override the panel's authored preview shape. But once we HAVE applied
		# a shape, clearing the export back to null must actually clear it, or
		# the stale carve sticks.
		if _applied_a_shape:
			_applied_a_shape = false
			_inner_disk.carve_shape = null
		return
	_applied_a_shape = true
	_inner_disk.carve_shape = carve_shape


## The core-class [Sigil] to BLOOM on [CoreSigilBloom] (Register 3, #128) —
## null when this node isn't the owner's core. Fed by SkillNode alongside
## `core_active`.
func set_core_sigil(sigil: Sigil) -> void:
	_core_sigil_bloom.sigil = sigil


## Retargets the old CoreMarker glide-in tween onto [CorePresence]: slides the
## halo in from `local_offset` while the bloom extinguishes/reignites in
## lockstep (see core_presence.gd). Called by SkillNode.play_core_slide_from.
func glide_core_presence(local_offset: Vector2, duration: float) -> void:
	_core_presence.glide_from(local_offset, duration)


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
	_lighting.highlight_position = _inner_disk.highlight_position
	_lighting.highlight_intensity = _inner_disk.highlight_intensity
	_inner_disk.lighting = _lighting
	_rim_ring.lighting = _lighting


## Lines the base rim up with the disk edge, activates its tint on allocation,
## and (#341) drives its current/max dial fill. The RimBonuses stake dial that
## used to live here as a separate scene is still shelved (#238) — its
## SEMANTICS are reclaimed by RimRing's own `fill_current`/`fill_max`, forwarded
## straight from this node's `allocation_level`/`stake_level` below.
func _sync_stake() -> void:
	if not is_node_ready():
		return
	# Disk tucks under the rim (see DISK_RIM_OVERLAP).
	_inner_disk.disk_radius = geom_inner_r + DISK_RIM_OVERLAP
	_rim_ring.inner_radius = geom_inner_r
	# geom_crest_r was stored and never forwarded — the export did nothing. The
	# forward is the fix; the VALUE is untouched on purpose (see the export's
	# doc comment and triage B9), so this lands pixel-neutral.
	_rim_ring.crest_r = geom_crest_r
	_rim_ring.outer_radius = geom_outer_r
	_rim_ring.tint_mix = FILLED_TINT_MIX if allocation_level > 0 else UNFILLED_TINT_MIX
	_rim_ring.fill_max = stake_level
	_rim_ring.fill_current = allocation_level
