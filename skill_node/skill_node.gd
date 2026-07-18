@tool
class_name SkillNode
extends Area2D

const ZLayers = preload("res://ui/z_layers.gd")
# preload, not the bare class_name — parses before an editor class-cache
# refresh; see docs/domain/skillnode-emblem.md's "preload-not-class_name" note.
const EmblemSpec = preload("res://skill_node/visuals/emblem/emblem_spec.gd")
const ArchetypeShape = preload("res://skill_node/visuals/emblem/archetype_shape.gd")
const CarveShape = preload("res://skill_node/visuals/emblem/carve_shape.gd")
const EmblemResolver = preload("res://skill_node/visuals/emblem/emblem_resolver.gd")

signal radius_changed
signal owner_changed
signal archetype_changed
signal left_clicked(skill_node: SkillNode)
signal right_clicked(skill_node: SkillNode)
## Emitted on every take_damage call (even at 0 effective). Local twin of
## [signal Events.skill_node_damaged]; subscribe locally for per-node reactions
## (hit-flash lives right here), globally on the bus for UI like floating numbers.
signal damaged(amount: float, source: Variant)
## Emitted on every heal_damage call (even at 0 effective). Local twin of
## [signal Events.skill_node_damaged]; subscribe locally for per-node reactions
## (heal-flash lives right here)
signal healed(amount: float, source: Variant)
## Emitted when a non-core node's [member current_hp] reaches 0. Local twin of
## [signal Events.skill_node_depleted]; BattleSystem listens on the bus for the
## cascade dealloc.
signal depleted

# `owned_by` is the single source of truth for allocation:
# null  → unallocated
# !null → allocated
@export var owned_by: Entity = null:
	set(value):
		if owned_by == value:
			return
		owned_by = value
		owner_changed.emit()

## The modifier offerings this node carries — pushed onto an allocating
## entity's stat board by AllocationSystem. Node-level data, no behaviour.
@export var modifiers: Array[StatModifier] = []

## Special-effect content this node carries. Allocating grants its effects to
## the owner; deallocating revokes them. Placed by [KeystonePlacement].
@export var keystone: Keystone = null

## Effects granted directly by this node, independent of a keystone. The
## hand-authored escape hatch — most content should go through a [Keystone] or
## a [SkillNodeAddon].
@export var effects: Array[Effect] = []

## Hand-authoring quick-pick: which of [ArchetypeShape]'s fixed six shapes
## this node's archetype carves as the emblem fallback, when no
## [member carve_shape] override is stamped. See
## [method get_emblem_contributions] / docs/domain/skillnode-emblem.md.
@export var archetype: ArchetypeShape.Archetype = ArchetypeShape.Archetype.STR

## The resolved [CarveShape] this node's archetype actually carves, when set —
## WINS over [member archetype]. Procgen stamps this from the node's
## [ArchetypePolicy.carve_shape] (an open, content-defined shape, richer than
## the fixed six-way [member archetype] enum); null means "no policy stamped
## it", so hand-authored content (dev_sandbox, tests) keeps using the simple
## enum quick-pick instead. SkillNode never interprets what the shape IS
## (polygon vs. gem vs., later, arbitrary art) — it just holds the reference.
@export var carve_shape: CarveShape = null

## Persistent base-type identity colour (e.g. procgen's archetype colour).
## Drives the BaseCircle border; survives allocation. Defaults to dim grey so
## a hand-placed node in dev_sandbox.tscn looks the same as before any procgen
## stamping.
@export var base_type_color: Color = Color.DIM_GRAY:
	set(value):
		base_type_color = value
		archetype_changed.emit()
		if is_node_ready():
			_sync_visuals()

## Constant pixel inset from [member radius] to the rim's interior bevel
## control point (geom_crest_r). Kept small and constant so the rim width
## doesn't balloon when radius grows via stake.
const RIM_CREST_INSET := 4.0

@export var radius: float = 32.0:
	set(value):
		if is_equal_approx(radius, value):
			return
		radius = value
		radius_changed.emit()
		_sync_collision()
		_sync_visuals()

## Authored radius before stake scaling. Captured on first [_ready].
## Never write this directly — use [member radius] to set the base.
var _base_radius: float = -1.0

## Authored inner_radius before stake scaling. Captured on first [_ready].
var _base_inner_radius: float = -1.0

## Pixels of radius growth per additional stake level above 1.
## stake_level=1 → radius = base (no growth). stake_level=N → radius = base + (N-1) × delta.
@export var stake_radius_delta: float = 6.0:
	set(value):
		if is_equal_approx(stake_radius_delta, value):
			return
		stake_radius_delta = value
		_apply_stake_radius()

## Radius of the inner fill disk — what reads as "ownership" when allocated,
## and what VFX sizes effects against. Authored per-node so future archetypes
## can run flush (inner_radius == radius) or extra-recessed; pushed down to
## BaseCircle in _sync_visuals so BaseCircle has no inset policy of its own.
@export var inner_radius: float = 24.0:
	set(value):
		if is_equal_approx(inner_radius, value):
			return
		inner_radius = value
		_sync_visuals()

@export var self_loops: Array[Edge] = []

@onready var visuals: Node2D = $Visuals
@onready var hover_ring: Node2D = $Visuals/HoverRing
@onready var core_health_bar: CoreHealthBar = $Visuals/CoreHealthBar
@onready var _base_circle: Node2D = $Visuals/BaseCircle
@onready var _node_visuals: Node2D = $Visuals/NodeVisualsComposite
@onready var _addon_anchor: Node2D = $Visuals/AddonAnchor
@onready var _collision: CollisionShape2D = $CollisionShape2D

# Owner subscription tracking — re-bound whenever `owned_by` changes so the
# CoreMarker reflects the *current* owner's core_location, not a stale one.
var _bound_owner: Entity = null

## Sensed-but-not-visible flag, written by VisionSystem on every recompute.
## Drives the faint outline render on BaseCircle. Not a stat — purely a
## per-frame render hint, no signals, no persistence.
var sensed: bool = false:
	set(value):
		if sensed == value:
			return
		sensed = value
		_apply_sensed_state()

## Fully-visible flag, written by VisionSystem on every recompute (mirrors
## [member sensed], but for the "inside a vision radius" set rather than the
## "sensed-only blip" set). Fog gates readable detail — the core HP bar shows
## only when its node is actually revealed, not merely not-sensed (a fully-fogged
## node also has `sensed == false`, so `not sensed` would leak an enemy core's HP
## through darkness — #94). Defaults `true` so fog-less scenes/tests still read
## the bar. Not a stat — a per-frame render hint.
var revealed: bool = true:
	set(value):
		if revealed == value:
			return
		revealed = value
		_apply_sensed_state()

## Sparse [StatBoard] for per-node localized stats. All fields start null;
## a stat is only allocated when a node-local modifier targets it (via an
## addon) or when the node is allocated (combat health pool). See
## [method StatBoard._ensure_stat].
var node_board: StatBoard = null

## Per-node allocation cap. `stake_level` defaults to 1 (single allocation
## slot); raise by 1 per stake via the entity's `skill_points.stake(1)` action.
## `allocation_level` mirrors live allocation: 0 = unowned, 1 = baseline,
## 2+ = staked (e.g. stake_level=3 + allocation_level=1 reads as a 1/3 node).
## Pure node-local — these are not Stats and must never be registered with
## an entity StatBoard. If you want to scale modifier contributions by the
## stake count, read it directly off the SkillNode.
var stake_level: int = 1:
	set(value):
		if stake_level == value:
			return
		stake_level = value
		_apply_stake_radius()
		if is_node_ready():
			_sync_visuals()
var allocation_level: int = 0

# Track the entity node_health stat so we can re-sync the node's combat health
# base_value when the entity baseline changes. Swap on owner_changed.
var _bound_entity_node_health: Stat = null

# Hit-flash bookkeeping. Killed and re-created on every hit so back-to-back
# damage doesn't visually merge into one stuck red.
var _hit_flash_tween: Tween

# Denial-feedback bookkeeping (#89). Killed + reset on every trigger so spamming
# the deallocate key doesn't stack shakes / leave a stuck offset or tint.
var _feedback_tweens: Array[Tween] = []

var self_loop_count: int:
	get(): return self_loops.size()

func _ready() -> void:
	if _base_radius < 0.0:
		_base_radius = radius
		_base_inner_radius = inner_radius
	_sync_collision()
	# owned_by may already be non-null here — set as a scene-baked @export
	# (dev_sandbox.tscn's pre-owned nodes), which assigns the property (and
	# emits owner_changed into the void) before any listener is connected.
	# Refresh the derived allocation_level explicitly so the first
	# _sync_visuals below doesn't push a stale 0 into NodeVisualsComposite.
	_refresh_alloc_count()
	_sync_visuals()
	radius_changed.connect(_sync_visuals)
	# _refresh_alloc_count must run BEFORE _sync_visuals — the latter reads
	# allocation_level to push into NodeVisualsComposite, and connections fire
	# in connect() order.
	owner_changed.connect(_refresh_alloc_count)
	owner_changed.connect(_sync_visuals)
	owner_changed.connect(_refresh_core_presence)
	owner_changed.connect(_refresh_hp_binding)
	damaged.connect(play_hit_flash.unbind(2))
	_addon_anchor.child_entered_tree.connect(_on_addon_added)
	_addon_anchor.child_exiting_tree.connect(_on_addon_removed)
	_refresh_core_presence()
	_refresh_hp_binding()


func _refresh_core_presence() -> void:
	if _bound_owner != owned_by:
		if _bound_owner != null and _bound_owner.core_location_changed.is_connected(_refresh_core_presence):
			_bound_owner.core_location_changed.disconnect(_refresh_core_presence)
		_bound_owner = owned_by
		if _bound_owner != null:
			_bound_owner.core_location_changed.connect(_refresh_core_presence)
	var is_core := owned_by != null and owned_by.core_location == self
	# Gate the composite's core-only presence visuals (CorePresence: CoreHalos +
	# CoreSigilBloom, #128) to the one core node — otherwise every node draws a
	# gimbal (fps sink). `sensed` hiding the whole ShaderStack (CorePresence's
	# parent) is what keeps a fogged core hidden — no separate check needed here.
	if _node_visuals != null:
		_node_visuals.core_active = is_core
		var sigil: Sigil = null
		if is_core and owned_by.core_class != null:
			sigil = owned_by.core_class.sigil
		_node_visuals.set_core_sigil(sigil)
	_refresh_core_health_bar(is_core)


func _refresh_core_health_bar(is_core: bool) -> void:
	var pool: PoolStat = null
	if is_core and owned_by != null and owned_by.stat_board != null:
		pool = owned_by.stat_board.health
	core_health_bar.bind_health(pool)
	# Fog-gated: only a revealed core reads its HP (not a fogged/sensed one, #94).
	core_health_bar.visible = revealed and is_core


## Mirror the `sensed` flag onto the visual stack. Three things shift:
## the BaseCircle switches to its outline-only draw, the SkillNode is
## promoted above the fog overlay's z so the outline isn't dimmed into
## nothing, and owner/mechanic detail (core marker, addons) is hidden so
## a sensed-only viewer reads archetype only. The hide is a global
## placeholder — proper per-viewer info gating is the next layer up
## (see docs/domain/vision-system.md).
func _apply_sensed_state() -> void:
	if not is_node_ready():
		return
	# Sensed hides BaseCircle entirely — its wash carries the OWNER colour, which
	# must not leak through fog — and hands the archetype-only read to the
	# composite's own sensed state (SensedOutline), rather than the old "hide the
	# whole V2 stack and let BaseCircle stand in" path (#141).
	if _base_circle != null:
		_base_circle.visible = not sensed
	if _node_visuals != null:
		_node_visuals.sensed = sensed
	z_as_relative = not sensed
	z_index = ZLayers.GRAPH_DEFAULT + ZLayers.SENSED if sensed else 0
	# CorePresence needs no explicit hide here — it's nested under ShaderStack,
	# which `_node_visuals.sensed` above already hid wholesale.
	var _is_core := owned_by != null and owned_by.core_location == self
	core_health_bar.visible = revealed and _is_core
	for a in get_addons():
		a.visible = not sensed


func _sync_collision() -> void:
	if _collision == null or _collision.shape == null:
		return
	(_collision.shape as CircleShape2D).radius = radius


func _sync_visuals() -> void:
	if not is_node_ready():
		return
	# BaseCircle keeps only the faint always-on wash (legibility background for
	# unallocated nodes, per .claude/rules/skill-node-visuals.md) plus the
	# hit-flash / deny-tint channel — the sensed-fog outline moved onto the
	# composite's SensedOutline (#141), and NodeVisualsComposite (disk + rim +
	# rune/halo dress) is the real disk/allocation render.
	_base_circle._radius = radius
	_base_circle.fill_color = get_owner_color() if is_allocated() else Color.DIM_GRAY
	_base_circle.visible = not sensed
	_base_circle.queue_redraw()
	hover_ring.configure(radius)
	for a in get_addons():
		a.configure_visual(radius)
	_node_visuals.configure(radius)
	_node_visuals.geom_inner_r = inner_radius
	_node_visuals.geom_crest_r = radius - RIM_CREST_INSET
	_node_visuals.geom_outer_r = radius
	_node_visuals.entity_tint = get_owner_color()
	_node_visuals.archetype_tint = base_type_color
	_node_visuals.stake_level = stake_level
	_node_visuals.allocation_level = allocation_level
	_node_visuals.sensed = sensed
	_node_visuals.set_carve(EmblemResolver.resolve(get_emblem_contributions()).carve)


func is_allocated() -> bool:
	return owned_by != null


func is_core() -> bool:
	return owned_by != null and owned_by.core_location == self


func get_owner_color() -> Color:
	if owned_by:
		return owned_by.color
	return Color.WHITE


## World-space point on this node's perimeter facing [param world_target],
## plus optional [param extra_pad] outward. Use for projectile spawns,
## directional badges, or any anchor that should sit on the visible boundary.
func edge_point(world_target: Vector2, extra_pad: float = 0.0) -> Vector2:
	var dir := (world_target - global_position).normalized()
	return global_position + dir * (radius + extra_pad)


## Ring band convention (#67) — the single source of truth for how every
## decorative ring around a node expresses its span. A ring is a stroke of
## [param width] whose INNER edge sits [param inner_offset] outward from the
## node's canonical [member radius] (negative `inner_offset` insets the ring,
## so it lies inside the boundary). Returns the stroke CENTERLINE — the radius
## `draw_arc` / `draw_circle(..., filled=false, width)` actually want.
##   inner edge  = radius + inner_offset
##   outer edge  = radius + inner_offset + width
##   centerline  = radius + inner_offset + width / 2   ← returned
## `radius` itself is never redefined by this — it stays the collision /
## edge_point / blade-sim boundary; rings are purely relative to it. Filled
## discs (wash, inner disk) are NOT rings and don't use this. See
## `.claude/rules/skill-node-visuals.md` for the band table.
static func ring_centerline(node_radius: float, inner_offset: float, width: float) -> float:
	return node_radius + inner_offset + width / 2.0


## World-space pair `[start, end]` of a segment between [param a] and
## [param b], trimmed to each node's perimeter (plus [param pad] on each end).
## Returns an empty array when the nodes overlap so callers can early-out
## instead of drawing through each other. Static so it reads naturally at
## the call site: `SkillNode.segment_between(from, to)`.
static func segment_between(a: SkillNode, b: SkillNode, pad: float = 0.0) -> PackedVector2Array:
	if a == null or b == null:
		return PackedVector2Array()
	var pa := a.global_position
	var pb := b.global_position
	var delta := pb - pa
	var dist := delta.length()
	var trim_total: float = a.radius + b.radius + pad * 2.0
	if dist <= trim_total:
		return PackedVector2Array()
	var dir := delta / dist
	return PackedVector2Array([
		pa + dir * (a.radius + pad),
		pb - dir * (b.radius + pad),
	])


# ── Combat HP ──────────────────────────────────────────────────────────────

## Max combat HP for this node. Reads the node's [member node_board] combat
## health pool, which is seeded from the owning entity's [code]node_health[/code]
## baseline + any node-local modifiers. 0 if unallocated.
func get_max_hp() -> float:
	if node_board == null:
		return 0.0
	var hp := node_board.get_stat(&"node_health") as PoolStat
	if hp == null:
		return 0.0
	return hp.value


## Current combat HP for this node (ephemeral, from the pool's [member PoolStat.current]).
func get_current_hp() -> float:
	if node_board == null:
		return 0.0
	var hp := node_board.get_stat(&"node_health") as PoolStat
	if hp == null:
		return 0.0
	return hp.current


## Non-allocating passthrough read: returns the combined value of a stat
## visible to this node (entity board if owned, or StatRegistry default if
## orphaned). Does NOT create a stat on [member node_board] — use
## [method _ensure_local_stat] when you need a modifier target.
func get_local_value(stat_id: StringName) -> Variant:
	if owned_by != null and owned_by.stat_board != null:
		var es := owned_by.stat_board.get_stat(stat_id)
		if es != null:
			var ns: Stat = node_board.get_stat(stat_id) if node_board != null else null
			if ns == null:
				return es.get_value()
			var sources: Array[ModifierBins] = [es.bins, ns.bins]
			return ModifierBins.compute(es.base_value, sources)
	var ns: Stat = node_board.get_stat(stat_id) if node_board != null else null
	if ns != null:
		return ns.get_value()
	var def: StatDef = StatRegistry.get_def(stat_id)
	if def != null:
		return def.default_value
	return 0.0


## Returns (creating if necessary) the [code]node_board[/code] stat for
## [param stat_id]. This IS the modifier target — callers that just need a
## value should use [method get_local_value] instead, which does not allocate.
##
## When [param stat_id] is "node_health", a PoolStat is created (using the
## [code]node_combat_health[/code] PoolStatDef for its settings) instead of
## a ScalarStat — the entity board already owns the ScalarStat baseline;
## the node board needs the combat pool (max + current).
func _ensure_local_stat(stat_id: StringName) -> Stat:
	_init_node_board()
	if stat_id == &"node_health":
		var existing := node_board.get_stat(stat_id)
		if existing != null:
			return existing
		var def: StatDef = StatRegistry.get_def(&"node_combat_health")
		if def != null:
			var hp := PoolStat.new()
			hp.definition = def
			hp.base_value = def.default_value
			node_board._extra_stats[stat_id] = hp
			return hp
	return node_board._ensure_stat(stat_id)


#region Modifier plumbing
## Add an [b]entity-scoped[/b] modifier to this node: it joins [member modifiers]
## and, if the node is currently allocated, is mirrored onto the owner's stat
## board immediately. Deallocating strips it; reallocating re-applies it.
##
## This is the single path for entity-scoped node modifiers — addons, effects,
## and loot all route here rather than touching [member modifiers] plus the
## owner's board by hand. [AllocationSystem] drives the ownership transitions via
## [method apply_entity_modifiers_to] / [method remove_entity_modifiers_from].
func add_entity_modifier(m: StatModifier) -> void:
	if m == null:
		return
	modifiers.append(m)
	var board: StatBoard = owned_by.stat_board if owned_by != null else null
	if board != null:
		board.add_modifier(m)


## Remove an entity-scoped modifier added by [method add_entity_modifier],
## detaching it from the owner's board if allocated. Removal is by identity.
func remove_entity_modifier(m: StatModifier) -> void:
	if m == null:
		return
	modifiers.erase(m)
	var board: StatBoard = owned_by.stat_board if owned_by != null else null
	if board != null:
		board.remove_modifier(m)


## Mirror every entity-scoped modifier this node carries onto [param board].
## Called by [AllocationSystem] when the node becomes owned.
func apply_entity_modifiers_to(board: StatBoard) -> void:
	if board == null:
		return
	for m in modifiers:
		board.add_modifier(m)


## Strip this node's entity-scoped modifiers from [param board]. Called by
## [AllocationSystem] when the node stops being owned.
func remove_entity_modifiers_from(board: StatBoard) -> void:
	if board == null:
		return
	for m in modifiers:
		board.remove_modifier(m)


## Apply [param m] to this node's [member node_board] — a node-scoped modifier,
## never reaching the owning entity's board. The public target for [Effect]
## grants (via [method EffectContext.grant]) and for addon `local_modifiers`.
##
## Node-local values are read back with [method get_local_value], which merges
## the node's bins with the owner's through one [method ModifierBins.compute]
## without allocating.
##
## Note the modifier is NOT bound to the board (unlike [method StatBoard.add_modifier]),
## so a formula-driven node-local modifier will not track its source stats.
## No caller needs that today; it's the same contract addons have always had.
func add_local_modifier(m: StatModifier) -> void:
	if m == null:
		return
	# flatten() so a CompositeStatModifier lands its children on node_board;
	# a plain modifier is its own singleton. Mirrors StatBoard.add_modifier —
	# the node-local channel is bundle-aware too (#183). No bind, as before.
	for leaf in m.flatten():
		_ensure_local_stat(leaf.stat_id).add_modifier(leaf)


## Remove a modifier previously applied by [method add_local_modifier]. Removal
## is by object identity, so callers must hand back the same instance.
func remove_local_modifier(m: StatModifier) -> void:
	if m == null or node_board == null:
		return
	# Symmetric with add_local_modifier: flatten() returns the same stable child
	# instances, so a composite added earlier is removed leaf-for-leaf.
	for leaf in m.flatten():
		var s: Stat = node_board.get_stat(leaf.stat_id)
		if s != null:
			s.remove_modifier(leaf)


## Every [Effect] this node grants to an owner: its own, its keystone's, and
## any carried by its addons. [AllocationSystem] grants these on allocate and
## revokes them (keyed by this node) on deallocate.
func get_node_effects() -> Array[Effect]:
	var out: Array[Effect] = effects.duplicate()
	if keystone != null:
		out.append_array(keystone.effects)
	for a in get_addons():
		out.append_array(a.effects)
	return out
#endregion


func get_addons() -> Array[SkillNodeAddon]:
	var out: Array[SkillNodeAddon] = []
	if _addon_anchor == null:
		return out
	for c in _addon_anchor.get_children():
		if c is SkillNodeAddon:
			out.append(c)
	return out


## Defensive sharpness of this node — the spike magnitude an enemy melee blade
## vertex takes when it sweeps in (0 when unspiked). Sums every SpikeRingAddon's
## `damage` (one quantity drives both the offensive blade_damage and this
## defensive pop — see docs/design/skill_node_addons.md "Spikes"). Read by
## BladePopResolver during an attacker's swing resolution (#170).
func get_spike_power() -> float:
	var total := 0.0
	for a in get_addons():
		if a is SpikeRingAddon:
			total += (a as SpikeRingAddon).damage
	return total


## Tooltip sections contributed by attached addons. Each entry is
## `{ "title": String, "modifiers": Array[StatModifier] }`; SkillNodeTooltip
## renders them below the node's own modifier list. Addons opt in by overriding
## [method SkillNodeAddon.get_tooltip_modifiers] (e.g. SkillDust lists its loot
## payload). Addons that contribute nothing are skipped.
func get_addon_tooltip_sections() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for a in get_addons():
		var mods := a.get_tooltip_modifiers()
		if mods.is_empty():
			continue
		out.append({"title": a.get_tooltip_title(), "modifiers": mods})
	return out


## Aggregates this node's [EmblemSpec] candidates for the central-emblem
## resolver (see docs/domain/skillnode-emblem.md): the archetype fallback
## carve, a keystone carve, a SPELL carve per granted [SpellGrant], and every
## addon's own [method SkillNodeAddon.get_emblem] contribution. SkillNode never
## interprets these — [EmblemResolver] picks the winning CARVE and collects the
## BLOOMs; this is purely aggregation, mirroring [method get_node_effects] /
## [method get_addon_tooltip_sections].
##
## The archetype fallback prefers [member carve_shape] (procgen's real,
## content-defined shape) over the [member archetype] quick-pick enum — see
## both fields' docs.
func get_emblem_contributions() -> Array:
	var archetype_spec: EmblemSpec
	if carve_shape != null:
		archetype_spec = carve_shape.carve(EmblemSpec.PRIORITY_ARCHETYPE, &"archetype")
	else:
		archetype_spec = ArchetypeShape.carve(archetype)
	var out: Array = [archetype_spec]
	if keystone != null:
		out.append(EmblemSpec.texture_carve(keystone.icon, EmblemSpec.PRIORITY_KEYSTONE, &"keystone"))
	for effect in get_node_effects():
		if effect is SpellGrant and effect.spell_def != null:
			out.append(EmblemSpec.texture_carve(effect.spell_def.icon, EmblemSpec.PRIORITY_SPELL, &"spell"))
	for a in get_addons():
		var spec = a.get_emblem()
		if spec != null:
			out.append(spec)
	return out


## Reset node combat health to full. Called on allocation (silent) and at
## turn-start upkeep (not silent — emits healed signal).
func refill(silent: bool = false) -> void:
	var hp := node_board.get_stat(&"node_health") as PoolStat if node_board != null else null
	if hp == null:
		return
	var prev := hp.current
	hp.restore_to_full()
	if not silent:
		var delta := hp.current - prev
		if delta > 0.0:
			healed.emit(delta, null)
			Events.skill_node_healed.emit(self, delta, null)


## Apply an incoming hit. Mitigation runs here so attackers don't need to know
## about defender stats; node soaks first, overflow eats core HP iff this is
## the owner's core node. Emits [signal damaged] (and re-emits on the global
## bus) so UI hooks fire even when 0 damage lands.
func take_damage(amount: float, source: Variant) -> void:
	if owned_by == null or amount <= 0.0:
		return
	var raw: DamageInstance
	if source is DamageInstance:
		raw = source
	else:
		raw = DamageInstance.new()
		raw.amount = amount
	# Node-local: `armor` / `min_damage_taken` merge this node's board with its
	# owner's, so addon + aura defensive modifiers actually land.
	var effective: float = Mitigation.apply(raw, self)
	var hp := node_board.get_stat(&"node_health") as PoolStat if node_board != null else null
	if hp == null:
		return
	var before := hp.current
	hp.deplete(effective)
	var soaked: float = before - hp.current
	damaged.emit(effective, source)
	Events.skill_node_damaged.emit(self, effective, source)
	# Post-mitigation amount, so a defensive effect reacts to what actually landed.
	owned_by.dispatch(&"_on_node_damaged", [self, effective])
	var overflow: float = effective - soaked
	if owned_by.core_location == self:
		if overflow > 0.0 and owned_by.stat_board != null and owned_by.stat_board.health != null:
			owned_by.stat_board.health.deplete(overflow)
		return
	if hp.current <= 0.0:
		depleted.emit()
		Events.skill_node_depleted.emit(self)

## Restore HP by [param amount], clamped at max. Emits [signal healed] (and
## re-emits on the global bus) with the effective delta actually restored.
func heal_damage(amount: float, source: Variant) -> void:
	if owned_by == null or amount <= 0.0:
		return
	var hp := node_board.get_stat(&"node_health") as PoolStat if node_board != null else null
	if hp == null:
		return
	var prev := hp.current
	hp.set_current(min(hp.current + amount, hp.value))
	var effective := hp.current - prev
	if effective > 0.0:
		healed.emit(effective, source)
		Events.skill_node_healed.emit(self, effective, source)

# ── Internals ──────────────────────────────────────────────────────────────


func _refresh_hp_binding() -> void:
	# Detach from previous owner's node_health; attach to the new owner's.
	if _bound_entity_node_health != null and _bound_entity_node_health.value_changed.is_connected(_on_entity_node_health_changed):
		_bound_entity_node_health.value_changed.disconnect(_on_entity_node_health_changed)
		_bound_entity_node_health = null
	if owned_by != null and owned_by.stat_board != null:
		_init_node_board()
		_bound_entity_node_health = owned_by.stat_board.get_stat(&"node_health")
		if _bound_entity_node_health != null:
			if not _bound_entity_node_health.value_changed.is_connected(_on_entity_node_health_changed):
				_bound_entity_node_health.value_changed.connect(_on_entity_node_health_changed)
			# Sync our combat health pool's base_value to the entity baseline.
			_sync_combat_health_base()
		refill(true)
	else:
		_reset_combat_health()


func _on_entity_node_health_changed() -> void:
	_sync_combat_health_base()


func _sync_combat_health_base() -> void:
	if _bound_entity_node_health == null:
		return
	var hp := _ensure_local_stat(&"node_health") as PoolStat
	if hp == null:
		return
	hp.base_value = _bound_entity_node_health.get_value()


func _reset_combat_health() -> void:
	var hp := node_board.get_stat(&"node_health") as PoolStat if node_board != null else null
	if hp != null:
		hp.set_current(0.0)


func _init_node_board() -> void:
	if node_board == null:
		node_board = StatBoard.new()


func _refresh_alloc_count() -> void:
	if owned_by == null:
		allocation_level = 0
	elif allocation_level == 0:
		allocation_level = 1


func _apply_stake_radius() -> void:
	if not is_inside_tree():
		return
	if _base_radius < 0.0:
		return
	var growth := (stake_level - 1) * stake_radius_delta
	radius = _base_radius + growth
	inner_radius = _base_inner_radius + growth


# Addon plumbing. Carrier owns its `modifiers` array as the source-of-truth
# for AllocationSystem, so addons mutate it directly here (append/erase).
# While allocated we also push/pop live on the entity board so the effect
# is immediate — same StatModifier instance, no double-pop because
# AllocationSystem iterates the (now-updated) array on dealloc.
func _on_addon_added(c: Node) -> void:
	if not (c is SkillNodeAddon):
		return
	var a := c as SkillNodeAddon
	if a.unique:
		for existing in get_addons():
			if existing != a and existing.get_script() == a.get_script():
				push_error("Duplicate unique addon %s on %s; rejecting." % [a.get_script().resource_path, name])
				a.queue_free()
				return
	for m in a.entity_modifiers:
		add_entity_modifier(m)
	for m in a.get_local_modifiers():
		add_local_modifier(m)
	a.visible = not sensed
	_sync_visuals()


func _on_addon_removed(c: Node) -> void:
	if not (c is SkillNodeAddon):
		return
	var a := c as SkillNodeAddon
	for m in a.entity_modifiers:
		remove_entity_modifier(m)
	for m in a.get_local_modifiers():
		remove_local_modifier(m)


## Core-movement slide-in (#21, #128). Called on the *new* core slot after
## AllocationSystem.move_core commits; retargets the old CoreMarker glide onto
## [CorePresence] (CoreHalos + CoreSigilBloom) — the halo offsets to the
## previous slot's world position and tweens back to local zero, while the
## bloom extinguishes for the travel and bursts back in on arrival (see
## core_presence.gd). The underlying `core_location` has already flipped (and
## `core_active`/the sigil were refreshed) — this is purely the visual
## catch-up. No-op if this isn't actually the core node, it's sensed (its
## whole ShaderStack — and CorePresence with it — is hidden), or the offset is
## degenerate (same node).
func play_core_slide_from(world_pos: Vector2, duration: float = 0.25) -> void:
	if not is_node_ready() or not is_core() or sensed:
		return
	var offset := world_pos - global_position
	if offset.is_zero_approx():
		return
	_node_visuals.glide_core_presence(offset, duration)


## Brief white pulse on the BaseCircle. Auto-runs on the `damaged` signal;
## also callable externally (FloatingNumberLayer triggers it on wound/heal
## events so the core flashes alongside the floater).
func play_hit_flash() -> void:
	if _base_circle == null:
		return
	if _hit_flash_tween != null:
		_hit_flash_tween.kill()
	# Tweens BaseCircle.flash_amount only — leaves visuals.modulate free for
	# other consumers (selection tint, status effects, etc.) without colliding.
	_base_circle.flash_amount = 1.0
	_hit_flash_tween = create_tween()
	_hit_flash_tween.tween_property(_base_circle, "flash_amount", 0.0, 0.25)


# ── Denial feedback (#89) ────────────────────────────────────────────────────
# Two registers for a rejected deallocation, driven by PlayerInputController:
# the nodes that WOULD be islanded pulse danger-red (blink_blocked); the node
# the player actually tried to drop gets a short "bzzt — no" shake (shake_denied).
#
# The red tint lands on `_base_circle` (the node body), NOT on `visuals` — the
# hover glow (HoverRing) is a child of `visuals`, so a `visuals.modulate` tint
# multiplied the glow down to near-black and read as "the glow vanished". Body
# tint keeps the hover register (a different visual meaning: "pointer is here")
# clean. The shake offsets `visuals.position` (edges anchor on the node root, so
# endpoints don't move); the hover glow is counter-translated to stay world-fixed
# — the pointer isn't shaking, so its feedback shouldn't either.

const _DENY_COLOR := Color(1.0, 0.3, 0.3)
const _BLINK_STEP := 0.11
const _SHAKE_TIME := 0.30
const _SHAKE_AMPLITUDE := 5.0


func _reset_feedback() -> void:
	for t in _feedback_tweens:
		if t != null and t.is_valid():
			t.kill()
	_feedback_tweens.clear()
	if visuals != null:
		visuals.position = Vector2.ZERO
	if hover_ring != null:
		hover_ring.position = Vector2.ZERO
	if _base_circle != null:
		_base_circle.modulate = Color.WHITE


## Danger-red pulse — marks a node that a denied deallocation would island (#89).
func blink_blocked() -> void:
	if not is_node_ready() or _base_circle == null:
		return
	_reset_feedback()
	var t := create_tween()
	for i in 2:
		t.tween_property(_base_circle, "modulate", _DENY_COLOR, _BLINK_STEP)
		t.tween_property(_base_circle, "modulate", Color.WHITE, _BLINK_STEP)
	_feedback_tweens.append(t)


## Short "bzzt — no" shake + red tint — the node the player tried but failed to
## deallocate (#89). Horizontal decaying jitter on the body; hover glow held put.
func shake_denied() -> void:
	if not is_node_ready() or visuals == null:
		return
	_reset_feedback()
	if _base_circle != null:
		_base_circle.modulate = _DENY_COLOR
		var tint := create_tween()
		tint.tween_property(_base_circle, "modulate", Color.WHITE, _SHAKE_TIME)
		_feedback_tweens.append(tint)
	var shake := create_tween()
	var amps := [1.0, -0.72, 0.5, -0.32, 0.16, 0.0]
	var step := _SHAKE_TIME / float(amps.size())
	for a in amps:
		var off := Vector2(a * _SHAKE_AMPLITUDE, 0.0)
		shake.tween_property(visuals, "position", off, step).set_trans(Tween.TRANS_SINE)
		if hover_ring != null:
			shake.parallel().tween_property(hover_ring, "position", -off, step).set_trans(Tween.TRANS_SINE)
	_feedback_tweens.append(shake)


func _on_mouse_entered() -> void:
	hover_ring.show()
	if not Engine.is_editor_hint():
		Events.skill_node_hovered.emit(self)


func _on_mouse_exited() -> void:
	hover_ring.hide()
	if not Engine.is_editor_hint():
		Events.skill_node_unhovered.emit()


func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			return
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				left_clicked.emit(self)
			MOUSE_BUTTON_RIGHT:
				right_clicked.emit(self)
