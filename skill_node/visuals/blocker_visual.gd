class_name BlockerVisual
extends Node2D
## Null-field blob overlay for a Dormant Core's blocked node (#300 / #478 /
## #1526). While the node reads as blocked, draws one quad under the shared
## `blocker_blob_material.tres`; the shader draws everything — tar-black
## metaball lobes whose edge deforms slowly on `TIME`, drifting luminance-mask
## texture layers, glitch, and the damage read. Tier reads as fused LOBE COUNT
## ([member tier_lobes]), never node size: [member SkillNode.radius] already
## grows with stake. Three crack stages sync to the node's combat-HP fraction
## (intact > 66%, cracked ≤ 66%, shattered ≤ 33%); as the stage rises the lobes
## drift apart, the edge fractures and the glitch light bleeds. Each node's
## variant (texture offset, lobe phase, glitch timing) is
## [method seed_for] its [member SkillNode.stable_id], so every peer draws the
## same blob. The design: `docs/domain/dormant-core.md` "The look".
##
## [b]One shared material, bound only while visible[/b] (the InnerDisk
## pattern, `docs/domain/skillnode-visuals.md`): lobe count, seed and damage
## travel as `instance uniform`s, and binding the material is what claims an
## instance-uniform slot, so a cleared or sensed blob binds none.
##
## [b]Crack stage is combat PAINT, and under design B (#504) the model IS the
## presentation clock.[/b] A hit mutates the world at its own `arrival_time`
## (see [BeatClock]), so [method _on_damaged] — bound to the node's own
## `damaged` / `healed` — already fires exactly when the blob should
## visibly crack, with no view store in between. Crack stage ALSO lags one idle
## frame behind a FRESH allocation (see `_ready`'s docstring for why); that only
## delays picking up new ownership, never a mid-life damage tick.
##
## [b]Blocked is a LATCH, not a live predicate.[/b] The first entity to own
## this node (a blocker force-allocates its blocked node as its own core at
## spawn) is latched as `_latched_owner_id`; the node reads blocked for as long
## as [member SkillNode.owned_by] stays that entity. The instant ownership
## differs — including going back to null on the blocker's death — clearing is
## PERMANENT: a real entity re-allocating the node afterward must never
## re-show the blob, even though `owned_by` briefly equals a non-blocker
## entity that could otherwise look plausible. `owned_by.core_class == null`
## was considered and rejected as the predicate: it can't distinguish "still
## the original blocker" from "some other null-core actor", and it re-derives
## every read instead of remembering the one fact that actually matters (who
## owned this first).
##
## [b]The latch holds an instance ID, never an [Entity] reference.[/b] It used
## to hold the entity, and that was a real bug (#478 follow-up): GameRoot frees
## the corpse on `entity_death_shown`, and in Godot a freed Object compares
## EQUAL to null — so once the free beat the deferred `owner_changed` flush,
## `_latched_owner == null` read true and `_update_latch` took its
## "nothing latched yet" branch instead of its "ownership diverged" one.
## Clearing never happened, and the next entity to allocate the node (the one
## claiming the SkillDust relic the dead blocker dropped) RE-latched — the
## blob reappeared from under the loot the moment the loot was picked up.
## `get_instance_id()` is a never-reused int, so `cur_id != _latched_owner_id`
## stays a truthful comparison for the rest of the node's life. Note this is
## deliberately NOT [member Entity.entity_id]: that one is minted only on entry
## to a Graph's `entities_container` and reads 0 otherwise, so two unparented
## entities would compare equal.
##
## The core's look is not this script's business: a blocker entity's class is
## `blocker_core.tres`, whose `core_look` is the gear (`core_gear.tscn`), so a
## blocked node wears the gear and a cleared node re-owned by a player wears
## that player's class look — both through [method SkillNode._refresh_core_presence].
##
## Fog mirrors every other owner-detail on the node (the disk, the addons):
## hidden while [member SkillNode.sensed]. Resynced off the node's
## [signal SkillNode.sensed_changed] (plus one initial sync in `_ready`) —
## deliberately not a `_process` poll; `sensed` gained a signal specifically so
## fog-reactive visuals don't need one (#478).
##
## [b]Not [code]@tool[/code][/b] — unlike [CoreHealthBar] (which opts in for
## the editor-hosted Spell Playground), there's no editor-preview use case
## here worth the scene-baking hazard (`.claude/rules/godot-workflow.md`): an
## `@tool` `_ready` writing `visible` while `blocker_node.tscn` is open in the
## editor would get serialized back into the scene on save. Staying non-tool
## sidesteps that outright — the blob simply doesn't run until the scene is
## live in a real game/test tree.

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
