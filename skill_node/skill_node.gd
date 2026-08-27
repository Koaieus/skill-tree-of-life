@tool
class_name SkillNode
extends Area2D

const ZLayers = preload("res://ui/z_layers.gd")
# preload, not the bare class_name — parses before an editor class-cache
# refresh; see docs/domain/skillnode-emblem.md's "preload-not-class_name" note.
@warning_ignore("shadowed_global_identifier")
const EmblemSpec = preload("res://skill_node/visuals/emblem/emblem_spec.gd")
@warning_ignore("shadowed_global_identifier")
const EmblemResolver = preload("res://skill_node/visuals/emblem/emblem_resolver.gd")

signal radius_changed
signal owner_changed
signal archetype_changed
## Emitted at the end of [method _apply_sensed_state], after `sensed` (or
## `revealed`) has already been mirrored onto the visual stack — lets a
## fog-reactive visual (e.g. [BlockerVisual], #478) re-sync off a signal
## instead of polling [member sensed] every frame. `_apply_sensed_state` fires
## for either flag changing, and early-returns before `is_node_ready()`, so a
## pre-ready sensed/revealed write never emits this.
signal sensed_changed
## Emitted after `_addons` gains or loses a member (never on a rejected
## duplicate-unique attach, which returns before mutating the ledger) — see
## `_attach_addon`/`_detach_addon`. Lets a listener (e.g. `Edge`, for
## ClampAddon's edge-width gradient, #455) react without polling `get_addons()`.
signal addons_changed
signal left_clicked(skill_node: SkillNode)
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
# TODO(#336): remove. A `Keystone` is to come to mean 'hand authored (inherited) .tscn which
#				carries the baked-in modifiers/visuals/addons', instead of a Resource mirroring a
#				subset of SkillNode's own authoring surface and stamping itself on. See the hub
#				for the three open forks (carve home, tooltip predicate, placement surface).
@export var keystone: Keystone = null

## Effects granted directly by this node, independent of a keystone. The
## hand-authored escape hatch — most content should go through a [Keystone] or
## a [SkillNodeAddon].
@export var effects: Array[Effect] = []

## This node's archetype identity — carries the primary stat, colour, and
## central-emblem [CarveShape] (see [Archetype]). Procgen stamps this from the
## node's [ArchetypePolicy.archetype]; null means no policy stamped one (e.g.
## dev_sandbox nodes not wired to an archetype), and the node's emblem
## contributes no archetype carve at all. See
## [method get_emblem_contributions] / docs/domain/skillnode-emblem.md.
@export var archetype: Archetype = null:
	set(value):
		if archetype == value:
			return
		archetype = value
		archetype_changed.emit()
		if is_node_ready():
			_sync_visuals()

## Persistent base-type identity colour (e.g. procgen's archetype colour).
## Drives NodeVisualsComposite's `archetype_tint` (rim, sensed outline);
## survives allocation. Defaults to dim grey so a hand-placed node in
## dev_sandbox.tscn looks the same as before any procgen stamping.
@export var base_type_color: Color = Color.DIM_GRAY:
	set(value):
		base_type_color = value
		archetype_changed.emit()
		if is_node_ready():
			_sync_visuals()

@export_tool_button('Load color from Archetype', 'ColorPickerButton') var _color_load_button = _load_type_color_from_archetype

## Constant pixel inset from [member radius] to the rim's interior bevel
## control point (geom_crest_r). Kept small and constant so the rim width
## doesn't balloon when radius grows via stake.
const RIM_CREST_INSET := 4.0

## THE authored size knob — the node's outer radius at `stake_level == 1`.
## [member radius] is DERIVED from this plus stake growth and is read-only;
## anything that wants to resize a node writes here.
##
## Why the split: this class is `@tool`, so if stake growth wrote back into an
## exported `radius` the editor would serialize the GROWN value into the
## `.tscn` — and the next load would grow it again from there, compounding on
## every save. Keeping the authored value and the derived value in separate
## properties, with only the authored one exported, makes that impossible
## rather than merely unlikely.
@export var base_radius: float = 32.0:
	set(value):
		if is_equal_approx(base_radius, value):
			return
		base_radius = value
		_refresh_radius()

## Authored radius of the inner fill disk at `stake_level == 1` — what reads as
## "ownership" when allocated, and what VFX sizes effects against. Authored per
## node so future archetypes can run flush (inner == outer) or extra-recessed;
## pushed down to NodeVisualsComposite.geom_inner_r in _sync_visuals. Same
## authored/derived split as [member base_radius] → [member radius].
@export var base_inner_radius: float = 24.0:
	set(value):
		if is_equal_approx(base_inner_radius, value):
			return
		base_inner_radius = value
		_refresh_radius()

## Pixels of radius growth per additional stake level above 1.
## stake_level=1 → radius = base (no growth). stake_level=N → radius = base + (N-1) × delta.
@export var stake_radius_delta: float = 6.0:
	set(value):
		if is_equal_approx(stake_radius_delta, value):
			return
		stake_radius_delta = value
		_refresh_radius()

## Live outer radius, INCLUDING stake growth. Read-only and never serialized —
## a pure function of [member base_radius], [member stake_level] and
## [member stake_radius_delta]. Gameplay geometry (the collision shape, reach
## queries, VFX sizing) reads this; nothing writes it.
var radius: float:
	get: return base_radius + _stake_growth()

## Live inner-disk radius, including stake growth. Read-only, see [member radius].
var inner_radius: float:
	get: return base_inner_radius + _stake_growth()

## Overrides which [CoreHalos] preset a core node wears — `-1` (Default) means
## "whatever core_presence.tscn authored" (today: GIMBAL), so leaving this
## alone changes nothing for any existing node. Forwarded alongside
## `core_active` / the sigil in [method _refresh_core_presence]; routes down
## through [method NodeVisualsComposite.set_core_halo_style] rather than
## reaching past it into CorePresence/CoreHalos by path (those live inside a
## nested instanced scene, see .claude/rules/scene-composition.md).
##
## Exists for removable blockers (#478): GIMBAL is a 28-segment
## quaternion-chained hoop stack redrawn every `_process` tick — more than a
## handful on screen tanks fps (see .claude/rules/skill-node-scale.md), and a
## level can spawn several blockers. `blocker_node.tscn` pins this to COG (a
## `draw_circle` + 10 `draw_line`s, ~two orders of magnitude cheaper) so a
## blocked node's core presence stays active — machinery/obstacle is the right
## read for a blocker anyway — without paying gimbal cost per instance. The
## `int` + `@export_enum` shape (not a typed enum) matches [CoreHalos] itself,
## which deliberately carries no `class_name` (see skill-node-visuals.md).
##
## The setter re-runs [method _refresh_core_presence] itself (guarded on
## `is_node_ready()`, same guard every other re-syncing setter in this file
## uses pre-`_ready`) — a write at ANY time re-syncs the live halo, so a caller
## (e.g. [BlockerVisual] toggling this on latch/clear) never has to race
## `SkillNode`'s own `owner_changed` connection order the way an unsynced flag
## would. That is what let [BlockerVisual]'s crack-stage refresh be the ONLY
## `owner_changed` listener that still needs `CONNECT_DEFERRED` — see its
## `_ready` docstring, which reads combat HP and genuinely does need
## `_refresh_hp_binding` to have already run.
@export_enum("Default:-1", "None:0", "Rings:1", "Orbit:2", "Gimbal:3", "Cog:4")
var core_halo_style: int = -1:
	set(value):
		if core_halo_style == value:
			return
		core_halo_style = value
		if is_node_ready():
			_refresh_core_presence()

@export var self_loops: Array[Edge] = []

@onready var visuals: Node2D = $Visuals
@onready var hover_ring: Node2D = $Visuals/HoverRing
@onready var core_health_bar: CoreHealthBar = $Visuals/CoreHealthBar
@onready var _node_visuals: Node2D = $Visuals/NodeVisualsComposite
@onready var _collision: CollisionShape2D = $CollisionShape2D

## Attached addons, in child order — the ledger that makes attach/detach
## idempotent (#334). NOT merely a cache of a child scan: a SkillNode
## re-entering the tree re-fires `child_entered_tree` for every existing child,
## so membership here (not call ordering) is what decides whether an addon's
## modifiers still need transferring. See .claude/rules/skill-node-addons.md.
var _addons: Array[SkillNodeAddon] = []

# Owner subscription tracking — re-bound whenever `owned_by` changes so the
# CoreMarker reflects the *current* owner's core_location, not a stale one.
var _bound_owner: Entity = null

## Canonical ledger of node-LOCAL modifiers (addons, direct grants, effect
## node-grants) — the complement of [member modifiers] (entity-scoped). Kept
## as the PARENT instances (composites stay whole) so the local-scale mutator
## (#376) can walk the walk and consult each parent's override. Populated by
## [method add_local_modifier] / emptied by [method remove_local_modifier].
var _local_modifiers: Array[StatModifier] = []

## [b]Two of the four ledgers this comment used to describe are gone — see
## #377.[/b] `_addon_local_clones` / `_addon_entity_clones` existed because a
## `.tscn`-instantiated addon's `local_modifiers` / `entity_modifiers` were
## Godot-cached sub-resources shared across every `instantiate()` of that
## scene; the local-scale mutator's `value` writes would have leaked across
## carriers. Fixed at the source instead of worked around: every addon
## `.tscn` carrying a `StatModifier` sub-resource now sets
## `resource_local_to_scene = true` (see docs/domain/resource-local-to-scene.md),
## so each instantiation already gets its own private copy — `_attach_addon` /
## `_detach_addon` route `a.get_local_modifiers()` / `a.entity_modifiers`
## straight through, no clone, no ledger.
##
## The two below are NOT a binding-state artifact and #377 does not remove
## them — they're composition bookkeeping for the local-scale mutator's
## Array-override path (#376 decision 8), independent of how a modifier binds
## to a board. Killing these needs #376's swap-the-active-leaf-set mechanism
## itself to change (always-live leaves + a read-time scale factor instead);
## that's a separate, unstarted redesign — see the #377 backlog follow-up.

## Composition-swap ledger (#376, decision 8): parent modifier -> the scaled
## leaf-set currently applied in its place on its contribution board. Only
## populated while an override returns an Array; the value path is drift-free
## by construction and keeps no state.
var _scaled_sets: Dictionary[StatModifier, Array] = {}

## Same ledger for the effect path: effect -> scaled leaf-set applied in
## place of the effect's granted modifiers on the entity board.
var _scaled_effect_sets: Dictionary[Effect, Array] = {}

## Old fill for the mutator's (old_al, new_al) pair — PoolStat.current_changed
## only carries the new value.
var _last_allocation_level: int = 0

## Sensed-but-not-visible flag, written by VisionSystem on every recompute.
## Drives NodeVisualsComposite's archetype-only outline (SensedOutline, #141).
## Not a stat — purely a per-frame render hint, no signals, no persistence.
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

## This node's [NodeStatBoard]. Authored here (the scene wires
## [constant DEFAULT_NODE_BOARD]) and DEEP-CLONED at init, exactly like
## [member Entity.stat_board] — so a level, cluster or single node may compose
## its own board, and a saved level serializes real per-node stat state rather
## than losing it.
##
## Node-only stats it OWNS (`stake_level`, `addon_slots`) arrive baked and
## authorable; every stat it BORROWS from its owner (`armor`, `node_healing`, …)
## stays sparse and is minted only when a node-local modifier targets it. See
## [NodeStatBoard] for why the split falls along that line.
##
## Writing the clone back into this `@export` is safe because `duplicate(true)`
## is IDEMPOTENT — the derived-value-writeback hazard needs a *transforming*
## function, and a deep copy round-trips to the same values. What is NOT safe is
## treating non-null as "already initialized": a scene-authored board would then
## skip [method StatBoard.apply_intrinsics] forever and `addon_slots` would
## silently stop tracking allocation level. [member _node_board_ready] separates
## "authored" from "initialized"; Entity gets the same property for free by
## running its init exactly once in `_ready`.
const DEFAULT_NODE_BOARD: NodeStatBoard = preload("res://skill_node/default_node_board.tres")

## Assigning this ALWAYS resets [member _node_board_ready] — the property means
## "here is the authored board", so a fresh one (or `null`, which sandboxes use
## to make a board-less node) must be re-cloned and re-wired on next need
## instead of inheriting the previous board's initialization. Self-assignment
## inside a setter does not recurse in Godot 4; [method _init_node_board] relies
## on that and re-raises the flag after its own write.
@export var node_board: NodeStatBoard = null:
	set(value):
		node_board = value
		_node_board_ready = false

## True once [method _init_node_board] has cloned + wired the board. NOT the
## same question as `node_board != null` — see the note above.
var _node_board_ready: bool = false

## Refcounted status markers ("poisoned", "lifeline", ...) — the non-numeric
## sibling to [member node_board]. See docs/design/status-tags.md. Sparse:
## an entry exists only while at least one source has granted it. Refcounted,
## not a bool, because multiplicity is real — two effects granting the same
## tag must both need to revoke before it clears. Granted/revoked through
## [method EffectContext.grant_tag] / `revoke`, never written to directly.
var _tags: Dictionary[StringName, int] = {}

## Per-node allocation cap — the N in the M/N dial, and `.max` of the
## node-board `stake_level` PoolStat (the baked [member NodeStatBoard.stake_level]).
## `allocation_level` is that pool's `.current`: 0 = unowned, 1 = baseline,
## 2+ = staked (e.g. stake_level=3 + allocation_level=1 reads as a 1/3 node).
## The pool's clamp is the single guard that keeps fill ≤ cap (#374).
##
## These two are PROXY properties over the node-board pool: authors stay at
## SkillNode scope, the pool is minted by [method _init_node_board], and each
## setter pushes its backing field into it. A setter can run pre-`_ready`
## (scene instantiation, in-editor authoring) when the board does not exist
## yet — the backing field holds the authored value until the board
## materializes and the mint pushes both through. Once the pool exists its
## GETTERS read it back, so the pool's clamp and any cap modifiers stay
## authoritative. `duplicate(true)` round-trips them the same way.
##
## Exported so it's authorable (and previewable) in the inspector — a staked
## node is content, not just runtime state. Safe to serialize precisely because
## [member radius] is derived rather than written back; see [member base_radius].
## Pure node-local — never registered with an entity StatBoard.
@export_range(1, 4, 1, "or_greater") var stake_level: int:
	get:
		return int(node_board.stake_level.value) if _node_board_ready else _stake_level_backing
	set(value):
		if stake_level == value:
			return
		_stake_level_backing = value
		_push_stake_level()
		_refresh_radius()
var _stake_level_backing: int = 1

## Per-node allocation fill — the M in M/N. 0 = unowned, 1 = baseline,
## 2+ = staked. Mirrors `stake_level` PoolStat.current; the pool's clamp
## keeps it ≤ the cap and is authoritative once minted. Exported like
## [member stake_level] so scene inheritance / `duplicate(true)` round-trips
## an authored fill (runtime state that IS worth authoring — a pre-staked
## node is content, same as a pre-staked cap).
@export var allocation_level: int:
	get:
		return int(node_board.stake_level.current) if _node_board_ready else _allocation_level_backing
	set(value):
		if allocation_level == value:
			return
		_allocation_level_backing = value
		_push_allocation_level()
		if is_node_ready():
			_sync_visuals()
var _allocation_level_backing: int = 0

## Consecutive turns this node has regenerated without taking damage, feeding
## `node_healing_ramp` (D-9). Runtime state, not a stat — same rationale as
## node HP itself: see docs/domain/node-hp.md. Reset to 0 on damage taken and
## on reaching full HP; incremented by [method apply_turn_regen] each time it
## grants a ramped heal.
var regen_stacks: int = 0

## Set by [method take_damage] whenever a hit actually reduces this node's
## HP; cleared by [method apply_turn_regen]. Gates the D-9 base heal — a node
## hit since its last upkeep gets no base heal this turn and its ramp resets.
var _damaged_since_upkeep: bool = false

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

## Assigned once by [method Graph._ensure_topology] the first time this node
## is indexed — stable across a removal reshuffling the container's child
## order. 0 means unassigned. Plain var, not @export: it's Graph-assigned
## runtime identity, not authored content — see .claude/rules/gdscript-pitfalls.md
## on never writing a derived value back into an @export.
var stable_id: int = 0

## The live combat-state slice (#498 step 1, docs/domain/attack-timeline.md).
## SkillNode COMPOSES this — it owns the live one, it does not copy one.
## Constructed here (a field initializer, not `_ready`) so it exists for a
## pre-`_ready` scene-authored write, same reasoning as [member _addons].
var _combat := NodeCombat.new(self)


## Public accessor for [member _combat] (#498 step 2) — [EntityCombat.snapshot]
## needs it to build a shadow's owned [NodeCombat] set from the real navigator
## mirror; a plain getter keeps `_combat` itself construction-assigned with no
## public setter. Mirrors [method Entity.get_combat].
func get_combat() -> NodeCombat:
	return _combat


func _ready() -> void:
	# No authored-radius capture here any more: `radius` is a getter over
	# `base_radius` + stake growth, so it's correct from construction onward —
	# including for a `stake_level` set before the node entered the tree, which
	# the old capture-then-apply scheme silently dropped.
	_sync_collision()
	# The node board (and with it the stake pool) materializes lazily — via
	# _refresh_hp_binding below when owned, or _ensure_local_stat /
	# add_local_modifier on first need. Authored pre-_ready stake_level /
	# allocation_level sit in their backing fields until then and are pushed
	# into the pool when the board clones (see _init_node_board).
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
	damaged.connect(_on_damaged_flash.unbind(2))
	# Addons are plain direct children (#334) — no filing bin. Adopt the ones
	# already present (scene-authored, or parented before we entered the tree),
	# then listen for later arrivals. `child_entered_tree` fires for DIRECT
	# children only — verified empirically, a grandchild never fires it — which
	# is what makes the type filter a sufficient contract.
	for c in get_children():
		if c is SkillNodeAddon:
			_attach_addon(c)
	child_entered_tree.connect(_on_addon_added)
	child_exiting_tree.connect(_on_addon_removed)
	_refresh_core_presence()
	_refresh_hp_binding()
	_sync_visuals()


func _refresh_core_presence() -> void:
	if _bound_owner != owned_by:
		if _bound_owner != null and _bound_owner.core_location_changed.is_connected(_refresh_core_presence):
			_bound_owner.core_location_changed.disconnect(_refresh_core_presence)
		_bound_owner = owned_by
		if _bound_owner != null:
			_bound_owner.core_location_changed.connect(_refresh_core_presence)
	var _is_core := owned_by != null and owned_by.core_location == self
	# Gate the composite's core-only presence visuals (CorePresence: CoreHalos +
	# CoreSigilBloom, #128) to the one core node — otherwise every node draws a
	# gimbal (fps sink). `sensed` hiding the whole ShaderStack (CorePresence's
	# parent) is what keeps a fogged core hidden — no separate check needed here.
	if _node_visuals != null:
		_node_visuals.core_active = _is_core
		var sigil: Sigil = null
		if _is_core and owned_by.core_class != null:
			sigil = owned_by.core_class.sigil
		_node_visuals.set_core_sigil(sigil)
		_node_visuals.set_core_halo_style(core_halo_style)
	_refresh_core_health_bar(_is_core)


func _refresh_core_health_bar(_is_core: bool) -> void:
	var pool: PoolStat = null
	if _is_core and owned_by != null and owned_by.stat_board != null:
		pool = owned_by.stat_board.health
	core_health_bar.bind_health(pool)
	# Fog-gated: only a revealed core reads its HP (not a fogged/sensed one, #94).
	core_health_bar.visible = revealed and _is_core


## Mirror the `sensed` flag onto the visual stack. Three things shift:
## NodeVisualsComposite switches to its archetype-only outline draw
## (SensedOutline, #141), the SkillNode is promoted above the fog overlay's z
## so the outline isn't dimmed into nothing, and owner/mechanic detail (core
## marker, addons) is hidden so a sensed-only viewer reads archetype only. The
## hide is a global placeholder — proper per-viewer info gating is the next
## layer up (see docs/domain/vision-system.md).
func _apply_sensed_state() -> void:
	if not is_node_ready():
		return
	if _node_visuals != null:
		_node_visuals.sensed = sensed
	z_as_relative = not sensed
	z_index = ZLayers.GRAPH_DEFAULT + ZLayers.SENSED if sensed else 0
	# CorePresence needs no explicit hide here — it's nested under ShaderStack,
	# which `_node_visuals.sensed` above already hid wholesale.
	var _is_core := owned_by != null and owned_by.core_location == self
	core_health_bar.visible = revealed and _is_core
	for a in _addons:
		a.visible = not sensed
	sensed_changed.emit()


func _sync_collision() -> void:
	if _collision == null or _collision.shape == null:
		return
	(_collision.shape as CircleShape2D).radius = radius

func _load_type_color_from_archetype() -> void:
	if not archetype:
		push_warning('Cannot load color: No archetype!')
		return
	if not node_board:
		push_warning('Cannot load color: No stat board!')
		return
	var def: StatDef = StatRegistry.get_def(archetype.primary_stat)
	if def != null:
		base_type_color = def.tint_color
		notify_property_list_changed()
	else:
		push_warning('Stat not found: %s' % archetype.primary_stat)
	

func _current_node_hp() -> float:
	var hp := node_board.get_stat(&"node_health") as PoolStat if _node_board_ready else null
	return hp.current if hp != null else 0.0


func _on_damaged_flash() -> void:
	play_hit_flash()


func _sync_visuals() -> void:
	if not is_node_ready():
		return

	# NodeVisualsComposite (disk + rim + rune/halo dress) is the whole
	# disk/allocation render (#304) — InnerDisk and RimRing both draw opaquely
	# across their full band regardless of allocation (dark dome / dim silver
	# rim when unallocated), so an unallocated node already reads as a
	# footprint with no separate wash layer needed. The sensed-fog outline is
	# the composite's own SensedOutline (#141).
	hover_ring.configure(radius)
	for a in _addons:
		a.configure_visual(radius)
	_node_visuals.configure(radius)
	_node_visuals.geom_inner_r = inner_radius
	_node_visuals.geom_crest_r = radius - RIM_CREST_INSET
	_node_visuals.geom_outer_r = radius
	# #504: entity tint / allocation fill are drawn off `owned_by` — the model.
	# There is no `shown_owner` to lag behind it: an attack's ownership loss now
	# happens at the landing's own `arrival_time` (see [BeatClock]), so the
	# repaint this triggers already IS the reveal.
	_node_visuals.entity_tint = owned_by.color if owned_by != null else Color.WHITE
	_node_visuals.archetype_tint = base_type_color
	_node_visuals.stake_level = stake_level
	_node_visuals.allocation_level = allocation_level if owned_by != null else 0
	_node_visuals.sensed = sensed
	var resolution := EmblemResolver.resolve(get_emblem_contributions())
	_node_visuals.set_carve(resolution.carve, resolution.carve_ties)


func is_allocated() -> bool:
	return _combat.is_allocated()


func is_core() -> bool:
	return owned_by != null and owned_by.core_location == self


## The four mutually exclusive ownership buckets (#384), as `@export_flags`
## bit values — see [NodeTargeting.ownership_filter] for the composites.
enum Ownership { NEUTRAL = 1, MINE = 2, ALLY = 4, HOSTILE = 8 }


## Exactly one set bit describing this node's relation to [param viewer]. A
## node cannot cache "I am hostile" — hostile *to whom* — so this is a pure
## query, never stored state. Delegates to [method Entity.attitude_to] for the
## owned-by-someone-else case; that method is the single home for the
## player/enemy relation.
##
## A null [param viewer] can't be MINE or an ALLY (there's no one to be allied
## with), so an owned node reads HOSTILE to it.
##
## State half moved to [method NodeCombat.ownership_bit] (#498 step 3), so a
## landing gate asks the question the same way against a shadow world as against
## the real one.
func ownership_bit(viewer: Entity) -> int:
	return _combat.ownership_bit(viewer)


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

## Max combat HP for this node. State half moved to [method NodeCombat.get_max_hp]
## (#498 step 2) — see it for why a shadow needs to compute this differently
## than a live node does. 0 if unallocated.
func get_max_hp() -> float:
	return _combat.get_max_hp()


## Current combat HP for this node (ephemeral, from the pool's [member PoolStat.current]).
## State half moved to [method NodeCombat.get_current_hp].
func get_current_hp() -> float:
	return _combat.get_current_hp()


## Wire-restore write half of [method get_current_hp] — for [GraphSnapshot]
## decode only. Writes straight into the `node_health` pool's `current`,
## bypassing [method NodeCombat.take_damage] / [method heal_damage] (no
## `damaged`/`healed` signal, no death check): a decode is reconstructing
## ACCUMULATED state that already happened elsewhere, not re-simulating a hit.
## Ensures the board exists first ([method _init_node_board]) so this works on
## a freshly-decoded node whose board has never been touched.
func restore_current_hp(value: float) -> void:
	_init_node_board()
	var hp := node_board.get_stat(&"node_health") as PoolStat
	if hp != null:
		hp.set_current(value)


## Non-allocating passthrough read: returns the combined value of a stat
## visible to this node (entity board if owned, or StatRegistry default if
## orphaned). Does NOT create a stat on [member node_board] — use
## [method _ensure_local_stat] when you need a modifier target. State half
## moved to [method NodeCombat.get_local_value] (#498 step 2) — that's what
## makes [Mitigation]'s armor/floor reads work on a shadow too.
func get_local_value(stat_id: StringName) -> Variant:
	return _combat.get_local_value(stat_id)


## Returns (creating if necessary) the [code]node_board[/code] stat for
## [param stat_id]. This IS the modifier target — callers that just need a
## value should use [method get_local_value] instead, which does not allocate.
##
## The `node_health`-is-a-PoolStat-here special case moved to
## [method NodeStatBoard._mint_stat], where it belongs — "which Stat class this
## id takes" is a fact about the board, not about the node holding it. That also
## retired this method's direct write into `node_board._extra_stats`.
func _ensure_local_stat(stat_id: StringName) -> Stat:
	_init_node_board()
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
##
## No multi-board guard here (#377 removed StatModifier._board, which is what
## made one cheap): a `board.add_modifier` on an already-applied instance is
## idempotent by design. The local-scale mutator's single-owner assumption
## (decision 9) still holds structurally — this node's own [member modifiers]
## are authored per-node, not shared across SkillNodes — so #377's new
## capability (one instance safely live on N boards) doesn't put THIS array's
## contents on two owners at once; it only makes doing so possible elsewhere,
## deliberately (that's the point of the issue).
func apply_entity_modifiers_to(board: StatBoard) -> void:
	if board == null:
		return
	# One allocation is ONE logical event, so it gets one notification wave.
	# Without the batch, a node granting two modifiers that feed the same
	# downstream stat (`constitution` and `node_health` both feed `node_health`)
	# cascades twice — and that cascade re-syncs every owned node's combat
	# health pool. See StatBoard.begin_batch for the measurement.
	board.begin_batch()
	for m in modifiers:
		board.add_modifier(m)
	board.end_batch()


## The handles this node is currently contributing to its owner's board — what
## [method remove_entity_modifiers_from] would take off, [b]without taking
## anything off[/b] (#520).
##
## Pure by design, and that is the whole point: a shadow's cascade has to revoke
## this node's grants from ITS board, and the mutating helper below erases
## [member _scaled_sets] on the REAL node while it works. Splitting the question
## ("what is granted") from the verb ("un-grant it") is what lets both worlds
## share the answer and keeps the `erase` on the live path where it belongs.
##
## A composition swap ([member _scaled_sets] entry) means the parent's own
## leaves are NOT what landed — the scaled set is, so that is what this reports.
func granted_entity_modifiers() -> Array[StatModifier]:
	var out: Array[StatModifier] = []
	for m in modifiers:
		var swapped: Array = _scaled_sets.get(m, [])
		if swapped.is_empty():
			out.append(m)
		else:
			for leaf in swapped:
				out.append(leaf)
	return out


## Strip this node's entity-scoped modifiers from [param board]. Called by
## [AllocationSystem] when the node stops being owned — i.e. the LIVE path, and
## the only one, because of the [member _scaled_sets] erase at the end.
func remove_entity_modifiers_from(board: StatBoard) -> void:
	if board == null:
		return
	# Symmetric with apply_entity_modifiers_to — a dealloc is one event too, and
	# the same double-cascade applies on the way out.
	board.begin_batch()
	for handle in granted_entity_modifiers():
		board.remove_modifier(handle)
	board.end_batch()
	# A swapped set has now left the board, so the swap record is spent. Erased
	# after the removals, never inside the loop above — `granted_entity_modifiers`
	# reads the same dictionary.
	for m in modifiers:
		if _scaled_sets.has(m):
			_scaled_sets.erase(m)


## Apply [param m] to this node's [member node_board] — a node-scoped modifier,
## never reaching the owning entity's board. The public target for [Effect]
## grants (via [method EffectContext.grant]) and for addon `local_modifiers`.
##
## Node-local values are read back with [method get_local_value], which merges
## the node's bins with the owner's through one [method ModifierBins.compute]
## without allocating.
##
## Mirrors [method StatBoard.add_modifier]'s cycle-check -> bind -> resolve-target
## sequence (cross-referenced there too — #340), but does NOT route through it:
## StatBoard.add_modifier resolves its target with plain get_stat, which returns
## null on a sparse node board (silently dropping the modifier), and making it
## ensuring instead would let a stray node-only stat id (stake_level,
## addon_slots) leak onto an entity board. So the three steps are done locally
## against node_board instead, using the legitimate write path
## ([method _ensure_local_stat]) for the target.
func add_local_modifier(m: StatModifier) -> void:
	if m == null:
		return
	_init_node_board()
	var cycle := node_board.cycle_from(m)
	if not cycle.is_empty():
		push_warning("SkillNode.add_local_modifier: rejected a modifier that would close a formula dependency cycle: %s" % cycle)
		return
	# flatten() so a CompositeStatModifier lands its children on node_board;
	# a plain modifier is its own singleton. Mirrors StatBoard.add_modifier —
	# the node-local channel is bundle-aware too (#183).
	for leaf in m.flatten():
		node_board.bind_modifier(leaf)
		_ensure_local_stat(leaf.stat_id).add_modifier(leaf, node_board)
	# Canonical ledger for the local-scale mutator (#376): the PARENT instance
	# (composites stay whole) so the walk can consult its override.
	if not _local_modifiers.has(m):
		_local_modifiers.append(m)
	# #634: a freshly bound handle always arrives at its AUTHORED (al=1)
	# value — an aura re-grant included, since #623 scales the aura's
	# distance, never the node's allocation ladder. Bring it up to this
	# node's CURRENT allocation level right here, or it sits at baseline
	# until the next stake_level change happens to fire
	# _on_stake_level_changed. `_scale_modifier` is the same universal-law /
	# override walk _apply_local_scale already runs per stake change, so a
	# composite's children and any `_local_scale_override` are honoured
	# identically; it needs a live board, which is exactly why this runs
	# after `node_board` is bound above.
	_scale_modifier(m, 1, _last_allocation_level)


## Remove a modifier previously applied by [method add_local_modifier]. Removal
## is by object identity, so callers must hand back the same instance.
func remove_local_modifier(m: StatModifier) -> void:
	if m == null or not _node_board_ready:
		return
	# A composition swap (m._scaled_sets entry) means the parent's own leaves
	# are NOT what's applied — remove the scaled set too, or it would strand
	# on the board.
	var leaves: Array = _scaled_sets.get(m, [])
	if not leaves.is_empty():
		for leaf in leaves:
			node_board.unbind_modifier(leaf)
			var s: Stat = node_board.get_stat(leaf.stat_id)
			if s != null:
				s.remove_modifier(leaf, node_board)
		_scaled_sets.erase(m)
	_local_modifiers.erase(m)
	# Symmetric with add_local_modifier: flatten() returns the same stable child
	# instances, so a composite added earlier is removed leaf-for-leaf.
	for leaf in m.flatten():
		var s: Stat = node_board.get_stat(leaf.stat_id)
		if s != null:
			node_board.unbind_modifier(leaf)
			s.remove_modifier(leaf, node_board)


## Increment [param tag]'s refcount, creating the entry at 1 if new. State half
## on [method NodeCombat.add_tag] (#520), so an aura recomputing against a
## shadow tags the shadow instead of the real node.
func add_tag(tag: StringName) -> void:
	_combat.add_tag(tag)


## Decrement [param tag]'s refcount; drops the entry entirely at 0 so
## [method get_active_tags] only ever reports what's actually live.
func remove_tag(tag: StringName) -> void:
	_combat.remove_tag(tag)


func has_tag(tag: StringName) -> bool:
	return _combat.has_tag(tag)


## The live tag set — no [StatRegistry] entry, no board slot. Tooltips /
## [DebugClipboard] read this for a generic "what's currently active" listing.
func get_active_tags() -> Array[StringName]:
	var out: Array[StringName] = []
	for t in _tags:
		out.append(t)
	return out


## Appends [param effect] to [member effects] and re-resolves the central
## emblem so a carve added after this node's first `_sync_visuals()` (procgen's
## post-placement spell-grant roll; a loot-granted [SpellGrant] landing on an
## already-allocated core) actually shows up. Plain `effects.append()` misses
## this — [member archetype] and [member keystone] have setters that resync,
## but [member effects] is a bare array with no hook. If the node isn't ready
## yet, its own `_ready()` → `_sync_visuals()` will read the appended effect
## once it runs, so the guard is correct, not just defensive.
func add_effect(effect: Effect) -> void:
	effects.append(effect)
	if is_node_ready():
		_sync_visuals()


## Every [Effect] this node grants to an owner: its own, its keystone's, and
## any carried by its addons. [AllocationSystem] grants these on allocate and
## revokes them (keyed by this node) on deallocate.
func get_node_effects() -> Array[Effect]:
	var out: Array[Effect] = effects.duplicate()
	if keystone != null:
		out.append_array(keystone.effects)
	for a in _addons:
		out.append_array(a.effects)
	return out
#endregion


## Tooltip identity — [member Keystone.display_name] when this node carries a
## keystone, [code]""[/code] otherwise. Deliberately no fabricated id, no scene
## node name, no hash: an empty string means "no name to show", and callers
## render nothing (#288's name composer later fills the empty branch). See
## Tooltip V2 (#294).
func get_display_name() -> String:
	if keystone != null:
		return keystone.display_name
	return ""


## True vertex degree in [param graph] — every node sharing an edge with this
## one, regardless of ownership. O(degree): reads [method Graph.get_neighbours]'s
## cached adjacency index. NEVER walk [method Graph.get_edges] per node — see
## `.claude/rules/graph.md`.
## Self-loops ARE counted (+2 each): they are real [Edge] children, and
## `Graph._adjacency` appends both endpoints — so this already agrees with
## [method GraphMirror.get_degree]'s explicit `+ 2 * self_loop_count`. The one
## place the two diverge is **parallel edges**: AStar dedupes them, this
## doesn't. Nothing emits parallel edges today.
func get_graph_degree(graph: Graph) -> int:
	if graph == null:
		return 0
	return graph.get_neighbours(self).size()


## Degree within the induced subgraph of [param entity]'s owned nodes: how many
## of this node's neighbours are also owned by [param entity]. Always
## `<= get_graph_degree(graph)`, and self-loops count +2 as in
## [method get_graph_degree].
##
## [param entity] defaults to this node's own [member owned_by] — that's the
## "degree inside its own territory" reading almost every caller wants, and an
## unallocated node correctly reads 0.
##
## Passing an [param entity] that does NOT own this node is meaningful only if
## you mean it: it counts this node's [param entity]-owned neighbours, so an
## unowned node wedged between two of red's nodes reads 2 for red.
##
## [b]Two things this body deliberately does NOT do[/b] — both were tried and
## both are wrong; see `docs/domain/degree.md` for the long form:
##
## 1. It does not add `2 * self_loop_count`. `Graph._adjacency` already appends
##    BOTH endpoints of a self-loop, so the loop below visits `self` twice and
##    the +2 falls out for free — adding it again double-counts.
## 2. It does not delegate to `entity.navigator.get_degree(self)`. The navigator
##    mirrors only nodes `entity` OWNS, so it answers `-1` for exactly the
##    unowned-node reading documented three lines up.
func get_entity_degree(graph: Graph, entity: Entity = null) -> int:
	if entity == null:
		entity = owned_by
	if graph == null or entity == null:
		return 0
	var count := 0
	for n in graph.get_neighbours(self):
		if n.owned_by == entity:
			count += 1
	return count


## Addons currently attached to this node, in child order. Reads the `_addons`
## ledger rather than scanning children, so it's O(addons) — it sits inside
## `_sync_visuals` and the tooltip/emblem aggregators, both of which run per
## node at graph scale (see .claude/rules/skill-node-scale.md).
##
## Returns a copy: callers may mutate the result (the accessor contract in
## .claude/rules/graph.md). Internal loops iterate `_addons` directly.
func get_addons() -> Array[SkillNodeAddon]:
	return _addons.duplicate()


## Whether this node currently carries an addon of exactly `script` (e.g.
## `has_addon(ClampAddon)`). Iterates `_addons` directly, not `get_addons()` —
## same reasoning as `can_attach_addon` above: the accessor duplicates the
## whole ledger just to check membership, and this is meant to be cheap enough
## to call from `Edge`'s render-state push (#455). `get_script() == script`
## matches `_attach_addon`'s own duplicate-unique comparison, not an `is`
## check, so it generalizes to any addon script without a hardcoded type test.
func has_addon(script: Script) -> bool:
	for a in _addons:
		if a.get_script() == script:
			return true
	return false


## Defensive sharpness of this node — the spike magnitude an enemy melee blade
## vertex takes when it sweeps in (0 when unspiked). Sums every SpikeRingAddon's
## `blade_damage` local modifier (one quantity drives both the offensive
## blade_damage and this defensive pop — see docs/design/skill_node_addons.md
## "Spikes"). Read by BladePopResolver during an attacker's swing resolution (#170).
func get_spike_power() -> float:
	var total := 0.0
	for a in _addons:
		if a is SpikeRingAddon:
			for mod in a.get_local_modifiers():
				if mod.stat_id == &"blade_damage":
					total += mod.get_effective_value(node_board)
	return total


## Tooltip sections contributed by attached addons. Each entry is
## `{ "title": String, "modifiers": Array[StatModifier], "description": String }`;
## The tooltip fan's AddonsPanel renders them per addon. Addons opt
## in by overriding [method SkillNodeAddon.get_tooltip_modifiers] (e.g. SkillDust
## lists its loot payload) or authoring [member SkillNodeAddon.description] for a
## behaviour-only addon with no modifiers (e.g. Clamp). Addons that contribute
## neither are skipped.
func get_addon_tooltip_sections() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for a in _addons:
		var mods := a.get_tooltip_modifiers()
		if mods.is_empty() and a.description.is_empty():
			continue
		out.append({"title": a.get_tooltip_title(), "modifiers": mods, "description": a.description})
	return out


## Aggregates this node's [EmblemSpec] candidates for the central-emblem
## resolver (see docs/domain/skillnode-emblem.md): the archetype fallback
## carve, a keystone carve, a SPELL carve per granted [SpellGrant], and every
## addon's own [method SkillNodeAddon.get_emblem] contribution. SkillNode never
## interprets these — [EmblemResolver] picks the winning CARVE and collects the
## BLOOMs; this is purely aggregation, mirroring [method get_node_effects] /
## [method get_addon_tooltip_sections].
##
## A null [member archetype] contributes nothing — the honest empty dome —
## rather than silently falling back to a default shape.
##
## A keystone / spell grant with no `carve_shape` authored still contributes,
## with a null [member EmblemSpec.shape]. That's deliberate and NOT the same as
## contributing nothing: it claims its (higher) rung so the node reads as an
## empty dome, instead of the archetype fallback winning and dressing a keystone
## node up as a plain territory node.
func get_emblem_contributions() -> Array:
	var out: Array = []
	if archetype != null:
		out.append(archetype.carve_shape.carve(EmblemSpec.Priority.ARCHETYPE, &"archetype"))
	if keystone != null:
		out.append(EmblemSpec.carve(keystone.carve_shape, EmblemSpec.Priority.KEYSTONE, &"keystone"))
	for effect in get_node_effects():
		if effect is SpellGrant and effect.spell_def != null:
			out.append(EmblemSpec.carve(effect.spell_def.carve_shape, EmblemSpec.Priority.SPELL, &"spell"))
	for a in _addons:
		var spec = a.get_emblem()
		if spec != null:
			out.append(spec)
	return out


## Reset node combat health to full. D-9 removed the turn-start refill sweep
## (see [method apply_turn_regen]) — this now fires only on allocation, from
## [method _refresh_hp_binding].
##
## Known and accepted interaction (D-9): because this still fires on
## allocation, a low-HP node can be deallocated and reallocated to come back
## full. That costs 1 DP (+2 MP if the core sits there) and requires topology
## that permits the dealloc without islanding — a real turn-budget price, not
## a bug. Do not "fix" this without a design decision first — see D-9 in
## docs/design/mvp_decisions.md.
func refill(silent: bool = false) -> void:
	_combat.refill(silent)


## Notification half of [method refill]'s state change (see [NodeCombat]).
## The HP number itself needs no announcement here: [HealthBar] draws the
## `node_health` pool and hears its `current_changed` directly (#504).
func notify_refilled(prev: float, after: float, silent: bool) -> void:
	if not silent:
		var delta := after - prev
		if delta > 0.0:
			healed.emit(delta, null)
			Events.skill_node_healed.emit(self, delta, null)


## Turn-start regen upkeep (D-9), called once per owned node from
## [code]Entity._on_turn_started[/code]. Gated, ramping heal:
##
## - took damage since the last upkeep -> [member regen_stacks] resets to 0,
##   no base heal;
## - else if below max HP -> heal [code]node_healing + regen_stacks *
##   node_healing_ramp[/code], then bump the stack;
## - else (already full) -> reset the stack.
##
## Aura healing (D-10) is [i]not[/i] computed here — it ignores this gate and
## grants no ramp, so the caller applies it separately via
## [method CoreAura.apply] / [method heal_damage] on top of whatever this
## method does. Folding it in here would wrongly gate it on damage-this-turn.
func apply_turn_regen() -> void:
	var hp := node_board.get_stat(&"node_health") as PoolStat if _node_board_ready else null
	if hp == null:
		return
	var took_damage := _damaged_since_upkeep
	_damaged_since_upkeep = false
	if took_damage:
		regen_stacks = 0
		return
	if hp.current >= hp.value:
		regen_stacks = 0
		return
	var base_heal: float = get_local_value(&"node_healing")
	var ramp: float = get_local_value(&"node_healing_ramp")
	var amount: float = base_heal + float(regen_stacks) * ramp
	regen_stacks += 1
	if amount > 0.0:
		heal_damage(amount, null)


## Apply an incoming hit. Mitigation runs here so attackers don't need to know
## about defender stats; node soaks first, overflow eats core HP iff this is
## the owner's core node. Emits [signal damaged] (and re-emits on the global
## bus) so UI hooks fire even when 0 damage lands.
func take_damage(amount: float, source: Variant) -> void:
	_combat.take_damage(amount, source)


## Notification half of [method take_damage]'s state change (see
## [NodeCombat]): the local + global damage announcement and the post-
## mitigation defensive-effect dispatch. `amount`/`before`/`after` name the
## HP pool's values around the deplete; `effective` is the post-mitigation
## number (`damaged.emit` and the dispatch both carry it, matching the
## pre-#498 contract).
func notify_damaged(_before: float, _after: float, effective: float, source: Variant) -> void:
	damaged.emit(effective, source)
	Events.skill_node_damaged.emit(self, effective, source)
	# Post-mitigation amount, so a defensive effect reacts to what actually landed.
	owned_by.dispatch(&"_on_node_damaged", [self, effective])


## Notification half of [method take_damage]'s state change for the "HP hit
## 0, non-core" branch (see [NodeCombat]). [param source] is the [HitInstance]
## that depleted this node, forwarded so [method BattleSystem._on_node_depleted]
## can record the cascade it runs back onto that hit (#518) — the emit is
## synchronous, so the record is in place before `take_damage` continues. The core-node branch never calls
## this — an overflowing core node returns before the depleted check, exactly
## as before extraction (core HP is bottomless in the death sense; see
## `.claude/rules/entity-death.md`).
func notify_depleted(source: Variant = null) -> void:
	depleted.emit()
	Events.skill_node_depleted.emit(self, source)


## Restore HP by [param amount], clamped at max. Emits [signal healed] (and
## re-emits on the global bus) with the effective delta actually restored.
func heal_damage(amount: float, source: Variant) -> void:
	_combat.heal_damage(amount, source)


## Notification half of [method heal_damage]'s state change (see [NodeCombat]).
func notify_healed(_prev: float, _after: float, effective: float, source: Variant) -> void:
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
	# Ratcheted, not a raw `base_value` write: the owner's node_health baseline
	# climbs with CON/level, and a raw write moves the cap *outside* the ratchet —
	# no grant on a rise, no clamp on a fall. That stranded `current` at its old
	# value while max grew, which is #346's "nodes sit at ~1/10 max HP". D-31.
	hp.base_value = float(_bound_entity_node_health.get_value())


func _reset_combat_health() -> void:
	var hp := node_board.get_stat(&"node_health") as PoolStat if _node_board_ready else null
	if hp != null:
		hp.set_current(0.0)


## Materialize [member node_board] from [constant DEFAULT_NODE_BOARD] — a deep
## clone, exactly like [method Entity._ready] does with the entity template.
## Deep because `duplicate(true)` is what gives this node its OWN `stake_level`
## pool and `addon_slots` stat; a shallow copy (or `resource_local_to_scene` on
## the template, the other candidate) would leave every SkillNode in the level
## sharing one set of Stat instances, and every local modifier would apply
## globally. `resource_local_to_scene` does NOT recurse into sub-resources —
## each Stat would need the flag individually — which is exactly the discipline
## the Entity pattern avoids having to remember.
##
## Lazy, and called from every write path (both proxy setters,
## [method _ensure_local_stat], [method add_local_modifier]): a node that never
## needs a board never pays for one.
func _init_node_board() -> void:
	if _node_board_ready:
		return
	# The authored board when a scene composed one, the shared template otherwise
	# — either way a deep clone, so this node owns its Stat instances outright.
	# Deep matters: `resource_local_to_scene` on the template would NOT recurse
	# into sub-resources, so every SkillNode in the level would share one set of
	# Stats and every local modifier would apply globally. Same reason
	# Entity._ready duplicates instead of relying on the flag.
	var source: NodeStatBoard = node_board if node_board != null else DEFAULT_NODE_BOARD
	node_board = source.duplicate(true)   # clears the flag via the setter...
	_node_board_ready = true              # ...so re-raise it here, after the write
	# The reactive edge feeding the #376 local-scale mutator, and the read side
	# of the `stake_level__current` accessor. Connected here rather than in the
	# template because a signal connection is not a resource property.
	node_board.stake_level.current_changed.connect(_on_stake_level_changed)
	# `addon_slots = base(0) + allocation_level` — authored on the template as an
	# intrinsic instead of built in code, so the formula is a one-file edit and
	# binds through the ordinary reactive path (#375). Unconditional, mirroring
	# Entity._ready: an authored board needs its intrinsics applied just as much
	# as a cloned template does.
	node_board.apply_intrinsics()
	# Push the AUTHORED backings, not the proxy getters — the getters would read
	# the pool's just-cloned state and overwrite what the author set.
	node_board.stake_level.base_value = float(_stake_level_backing)
	node_board.stake_level.set_current(float(_allocation_level_backing))


## Push the authored [member stake_level] backing into the node-board pool's
## cap. Clones the board on demand (a written cap is its birth event for an
## unallocated node); the pool itself is baked, so it is never absent after.
func _push_stake_level() -> void:
	_init_node_board()
	node_board.stake_level.base_value = float(_stake_level_backing)


## Push the [member allocation_level] backing into the node-board pool's
## current — the pool's clamp is what keeps fill ≤ cap. Clones the board on
## demand like [method _push_stake_level].
func _push_allocation_level() -> void:
	_init_node_board()
	node_board.stake_level.set_current(float(_allocation_level_backing))


## Hooked to the stake pool's `current_changed` — the reactive edge that runs
## the local-scale mutator (#376) once per allocation_level change. Per-node
## cost, not per-read: the mutator retunes the canonical modifier instances
## in place, and `Resource.changed` propagation re-derives every board that
## holds a reference.
func _on_stake_level_changed(new_current: Variant) -> void:
	var new_al := int(new_current)
	var old_al := _last_allocation_level
	_last_allocation_level = new_al
	_apply_local_scale(old_al, new_al)


# ── Local-scale mutator (#376) ───────────────────────────────────────────────
#
# The magnitude curve: every node-local and node-granted-to-entity modifier
# scales with the allocation level, per a per-operation law. SkillNode is the
# AUTHORITY over the canonical instances; the entity board (and node_board)
# hold references to the same instances, so a live `value` write propagates
# with no re-grant. The ladder is linear by default; `_local_scale` is the
# one line to swap for a curve.
#
# The mutator only ever writes `m.value` (share-safe via Resource.changed) —
# it never touches `_board` / `_bound_sources` / `_propagating` (decision 9).
# Composition mutations (Array overrides) are the one stateful exception: the
# swap ledger tracks which scaled leaf-set is currently applied in a parent's
# place, so the restore is exact.

## The ladder: al → scale factor. Identity, floored at 1 so an unowned node
## (al 0) reads as the baseline — going 0→1 is a ×1 no-op and 1→0 restores
## the authored value exactly. Swap the body for a curve later = one line.
func _local_scale(al: int) -> float:
	return maxf(float(al), 1.0)


func _laddered_multiply(value: float, old_al: int, new_al: int) -> float:
	# "Add the growth part": X(al) = 1 + (X_base - 1) × ladder(al), so the
	# transition is X_new = 1 + (X_old - 1) × ladder(new) / ladder(old) —
	# the exact inverse of the up-scale, so round-trips don't drift.
	return 1.0 + (value - 1.0) * _local_scale(new_al) / _local_scale(old_al)


## Run one mutator pass for a fill transition. Walks the node's entity-scoped
## modifiers, its node-local ledger (which includes addons), and its effects
## (composition path only — see [method _scale_effect]). Iterates UNTYPED
## copies: an `is CompositeStatModifier` on a typed-array loop variable is a
## parse error in this repo (.claude/rules/stats-system.md).
func _apply_local_scale(old_al: int, new_al: int) -> void:
	if old_al == new_al:
		return
	var entity_mods: Array = modifiers
	for m in entity_mods:
		_scale_modifier(m, old_al, new_al)
	var local_mods: Array = _local_modifiers
	for m in local_mods:
		_scale_modifier(m, old_al, new_al)
	for e in get_node_effects():
		_scale_effect(e, old_al, new_al)


func _scale_modifier(m: StatModifier, old_al: int, new_al: int) -> void:
	if m == null:
		return
	if m.scales_with(&"stake_level"):
		return  # already al-scaled by formula — the #375 parallel path
	var override: Variant = m._local_scale_override(old_al, new_al)
	# Type-guard the sentinel BEFORE comparing: a Variant holding an Array or
	# float cannot be ==-compared with a StringName (runtime error, not false).
	if override is StringName and override == StatModifier.UNSCALED:
		return
	if override is float or override is int:
		_restore_scaled_contribution(m)
		m.value = float(override)
		return
	if override is Array:
		_swap_scaled_contribution(m, override)
		return
	if override != null:
		push_warning("SkillNode._apply_local_scale: modifier '%s' returned unsupported override type %s; falling through to the universal law" % [m.resource_path, typeof(override)])
	# Universal law (null override).
	_restore_scaled_contribution(m)
	if m is CompositeStatModifier:
		for leaf in m.flatten():
			_scale_modifier(leaf, old_al, new_al)
		return
	match m.operation:
		StatModifier.Operation.ADD_BASE, StatModifier.Operation.ADD_BONUS, StatModifier.Operation.INCREASE:
			# "+X → +X × ladder(al)" — value × ladder(new)/ladder(old) is
			# exact for integer ladders (5 × 2/1 = 10, 10 × 1/2 = 5).
			m.value = m.value * _local_scale(new_al) / _local_scale(old_al)
		StatModifier.Operation.MULTIPLY:
			m.value = _laddered_multiply(m.value, old_al, new_al)
		StatModifier.Operation.SET:
			pass  # SET opts out of the universal law by default (#376 decision 7)


## The board a modifier is applied to: the entity board for entity-scoped
## modifiers (when owned), node_board for the local ledger. null when the
## modifier is not currently applied anywhere (unowned entity grants).
func _contribution_board(m: StatModifier) -> StatBoard:
	if owned_by != null and owned_by.stat_board != null and modifiers.has(m):
		return owned_by.stat_board
	if _node_board_ready and _local_modifiers.has(m):
		return node_board
	return null


## Composition mutation (decision 8): replace the parent's applied contribution
## with the override's scaled leaf-set. The parent STAYS in its ledger (it is
## still the canonical authority); `_scaled_sets` tracks what the board
## actually holds so the restore is exact.
func _swap_scaled_contribution(m: StatModifier, leaves: Array) -> void:
	var board := _contribution_board(m)
	if board == null:
		return  # unowned / not applied: nothing to swap on the board
	var prev: Array = _scaled_sets.get(m, [])
	if not prev.is_empty():
		_remove_leaf_set(board, prev)
	else:
		board.remove_modifier(m)
	_apply_leaf_set(board, leaves)
	_scaled_sets[m] = leaves


## Reverse of [method _swap_scaled_contribution]: put the parent's own leaves
## back where the scaled set was.
func _restore_scaled_contribution(m: StatModifier) -> void:
	var prev: Array = _scaled_sets.get(m, [])
	if prev.is_empty():
		return
	var board := _contribution_board(m)
	_scaled_sets.erase(m)
	if board == null:
		return  # the board is gone (dealloc); nothing to restore on it
	_remove_leaf_set(board, prev)
	_apply_leaf_set(board, m.flatten())


## Node boards are sparse — a scaled set may target stats the board doesn't
## carry yet, so the local apply/remove paths ensure (apply) or no-op
## (remove) through the stat lookup, mirroring add/remove_local_modifier.
func _apply_leaf_set(board: StatBoard, leaves: Array) -> void:
	for leaf in leaves:
		if board == node_board:
			node_board.bind_modifier(leaf)
			_ensure_local_stat(leaf.stat_id).add_modifier(leaf, node_board)
		else:
			board.add_modifier(leaf)


func _remove_leaf_set(board: StatBoard, leaves: Array) -> void:
	for leaf in leaves:
		if board == node_board:
			node_board.unbind_modifier(leaf)
			var s: Stat = node_board.get_stat(leaf.stat_id)
			if s != null:
				s.remove_modifier(leaf, node_board)
		else:
			board.remove_modifier(leaf)


## Effect composition path (acceptance 6): an effect whose override returns an
## Array has its granted contribution replaced on the entity board with the
## scaled leaf-set. Effects never value-scale — their canonical modifiers are
## shared .tres instances, so a Float override is rejected with a warning.
func _scale_effect(e: Effect, old_al: int, new_al: int) -> void:
	if e == null:
		return
	var override: Variant = e._local_scale_override(old_al, new_al)
	if override is StringName and override == StatModifier.UNSCALED:
		return
	if override is Array:
		var entity := owned_by
		if entity == null or entity.stat_board == null:
			return
		if _scaled_effect_sets.has(e):
			_remove_leaf_set(entity.stat_board, _scaled_effect_sets[e])
			_scaled_effect_sets.erase(e)
		else:
			for inst in entity.get_effects():
				if inst.source_node == self and inst.effect == e:
					entity.revoke_effect(inst)
		_apply_leaf_set(entity.stat_board, override)
		_scaled_effect_sets[e] = override
		return
	# Identity form: restore a previously-swapped contribution, then stop.
	if _scaled_effect_sets.has(e):
		_restore_scaled_effect(e)
	if override == null:
		return
	if override is float or override is int:
		push_warning("SkillNode._scale_effect: effect '%s' returned a Float override — effects carry shared .tres modifiers; use the Array (composition) form" % e.resource_path)
		return
	push_warning("SkillNode._scale_effect: effect '%s' returned unsupported override type %s" % [e.resource_path, typeof(override)])


func _restore_scaled_effect(e: Effect) -> void:
	var entity := owned_by
	if entity == null or entity.stat_board == null:
		_scaled_effect_sets.erase(e)
		return
	_remove_leaf_set(entity.stat_board, _scaled_effect_sets[e])
	_scaled_effect_sets.erase(e)
	entity.grant_effect(e, self)


## Every leaf currently applied through a scaled effect-set — the read half of
## [method clear_scaled_effect_sets] (#520), for the same reason
## [method granted_entity_modifiers] exists.
func scaled_effect_leaves() -> Array[StatModifier]:
	var out: Array[StatModifier] = []
	for e in _scaled_effect_sets:
		for leaf: StatModifier in _scaled_effect_sets[e]:
			out.append(leaf)
	return out


## Strip any scaled effect-sets applied to [param board] — called by
## AllocationSystem just before an ownership transition revokes the effect
## instances, because a swapped set is applied OUTSIDE the effect ledger and
## would strand on the board otherwise.
##
## Note this one was ALREADY shadow-safe: it only ever removed leaves from the
## board it was handed and never touched [member _scaled_effect_sets] (#520's
## body reads it as mutating the node; it does not). Kept as the named verb, now
## expressed over [method scaled_effect_leaves] so there is one answer to "what
## did the swap put on the board".
func clear_scaled_effect_sets(board: StatBoard) -> void:
	if board == null:
		return
	_remove_leaf_set(board, scaled_effect_leaves())
	_scaled_effect_sets.clear()


## Ownership-transition fill writer (#337): a node that stops being owned
## empties its fill. NO LONGER the fill authority — it never invents a 1 for
## newly-owned nodes; the allocate path (allocate / force_allocate /
## register_scene_authored_ownership) owns increments. The old `elif
## allocation_level == 0: allocation_level = 1` branch was the accident that
## kept fill writes working; it is gone on purpose.
func _refresh_alloc_count() -> void:
	if owned_by == null:
		allocation_level = 0


## Pixels of radius added by the current stake level. Level 1 (the ~99% case)
## adds nothing.
func _stake_growth() -> float:
	return (stake_level - 1) * stake_radius_delta


## Republishes the derived [member radius] / [member inner_radius] after any of
## their three inputs changed. There is no cached value to update — the point
## of the getters is that there can't be one to go stale — so this only has to
## notify and resync.
func _refresh_radius() -> void:
	radius_changed.emit()
	if not is_node_ready():
		return
	_sync_collision()
	_sync_visuals()


# Addon plumbing. Carrier owns its `modifiers` array as the source-of-truth
# for AllocationSystem, so addons mutate it directly here (append/erase).
# While allocated we also push/pop live on the entity board so the effect
# is immediate — same StatModifier instance, no double-pop because
# AllocationSystem iterates the (now-updated) array on dealloc.
#
# Attaching is `add_child` — there is deliberately no `attach_addon()` wrapper
# (#334). A second entry point would be the old AddonAnchor rebuilt with extra
# steps; future validation (slot caps, compatibility) belongs right here, in
# the `child_entered_tree` handler every path already flows through.

func _on_addon_added(c: Node) -> void:
	if c is SkillNodeAddon:
		_attach_addon(c)


func _on_addon_removed(c: Node) -> void:
	if c is SkillNodeAddon:
		_detach_addon(c)


## Whether an addon instantiated from `addon_script` would legally attach
## right now: an open slot AND no unique-collision (#406). Read-only —
## `_attach_addon` itself is UNCHANGED and still enforces only `unique`,
## never slots (slot enforcement stays locally scoped to the temp-upgrade
## gate per #406's acceptance spec; this is not #348's general-enforcement
## work). Callers that want slot enforcement call this instead of
## reimplementing it.
func can_attach_addon(addon_script: Script) -> bool:
	# `_addons.size()`, not `get_addons().size()` — the accessor duplicates the
	# whole ledger just to count it, and #406's UI calls this per candidate node.
	if _addons.size() >= int(get_local_value(&"addon_slots")):
		return false
	for a in _addons:
		if a.unique and a.get_script() == addon_script:
			return false
	return true


## Idempotent against the `_addons` ledger, NOT against call ordering — see
## [member _addons]. Attaching twice is a no-op, so tree re-entry can't
## double-apply an addon's modifiers.
func _attach_addon(a: SkillNodeAddon) -> void:
	if _addons.has(a):
		return
	if a.unique:
		for existing in _addons:
			if existing.get_script() == a.get_script():
				push_error("Duplicate unique addon %s on %s; rejecting." % [a.get_script().resource_path, name])
				# Refuse it, but never FREE it under the editor — since #334 made
				# scene authoring the blessed path, freeing here would silently
				# delete an authored node out of the user's open scene on load.
				if not Engine.is_editor_hint():
					a.queue_free()
				return
	_addons.append(a)
	# Mint the addon_slots stat for addon carriers (#375) — must run after the
	# ledger append (the mint's sparse check reads it) and before any modifier
	# transfer below, so a formula-bound addon modifier can bind the pool.
	_init_node_board()
	# Draw order is the addon's own business — see SkillNodeAddon.BASE_Z. The
	# carrier deliberately doesn't write it.
	#
	# The modifier transfer is runtime-only: `modifiers` is an @export, so doing
	# this under the editor would serialize addon-derived modifiers into the
	# .tscn and compound them on every save (see .claude/rules/godot-workflow.md,
	# "never write a DERIVED value back into an @export"). The editor still gets
	# the addon's visuals — it just doesn't get its stats. #335 removes this
	# guard by splitting authored from derived modifiers.
	if not Engine.is_editor_hint():
		# No clone-and-track needed (#377): every StatModifier sub-resource an
		# addon .tscn carries sets `resource_local_to_scene = true`, so Godot
		# already hands each `instantiate()` its own private copy — the modifier
		# a script-built addon builds in code was always private too. Either
		# way `a.get_local_modifiers()` / `a.entity_modifiers` are already
		# this carrier's own instances; detach can just ask the addon again.
		for m in a.get_local_modifiers():
			add_local_modifier(m)
		for m in a.entity_modifiers:
			add_entity_modifier(m)
	a.visible = not sensed
	_sync_visuals()
	addons_changed.emit()


func _detach_addon(a: SkillNodeAddon) -> void:
	if not _addons.has(a):
		return
	_addons.erase(a)
	# Mirror `_attach_addon`'s `_sync_visuals()`: a departing addon stops
	# contributing its emblem, so the carve must be re-resolved — otherwise a
	# consumed SkillDustAddon (looted relic) leaves its LOOT gem dent behind
	# (#369). Runs in the editor branch too, same as attach.
	_sync_visuals()
	if Engine.is_editor_hint():
		addons_changed.emit()
		return
	# Reverse whatever attach added (#377): identity never changed at attach
	# time, so `a` (still alive here — this fires from `child_exiting_tree`,
	# before it's freed) hands back the exact same instances to remove.
	for m in a.get_local_modifiers():
		remove_local_modifier(m)
	for m in a.entity_modifiers:
		remove_entity_modifier(m)
	addons_changed.emit()


## How long a core's presence takes to glide between two nodes. Named because
## [CameraDirector] sizes a [MoveCoreCommand]'s camera hold off it (#525) and a
## bare literal there would silently drift out of step with this one. It sits
## slightly ABOVE [constant CommandApplier.CORE_HOP_SLIDE_DELAY] on purpose —
## the hops of a multi-hop walk overlap so the walk reads as a cascade.
const CORE_SLIDE_DURATION := 0.25

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
func play_core_slide_from(world_pos: Vector2, duration: float = CORE_SLIDE_DURATION) -> void:
	if not is_node_ready() or not is_core() or sensed:
		return
	var offset := world_pos - global_position
	if offset.is_zero_approx():
		return
	_node_visuals.glide_core_presence(offset, duration)


## Brief red pulse on NodeVisualsComposite. Auto-runs on the `damaged` signal;
## also callable externally (FloatingNumberLayer triggers it on wound/heal
## events so the core flashes alongside the floater).
func play_hit_flash() -> void:
	if not is_node_ready() or _node_visuals == null:
		return
	if _hit_flash_tween != null:
		_hit_flash_tween.kill()
	# Tweens NodeVisualsComposite.feedback_tint (#304) only — leaves
	# visuals.modulate free for other consumers (selection tint, status
	# effects, etc.) without colliding.
	_node_visuals.feedback_tint = _DENY_COLOR
	_hit_flash_tween = create_tween()
	_hit_flash_tween.tween_property(_node_visuals, "feedback_tint", Color.WHITE, 0.25)


# ── Denial feedback (#89) ────────────────────────────────────────────────────
# Two registers for a rejected deallocation, driven by PlayerInputController:
# the nodes that WOULD be islanded pulse danger-red (blink_blocked); the node
# the player actually tried to drop gets a short "bzzt — no" shake (shake_denied).
#
# The red tint lands on `_node_visuals` (NodeVisualsComposite, #304's
# feedback_tint channel), NOT on `visuals` — the hover glow (HoverRing) is a
# child of `visuals`, so a `visuals.modulate` tint multiplied the glow down to
# near-black and read as "the glow vanished". Body tint keeps the hover
# register (a different visual meaning: "pointer is here") clean. The shake
# offsets `visuals.position` (edges anchor on the node root, so endpoints
# don't move); the hover glow is counter-translated to stay world-fixed — the
# pointer isn't shaking, so its feedback shouldn't either.

## Also the hit-flash channel's color (#304) — one shared feedback-tint value
## for both registers, since both drive [member NodeVisualsComposite.feedback_tint].
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
	for addon in _addons:
		addon.position = Vector2.ZERO
	if _node_visuals != null:
		_node_visuals.feedback_tint = Color.WHITE


## Danger-red pulse — marks a node that a denied deallocation would island (#89).
func blink_blocked() -> void:
	if not is_node_ready() or _node_visuals == null:
		return
	_reset_feedback()
	var t := create_tween()
	for i in 2:
		t.tween_property(_node_visuals, "feedback_tint", _DENY_COLOR, _BLINK_STEP)
		t.tween_property(_node_visuals, "feedback_tint", Color.WHITE, _BLINK_STEP)
	_feedback_tweens.append(t)


## Short "bzzt — no" shake + red tint — the node the player tried but failed to
## deallocate (#89). Horizontal decaying jitter on the body; hover glow held put.
func shake_denied() -> void:
	if not is_node_ready() or visuals == null:
		return
	_reset_feedback()
	if _node_visuals != null:
		_node_visuals.feedback_tint = _DENY_COLOR
		var tint := create_tween()
		tint.tween_property(_node_visuals, "feedback_tint", Color.WHITE, _SHAKE_TIME)
		_feedback_tweens.append(tint)
	var shake := create_tween()
	var amps := [1.0, -0.72, 0.5, -0.32, 0.16, 0.0]
	var step := _SHAKE_TIME / float(amps.size())
	for a in amps:
		var off := Vector2(a * _SHAKE_AMPLITUDE, 0.0)
		shake.tween_property(visuals, "position", off, step).set_trans(Tween.TRANS_SINE)
		if hover_ring != null:
			shake.parallel().tween_property(hover_ring, "position", -off, step).set_trans(Tween.TRANS_SINE)
		# Addons are siblings of `visuals`, not children (#334) — they no longer
		# ride its offset for free, so shake them alongside it or the node body
		# jitters out from under a stationary addon sprite.
		for addon in _addons:
			shake.parallel().tween_property(addon, "position", off, step).set_trans(Tween.TRANS_SINE)
	_feedback_tweens.append(shake)


var _mouse_hovering: bool = false
var _forced_hover: bool = false


func _on_mouse_entered() -> void:
	_mouse_hovering = true
	_sync_hover_ring()
	if not Engine.is_editor_hint():
		Events.skill_node_hovered.emit(self)


func _on_mouse_exited() -> void:
	_mouse_hovering = false
	_sync_hover_ring()
	if not Engine.is_editor_hint():
		Events.skill_node_unhovered.emit()


## Highlights this node from outside real mouse hover — e.g. the melee command
## tray's blade blips (#406 follow-up), where hovering a blip should light up
## the SkillNode it represents. A plain bool, not a ref-count: the one caller
## (MeleeBody) owns exactly one hovered node at a time and clears it explicitly
## on refresh/teardown, so there's nothing to double-count.
func set_forced_hover(active: bool) -> void:
	_forced_hover = active
	_sync_hover_ring()


func _sync_hover_ring() -> void:
	if hover_ring == null:
		return
	if _mouse_hovering or _forced_hover:
		hover_ring.show()
	else:
		hover_ring.hide()


func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			left_clicked.emit(self)
		# Right-click is handled node-independently in
		# PlayerInputController._unhandled_input — see the comment there.
