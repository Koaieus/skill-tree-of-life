class_name BlockerVisual
extends Node2D
## Null-field blob overlay for a Dormant Core's blocked node: one quad under
## the shared `blocker_blob_material.tres`, drawn only while the node reads as
## blocked. Blocked is a latch on the first owner's instance ID, and crack
## stage follows the node's combat-HP fraction on the presentation clock.
## Not `@tool`. See docs/domain/dormant-core.md "BlockerVisual internals".

## Crack stages are the contract (the blob art is tunable).
enum CrackStage { INTACT, CRACKED, SHATTERED }

## Node HP fraction at or below which the blob reads "cracked" (≤ 66%).
const CRACKED_AT := 2.0 / 3.0
## Node HP fraction at or below which the blob reads "shattered" (≤ 33%).
const SHATTERED_AT := 1.0 / 3.0

const BLOB_MATERIAL := preload("res://skill_node/visuals/blocker_blob_material.tres")

## How far the drawn quad reaches past the blob's rest radius, so lobes that
## drift apart on damage are never clipped by the quad's edge. Must match the
## shader's `QUAD_EXTENT`.
const QUAD_EXTENT := 1.6

## Lobes per [member Entity.entity_tier] 1..3 (index = tier - 1). Tentative,
## easy to change; keep it strictly increasing so tiers stay distinguishable.
@export var tier_lobes: Array[int] = [1, 2, 3]:
	set(value):
		tier_lobes = value
		_sync_material()

## The blob's rest footprint as a fraction of [member SkillNode.radius] — so
## stake still grows it. Tentative, easy to change.
@export_range(0.5, 1.2, 0.01) var blob_radius_scale := 0.92:
	set(value):
		blob_radius_scale = value
		queue_redraw()

## The named glow tier the damage bleed lights at (`docs/domain/hdr-color.md`);
## the lowest tier above threshold. Written onto the SHARED material as a plain
## uniform — identical for every core.
@export var bleed_tier: Emissive.Tier = Emissive.Tier.LABEL

## The bleed's hue before its [member bleed_tier] lift.
@export var bleed_base: Color = Color(0.55, 0.42, 1.0)

var crack_stage: CrackStage = CrackStage.INTACT

## Lobes this blob draws: [member tier_lobes] at the LATCHED tier.
var lobe_count: int:
	get:
		if tier_lobes.is_empty():
			return 1
		return tier_lobes[clampi(_latched_tier - 1, 0, tier_lobes.size() - 1)]

## This node's variant seed in [0, 1), read live off [member SkillNode.stable_id]
## (it is 0 until the graph mints it, so it is never latched).
var blob_seed: float:
	get: return seed_for(_node.stable_id if _node != null else 0)


## The variant seed for a node identity: golden-ratio fract, deterministic on
## every peer, distinct for neighbouring ids.
static func seed_for(stable_id: int) -> float:
	return fposmod(float(stable_id) * 0.6180339887, 1.0)


var _node: SkillNode = null

## `get_instance_id()` of the entity latched as "the blocker" — the first
## non-null [member SkillNode.owned_by] this node ever saw. 0 until that first
## ownership. An ID rather than the entity itself so a freed corpse can't read
## back as "nothing latched" — see the class docstring.
var _latched_owner_id: int = 0
## True once ownership has diverged from [member _latched_owner_id] even once.
## Permanent: never reset back to false.
var _cleared: bool = false
## The latched owner's [member Entity.entity_tier], read once with the id so a
## later write (or a freed corpse) can never change the look.
var _latched_tier: int = 1


func _ready() -> void:
	_node = owner as SkillNode
	if _node != null:
		# CONNECT_DEFERRED, matching health_bar.gd's `_on_owner_changed`:
		# reading combat HP needs `SkillNode._refresh_hp_binding` to have
		# already bound this node's `node_board` to the new owner's baseline.
		# Godot calls a child's `_ready` before its parent's, so this visual's
		# connect call (here) lands AHEAD of `SkillNode._ready`'s own
		# `owner_changed.connect(_refresh_hp_binding)` — a plain connection
		# would run this handler first and read a stale/zero max, misreporting
		# SHATTERED at full health. Deferring runs it once the same-frame
		# synchronous listeners (including the hp binding) have all fired.
		if not _node.owner_changed.is_connected(_on_owner_changed):
			_node.owner_changed.connect(_on_owner_changed, CONNECT_DEFERRED)
		if not _node.sensed_changed.is_connected(_on_sensed_changed):
			_node.sensed_changed.connect(_on_sensed_changed)
		# #504: crack stage re-syncs off the node's real combat HP. The hit that
		# causes it lands on its own `arrival_time` (see [BeatClock]), so
		# `damaged` already fires on the beat the blob should visibly crack.
		if not _node.damaged.is_connected(_on_damaged):
			_node.damaged.connect(_on_damaged)
		if not _node.healed.is_connected(_on_damaged):
			_node.healed.connect(_on_damaged)
	# An ancestor (a fogged SkillNode) toggling visibility re-gates the material.
	visibility_changed.connect(_sync_material)
	# Deferred for the same reason as the connect above. Establishes the
	# initial latch (a freshly-spawned blocker's force_allocate already ran
	# before this visual entered the tree, so `owned_by` is non-null here) and
	# syncs crack stage / visibility for the first frame, once SkillNode's own
	# `_ready` has bound the node_board.
	_on_owner_changed.call_deferred()


## #504: the node's combat HP moved — re-sync the crack stage against it.
## Bound to both `damaged` and `healed`; each carries `(amount, source)`, both
## ignored, because the stage is a function of the CURRENT fraction rather than
## of the delta.
func _on_damaged(_amount: float, _source: HitInstance) -> void:
	_refresh_stage_and_visibility()


func _on_owner_changed() -> void:
	_update_latch()
	_refresh_stage_and_visibility()


func _on_sensed_changed() -> void:
	_apply_visibility()


## Advances the latch state machine. Idempotent — safe to call on every
## `owner_changed`, including ones that don't move the latch at all.
func _update_latch() -> void:
	if _cleared or _node == null:
		return
	var cur := _node.owned_by
	if _latched_owner_id == 0:
		if cur != null:
			_latched_owner_id = cur.get_instance_id()
			_latched_tier = cur.entity_tier
		return
	# `cur` going null covers BOTH the death strip and a freed corpse — the
	# strip always runs first (AllocationSystem on `entity_died`, GameRoot's
	# despawn on the later `entity_death_shown`), so by the time anyone could
	# have freed the entity this reads 0 either way.
	var cur_id := cur.get_instance_id() if cur != null else 0
	if cur_id != _latched_owner_id:
		_cleared = true


func _is_blocked() -> bool:
	return not _cleared and _latched_owner_id != 0


## Re-derive crack stage + visibility. Runs off `damaged` (inline) and
## `owner_changed` (deferred — see `_ready`'s docstring), so `crack_stage` is
## correct the instant a hit lands with no extra frame wait, while still
## reading a correctly-bound HP pool on a fresh allocation.
func _refresh_stage_and_visibility() -> void:
	var blocked := _is_blocked()
	if blocked:
		_update_stage()
	else:
		crack_stage = CrackStage.INTACT
	_apply_visibility()


func _apply_visibility() -> void:
	visible = _is_blocked() and (_node == null or not _node.sensed)
	_sync_material()


## Binds the shared material and pushes this blob's instance uniforms — only
## while visible in the tree, because binding claims an instance-uniform slot.
## Hidden, sensed or cleared: no material at all.
func _sync_material() -> void:
	if not is_node_ready():
		return
	if not (visible and is_visible_in_tree()):
		if material != null:
			material = null
		return
	if material != BLOB_MATERIAL:
		material = BLOB_MATERIAL
	var bleed := Emissive.tint(bleed_base, Emissive.stops(bleed_tier))
	if BLOB_MATERIAL.get_shader_parameter(&"bleed_color") != bleed:
		BLOB_MATERIAL.set_shader_parameter(&"bleed_color", bleed)
	set_instance_shader_parameter(&"lobes", lobe_count)
	set_instance_shader_parameter(&"seed", blob_seed)
	set_instance_shader_parameter(&"damage", float(crack_stage))
	queue_redraw()


## Never bake the runtime material or its instance uniforms into a saved scene
## (as [method SkillNodeVisual._validate_property]).
func _validate_property(property: Dictionary) -> void:
	if property.name == "material" or (property.name as String).begins_with("instance_shader_parameters/"):
		property.usage = (property.usage as int) & ~PROPERTY_USAGE_STORAGE


func _update_stage() -> void:
	var frac := _hp_fraction()
	if frac <= SHATTERED_AT:
		crack_stage = CrackStage.SHATTERED
	elif frac <= CRACKED_AT:
		crack_stage = CrackStage.CRACKED
	else:
		crack_stage = CrackStage.INTACT


func _hp_fraction() -> float:
	if _node == null:
		return 1.0
	var max_hp := _node.get_max_hp()
	if max_hp <= 0.0:
		return 0.0
	return _node.get_current_hp() / max_hp


func _radius() -> float:
	return _node.radius if _node != null else 0.0


func _draw() -> void:
	var r := _radius() * blob_radius_scale * QUAD_EXTENT
	if r <= 0.0 or material == null:
		return
	draw_rect(Rect2(Vector2(-r, -r), Vector2.ONE * r * 2.0), Color.WHITE)
