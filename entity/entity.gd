@tool
class_name Entity
extends Node

## An entity that lives on the skill tree. Owns a connected induced
## subgraph of SkillNodes. Identity + colour + an optional stat board, plus
## a child `EntityNavigator` that mirrors the owned-subgraph for connectivity
## queries (islanding checks now; combat path/reach queries later).

## The authored [AmmoType] roster [method reload] mints from — never a
## directory scan (see [AmmoTypeRoster]).
const _AMMO_TYPES: AmmoTypeRoster = preload("res://attack/ammo/ammo_type_roster.tres")

signal core_location_changed
signal leveled_up(new_level: int)
signal died
## The entity-hosted status rows changed (#996) — apply, tick, cure, remove.
## Read them back through [method get_statuses]; #953's core readout binds here.
signal statuses_changed
## This entity's `node_health` BASELINE moved, so the derived cap of every node
## it owns moved with it (#660).
##
## [b]One signal, not one per owned node.[/b] It replaces the N per-node
## `value_changed` subscriptions the old CON fan-out kept — the cap itself is
## derived on read ([method NodeCombat._hp_pool]), so this carries no value and
## invalidates nothing; it exists purely so a VISIBLE health bar knows to
## re-read. Cost is O(listeners), which is O(visible), never O(owned). Do not
## reintroduce a per-node listener as a convenience.
signal node_health_cap_changed

## The player/enemy relation. Two teams for now (#384): [constant ALLIED] is
## same-[member faction], [constant HOSTILE] is everything else. Enemies do
## not fight each other, so a scalar faction resolves it with no attitude
## matrix — going multi-faction later changes only [method attitude_to], not
## its call sites.
enum Attitude { SELF, ALLIED, HOSTILE }

@export var display_name: String = "Entity"
@export var color: Color = Color.WHITE
## Team identity, composed like [member core_class]. Defaults to the shared
## [code]npc.tres[/code] faction; authored per-entity — a hand-authored
## scene sets its own export override, a roster-driven spawn gets it from
## [method GameRoot.apply_roster] (#475). Singular, compared by
## [member Faction.id]: two entities whose factions share an id are allies,
## even across separately-loaded/duplicated resource instances.
@export var faction: Faction = preload("res://entity/factions/npc.tres")
## Whether a human (local or remote) drives this entity — the seam
## [method GameRoot._ensure_controllers] reads to attach [PlayerController]
## vs [AIController]. Authored per-entity (roster-driven spawn via
## [method GameRoot.apply_roster], or set directly on a hand-authored scene's
## node) rather than derived from entity identity. See #475.
@export var is_human_controlled: bool = false
## One owner (#1031): outside the editor the setter stores a private
## `duplicate(true)` from the moment of assignment — a `.tscn` instance gets
## its copy at `instantiate()`, a spawned entity at spawn — so no reader that
## grabbed the board before bring-up can ever hold a stale one. Once
## [method initialize] has applied intrinsics and wired the pools the board is
## sealed: a later assignment `push_error`s and is ignored. The editor stores
## the shared ext_resource as given (the inspector must see it); an authored
## entity brought up in a live tab gets its copy inside [method initialize].
@export var stat_board: EntityStatBoard = null:
	set(v):
		if _board_sealed:
			push_error("Entity.stat_board is sealed after initialize(); assign the board before bring-up")
			return
		if v == null or Engine.is_editor_hint():
			stat_board = v
		else:
			stat_board = v.duplicate(true)

## Flipped by [method initialize] right after the board is duplicated and
## intrinsics applied — the seal on [member stat_board]. Not `_initialized`:
## that latch is set BEFORE the duplicate.
var _board_sealed: bool = false
## Class specialization for this entity. Applied once on _ready via
## `core_class.apply(self)` and consulted each turn via `on_turn_started`.
## Optional — null means a plain entity with no class bonuses.
@export var core_class: CoreClass = null
## Spells this entity knows + the gating logic for whether they can be cast
## from a given node (degree, etc.). Surfaced by the spell-picker UI and
## consulted by AI when scoring magic attacks. Promotion of a known spell
## into the active slot happens via [member BattleSystem.selected_spell].
@export var spellbook: SpellBook = null

## Reward tier (#300): sizes the SkillDust loot FRACTION
## (`LootSystem.loot_fraction_by_tier[tier-1]`, #775 — was the pick count,
## which is now a constant, [member LootSystem.loot_rounds]). No longer sizes
## the killing-blow XP bonus (#774 deleted the tier-scaled term in favour of
## a per-board `core_kill_xp` stat). Players and ordinary NPCs keep the
## default 3 → loot at the full 1.0 rate; removable-node blockers author
## 1/2/3 for small/medium/large → loot at 0.25/0.5/1.0.
@export var entity_tier: int = 3

## Wire identity (#509) — the only legal way a [Command] refers to an entity,
## exactly as [member SkillNode.stable_id] is for nodes. Minted once by
## [method Graph._mint_entity_id] on entry to `entities_container` and never
## reused; 0 means unminted (an entity built in a test and never parented
## under a Graph). Plain var, not @export: it's Graph-assigned runtime
## identity, not authored content — see .claude/rules/gdscript-pitfalls.md on
## never writing a derived value back into an @export.
var entity_id: int = 0

## Which [Participant] seats this entity — [member Participant.id], a
## lobby-minted seat index unrelated to [member entity_id] above (#564). 0
## means unset: an NPC nobody seats, or an entity built outside a roster-driven
## run (a hand-authored scene, a test fixture). Assigned at
## [method GameRoot.apply_roster] time rather than authored — plain var for the
## same reason [member entity_id] is: it is run-assigned identity, not content.
## The correlation this exists to close: [member Participant.id] alone cannot
## answer "which live entity is this seat playing", and nothing else in the
## codebase maps a live [Entity] back to the [Participant] that seats it.
## [method LootPickRegistry.is_remote_collector] is the first reader.
var participant_id: int = 0


## The entity's spellbook, created empty if it doesn't have one yet. Every
## entity *has* a book — an empty one is a real state, not an absent one — so
## granting a spell is never a no-op for lack of somewhere to put it.
## `entity.tscn` bakes one in; this covers entities built via `Entity.new()`
## (tests, sandboxes). Prefer this over touching [member spellbook] when you
## are about to write to the book; reads that tolerate "knows nothing" can
## still check the field directly.
func get_spellbook() -> SpellBook:
	if spellbook == null:
		spellbook = SpellBook.new()
	return spellbook


@export var core_location: SkillNode:
	set(value):
		if core_location == value:
			return
		var previous := core_location
		core_location = value
		core_location_changed.emit()
		# EVERY core placement re-derives auras, not just `AllocationSystem.move_core`.
		# The opening placement — `spawn_entity` assigning core_location after
		# `_ready` already granted the core class's effects, or scene-export
		# deserialization — never passes through move_core. Dispatching from the
		# setter is the only point that catches all of them. (No recursion: in
		# GDScript, assigning a property to its own backing field inside its setter
		# does not re-enter the setter.)
		dispatch(&"_on_core_moved", [previous, value])

## [member faction]'s [member Faction.id], or [code]&""[/code] with no faction
## assigned. For call sites that genuinely want the identifier rather than the
## relation — prefer [method attitude_to] for any hostility test.
var faction_id: StringName:
	get:
		return faction.id if faction != null else &""

## The ONLY place the player/enemy relation is decided (#384) — every other
## hostility test (targeting, XP gating, AI) routes through this or through
## [method SkillNode.ownership_bit], which delegates here. Same-[member faction]
## is ALLIED, compared by [member Faction.id] (not resource reference — a
## `.tres` loaded twice or `duplicate()`d must still compare equal). A null
## faction or an empty id on either side never matches, so two faction-less
## entities read HOSTILE rather than silently allying.
func attitude_to(other: Entity) -> Attitude:
	if other == self:
		return Attitude.SELF
	if faction != null and other.faction != null and faction.id != &"" \
			and faction.id == other.faction.id:
		return Attitude.ALLIED
	return Attitude.HOSTILE

## Current level. A proxy onto the `level` ScalarStat on the stat board — that's
## the canonical store (#200) so level-scaling formula modifiers can bind to it.
## Bumped (+1 base_value) on each xp fill in `_on_xp_replenished`; the getter's
## `.value` folds in any level modifiers and coerces to INT, the setter forwards
## to base_value. Falls back to 1 / no-ops for sparse boards with no `level` stat.
var level: int:
	get:
		if stat_board != null and stat_board.level != null:
			return int(stat_board.level.value)
		return 1
	set(v):
		# Convenience mutator — forwards to the one canonical store (the stat's
		# base_value), so there's no second source of truth. No-ops on sparse
		# boards. The level-up path writes base_value directly (see
		# `_on_xp_replenished`); this exists for scripted/test setup.
		if stat_board != null and stat_board.level != null:
			stat_board.level.base_value = v

## The initiative clock lives on the stat board as the `initiative` PoolStat
## (cap = this entity's action threshold). It fills by `initiative_speed` each
## TurnManager tick; crossing the cap fires `replenished`, which adds this
## entity to the `READY_GROUP` for TurnManager to serve. See _ready / TurnManager.
const READY_GROUP := &"ready_to_act"

## Group every Entity joins on enter_tree. TurnManager enumerates it to tick
## initiative and serve turns; death cleanup removes the corpse so it's skipped.
const GROUP := &"entities"

## #152: fallback AP→surplus conversion used only when a board carries no
## `ap_transfer_rate` stat (sparse / test boards). The live knob is the
## `ap_transfer_rate` ScalarStat — see `_transfer_unused_ap_to_surplus`.
const DEFAULT_AP_TRANSFER_RATE := 2.0

## Every Nth level mints one extra skill point — see [method sp_minted_for_level].
const MILESTONE_LEVEL_INTERVAL := 5

## The [Graph] this entity belongs to, for a scene that cannot put it UNDER one.
## Null (the default, and every level scene) falls back to the ancestor walk in
## [method _find_graph].
##
## An `@export` rather than an `initialize()` argument, deliberately: a NodePath
## export resolves before `_ready`, and `_ready` is what calls
## [method initialize] — a caller passing the graph in afterwards would find
## bring-up already latched and its argument silently ignored
## (`.claude/rules/scene-composition.md`). The spell playground is the case that
## needs it: it parks its entities BESIDE the Graph inside a SubViewport, so no
## ancestor walk can ever reach it, and a navigator-less entity snapshots an
## empty owned set — which since #536 means its nodes fall through to ownerless
## orphan slices and a spell's landings are silently dropped.
@export var graph_override: Graph

## The TurnManager this entity binds to at ready. Null → the first one in
## [constant TurnManager.GROUP], which is the only one in a game tree; a tree
## holding several worlds (the editor's sandbox host) must wire its own.
@export var turn_manager_override: TurnManager

## Auto-created on _ready when the entity has a Graph ancestor. Stays null
## in editor (`@tool` short-circuit) and in stand-alone tests with no graph.
var navigator: EntityNavigator

## Latch for [method initialize] — bring-up runs exactly once per entity, from
## `_ready` in a running game or from a live sandbox that has to ask.
var _initialized: bool = false

## Live [Effect] attachments, in grant order. Each holds its own grant ledger,
## so revocation is exact without a provenance field on [StatModifier].
var _effect_instances: Array[EffectInstance] = []

## The granted-atom ledger for CORE modifiers (#323) — every [StatModifier]
## ever permanently granted onto this entity's core, UNFLATTENED. Two honest
## layers: this register is what LootSystem's draw reads from (composites stay
## intact, so a `loots_as_unit` pack is still one atom if this entity later
## dies); [member stat_board] is the flattened, bound leaves the board computes
## stats from. [method grant_core_modifier] is the ONLY path that writes here —
## same shape as [EffectContext]'s handle-owned pattern — so register/board
## drift is impossible by construction.
var core_modifiers: Array[StatModifier] = []


## The only path that grants a modifier onto this entity's core permanently.
## Appends `m` to [member core_modifiers] (register) and mirrors it onto
## [member stat_board] (the flattened, computed layer). Both [CoreClass.apply]
## (class-template grants) and SkillDust pickup (looted grants) route through
## this — see #323.
##
## Does NOT duplicate `m` — per #377, formula binding is stateless (lives on
## the Stat/Board, not the modifier), so the SAME shared `.tres` instance
## already applies safely to every entity of a class, and a looted candidate
## arrives here already an independent copy (LootSystem's draw duplicates when
## building the payload). Duplicating again here would just be redundant work
## on the class path and double-duplication on the loot path.
func grant_core_modifier(m: StatModifier) -> void:
	if m == null:
		return
	core_modifiers.append(m)
	if stat_board != null:
		stat_board.add_modifier(m)


## The merge verb (#775) — SkillDust pickup routes an equivalent grant through
## here instead of [method grant_core_modifier], so a 6th looted copy of the
## same rule adds to one modifier's `value` rather than holding a 6th copy.
## Class-template grants (`CoreClass.apply`) do NOT go through this — they
## must keep appending the shared template untouched (decision 7); this is
## purely the loot-side merge.
##
## A [CompositeStatModifier] candidate never merges — it always appends whole
## through [method grant_core_modifier], same as a no-match plain candidate.
## A plain candidate is matched by [method StatModifier.merge_key] (same
## stat_id/operation/formula, ignoring `value`) against, in order,
## [member EntityStatBoard.intrinsic_modifiers] then [member core_modifiers] —
## intrinsics first because the owner's own example merges a looted copy into
## the default board rule. No match → the ordinary grant.
##
## A matched target in [member core_modifiers] with a non-empty
## [member Resource.resource_path] is a FILE-BACKED shared instance (a
## class-template grant — `CoreClass.apply` installs the same `.tres`
## modifier object on every entity of that class). Merging into it in place
## would move every entity's stat and the file on disk. Privatised via
## [method StatBoard.privatize_register_entry] first: swap the register slot
## for an unshared `duplicate(true)`, rebind it on the board, merge into the
## duplicate instead — the shared original is never touched. An intrinsic
## should never be file-backed post-`duplicate(true)` (#775 spec, decision 6),
## but as a guard a file-backed INTRINSIC match is skipped as a target
## entirely (search continues into `core_modifiers`) rather than privatised —
## intrinsics don't get the swap-the-slot treatment core_modifiers does.
##
## Owns the WHOLE `stat_modifier_changed` emit for a SkillDust grant (#70: one
## event per leaf on an append, one event carrying the merged target on a
## merge) — [SkillDustAddon._grant_mod] used to do this itself; folded in here
## so the merge path and the append path cannot emit a different shape by
## accident.
func absorb_core_modifier(m: StatModifier) -> void:
	if m == null:
		return
	if m is CompositeStatModifier or stat_board == null:
		grant_core_modifier(m)
		for leaf in m.flatten():
			Events.stat_modifier_changed.emit(self, leaf, ModifierBinding.Kind.CORE, true)
		return
	var key := StatModifierCodec.merge_key(m)
	# Intrinsics first (the owner's own example merges into the default board
	# rule) — but a file-backed one is not a valid target, so skip it rather
	# than returning it.
	var target: StatModifier = _find_merge_target(stat_board.intrinsic_modifiers, key, true)
	var in_intrinsics := target != null
	if target == null:
		target = _find_merge_target(core_modifiers, key, false)
	if target == null:
		grant_core_modifier(m)
		Events.stat_modifier_changed.emit(self, m, ModifierBinding.Kind.CORE, true)
		return
	if not in_intrinsics and not target.resource_path.is_empty():
		target = stat_board.privatize_register_entry(core_modifiers, target)
	target.value += m.value
	Events.stat_modifier_changed.emit(self, target, ModifierBinding.Kind.CORE, true)


## First plain (non-composite) entry in [param mods] whose merge key matches
## [param key], or null. Shared helper for [method absorb_core_modifier]'s two
## search buckets. [param skip_file_backed] excludes a file-backed entry from
## matching at all (the intrinsics bucket — see that method's doc); the
## `core_modifiers` bucket passes false and privatises a file-backed match
## instead of skipping it.
static func _find_merge_target(mods: Array[StatModifier], key: Dictionary,
		skip_file_backed: bool) -> StatModifier:
	var untyped: Array = mods  # untyped: element `is` narrows cleanly (see stats-system.md)
	for entry in untyped:
		if entry == null or entry is CompositeStatModifier:
			continue
		if skip_file_backed and not (entry as StatModifier).resource_path.is_empty():
			continue
		if StatModifierCodec.merge_key(entry) == key:
			return entry
	return null


## Listens for [signal StatBoard.restoring] — fired by
## [method StatBoard.read_dict] BEFORE its per-stat reconcile, so
## [member core_modifiers] gets the same pre-sync-then-privatise treatment
## [method StatBoard.sync_register_from_wire] gives `intrinsic_modifiers`
## itself (#775 late-join amendment; see that method's doc for why this must
## run before, not after, the reconcile).
func _on_stat_board_restoring(d: Dictionary) -> void:
	if stat_board != null:
		stat_board.sync_register_from_wire(core_modifiers, d)

## `hook name -> Array[EffectInstance]`. Bucketed once at grant time by asking
## each effect which optional hooks it implements, so `dispatch` touches only
## interested effects rather than walking every attachment on every event.
var _hook_buckets: Dictionary[StringName, Array] = {}

## Latched once `die()` runs, so death cleanup happens exactly once even if the
## `health` pool re-emits `depleted` mid-cascade. Systems read this to skip a
## corpse (TurnManager initiative, AI targeting).
var is_dead: bool = false

## Turns THIS entity has been served, counted in [method _on_turn_started] —
## distinct from [member TurnManager.turns_taken], which tallies every entity's.
##
## Its one job today is the first-turn gate: while it reads 1, turn-start upkeep
## is skipped entirely, so an entity never collects a turn of income before it
## has played a move. Derived, never synced: `turn_started` fires on every
## peer's own [TurnManager], so each peer counts the same turns independently
## and no [EntitySnapshot] slot is needed. (A mid-run resync onto a freshly
## constructed Entity is the one gap — it would re-grant the skip.)
##
## Fixtures that construct an already-established entity (the `tools/balance/`
## probes) set this to 1 at build time, which is the honest claim: they are not
## on their first turn.
##
## [b]Since #756 it DOES cross[/b] — [constant EntitySnapshot._R_TURNS]. The
## parenthesised gap above was the real one: a peer whose world arrived as a
## snapshot never counted the turns that produced it, so every entity in it read
## 0 and the next turn each one served re-granted the first-turn skip. The
## ordinary case is still that each peer counts for itself, off its own
## `turn_started`; the snapshot is what makes a peer that missed those emits
## agree anyway.
var turns_taken: int = 0

## Sparse spent-set for the `spikes` pop budget (#778): a node lands here the
## moment a melee contact drains its `spikes` pool ([method mark_spikes_spent],
## called from [BladePopResolver.LiveGate._mark_spent] on the LIVE world only).
## [method _on_turn_started] regenerates EXACTLY this set, then clears it — a
## sweep of a level's hundreds of allocated nodes to top up a pool that is
## almost always full is explicitly not acceptable (#778). There is
## deliberately no dormant-node exception: an owner who never takes a turn
## never drains this set, so a node under a blocker absorbs a finite number
## of pops for the whole run and that is intended (owner, #778).
var _spiked_nodes_spent: Dictionary[SkillNode, bool] = {}

## Sparse fired-set for the per-leaf shot budget (#956): every node this
## entity fired an arrow from this turn, appended by the launch commit next to
## its [method SkillNode.mark_shot_fired] call. [method _on_turn_ended] zeroes
## EXACTLY these nodes' [member SkillNode.shots_fired_this_turn] and clears
## the set — the same discipline as [member _spiked_nodes_spent], never a
## sweep of the owned subgraph — and does so regardless of who owns the node
## by then (a leaf lost mid-turn still belongs to this firer's budget).
var _fired_nodes_this_turn: Array[SkillNode] = []

## Volleys this entity has launched this turn, checked against the board's
## `volleys_per_turn` by the plan side (#956). Reset in
## [method _on_turn_started]. Derived from commands, so mirrors reproduce it;
## never snapshotted.
var volleys_launched_this_turn: int = 0

## The leaf set this entity held when its turn STARTED (#955) — the producer
## set a [ReloadCommand] sums `arrows_per_reload` over (∪ the core). Captured
## once per turn in [method _on_turn_started], never re-derived at reload
## time: the fixed set is what closes the allocate-then-reload pump, while
## the VALUES are read live so a stake raised mid-turn still counts. Runtime
## only, never synced — a mirror captures its own copy from its own
## `turn_started`, the same state the authority saw.
var _turn_start_leaves: Array[SkillNode] = []

## Resolved once in [method initialize]; read by [method _on_turn_started] to
## tell an adopted cursor from a turn actually beginning. See
## [member TurnManager.is_adopting].
var _turn_manager: TurnManager = null

## Has this entity's BRAIN concluded it is boxed in, this turn? Host-only,
## AI-only, and re-decided every turn by [method AIController.take_turn] from
## [method AiRecon.is_growth_capped]. Two consequences, one cause (#604):
## Dormant Cores stop being scenery ([method AiRecon.is_ai_target]), and any
## target adjacent to this entity's own territory scores a breakout bonus
## ([method AiCombatScorer.score]) — a door out is worth more than a dent when
## there is no other way to grow.
##
## Lives on [Entity] rather than on the controller because both readers are
## static and only ever receive the attacker entity. Player-driven entities
## never read it — the *relation* is what gates a player's swing, and that
## stays HOSTILE regardless (see [Faction]).
##
## Plain state, deliberately not a status tag: nothing grants or displays it,
## it never survives the turn that set it, and it carries no sync meaning (a
## MIRROR peer never runs an AI turn at all).
var ai_growth_capped: bool = false

## Refcounted status markers, entity-wide twin of [member SkillNode._tags] — see
## docs/design/status-tags.md. Granted/revoked through [method EffectContext.grant_tag]
## / `revoke`, never written to directly.
var _tags: Dictionary[StringName, int] = {}

## The live combat-state slice (#498 step 1, docs/domain/attack-timeline.md).
## Entity COMPOSES this — it owns the live one, it does not copy one.
## Constructed here (a field initializer, not `_ready`) so it exists before
## any pre-`_ready` caller could reach for it.
var _combat := EntityCombat.new(self)


## Public accessor for [member _combat] — [AllocationSystem] (a different
## file) needs it to run the revoke sweep on a node's PREVIOUS owner; a plain
## getter keeps `_combat` itself construction-assigned with no public setter.
func get_combat() -> EntityCombat:
	return _combat


## The statuses hosted on the ENTITY itself (#996): rows that fell through a
## cracked core. Live rows, read-only — see [method StatusHost.get_statuses].
func get_statuses() -> Array[NodeStatus]:
	return _combat.get_statuses()


func _ready() -> void:
	# Group membership is editor-safe and lets @tool consumers (e.g.
	# VisionSystem) enumerate entities live in the inspector.
	add_to_group(GROUP)
	if Engine.is_editor_hint():
		return
	initialize()


## Bring this entity to life: navigator, board duplication + intrinsics, core
## class, and every re-emit subscription. Idempotent — a second call is a no-op,
## so it can never double-apply intrinsics.
##
## Public, and separate from [method _ready], because the editor never runs
## `_ready` (see the guard above) and a LIVE sandbox tab hosting an *authored*
## entity has to say when bring-up happens. Calling this is the whole difference
## between an inert inspector object and a real entity; there is deliberately no
## second, sandbox-flavoured copy of it.
func initialize() -> void:
	if _initialized:
		return
	_initialized = true
	var g := _find_graph()
	if g == null:
		push_warning("Entity '%s' has no Graph ancestor; navigator disabled" % display_name)
	else:
		navigator = EntityNavigator.new()
		navigator.name = "EntityNavigator"
		navigator.entity = self
		navigator.graph = g
		add_child(navigator)
		if Engine.is_editor_hint():
			# EntityNavigator._ready deliberately no-ops in the editor (a @tool
			# mirror must not wire itself just because a scene is open). An
			# explicit `initialize()` is the opposite situation, so wire it here.
			navigator.wire_to(g)

	# Every entity.tscn instance shares the SAME authored spellbook_default.tres
	# resource object (ResourceLoader caches by path) unless duplicated here —
	# same rationale as stat_board immediately below.
	if spellbook != null:
		spellbook = spellbook.duplicate(true)

	# Initialize stat board and wiring. Outside the editor the setter already
	# took a private copy at assignment; the editor holds the shared
	# ext_resource and an authored entity brought up live needs its own here.
	if stat_board != null:
		if Engine.is_editor_hint():
			stat_board = stat_board.duplicate(true)
		stat_board.apply_intrinsics()
		# #775 late-join amendment: a decoded snapshot pre-syncs
		# `stat_board.intrinsic_modifiers` itself (`StatBoard.read_dict`);
		# `core_modifiers` lives here instead, so the board cannot reach it
		# and asks us to via this signal — same helper, same timing (BEFORE
		# the per-stat reconcile that follows).
		stat_board.restoring.connect(_on_stat_board_restoring)
		if core_class != null:
			core_class.apply(self)
		if stat_board.xp != null:
			stat_board.xp.replenished.connect(_on_xp_replenished)
			# Re-emit XP grants on the bus keyed by self — same rationale as the
			# SP wound/heal forwards below (a stat doesn't know its owner).
			stat_board.xp.replenished_by.connect(_emit_entity_xp_gained)
		# Initiative clock crossed its cap → this entity is ready to act.
		# TurnManager serves from READY_GROUP; it removes us again on start_turn.
		if stat_board.initiative != null:
			stat_board.initiative.replenished.connect(_on_initiative_ready)
		# Re-emit SP wound/heal on the global Events bus, keyed by self so
		# floater layers don't need to bind per-entity. The signals on
		# SkillPointStat fire on transfers, not on every value_changed —
		# safe to forward without spam.
		if stat_board.skill_points != null:
			stat_board.skill_points.wounds_applied.connect(_emit_entity_wounded)
			stat_board.skill_points.wounds_healed.connect(_emit_entity_healed)
		# Core HP is the entity's `health` pool: combat-HP overflow on the core
		# node eats it (see SkillNode.take_damage), and it hits 0 → the entity
		# dies. The core node never emits `depleted` itself (#18).
		if stat_board.health != null:
			stat_board.health.depleted.connect(_on_health_depleted)
		# The single re-emit that stands in for every owned node's old binding
		# (#660). Connected once, here, for the entity's whole life.
		var node_hp_baseline: Stat = stat_board.get_stat(&"node_health")
		if node_hp_baseline != null:
			node_hp_baseline.value_changed.connect(node_health_cap_changed.emit)
	_board_sealed = true

	_turn_manager = _find_turn_manager()
	if _turn_manager != null:
		_turn_manager.turn_started.connect(_on_turn_started)
		_turn_manager.turn_ended.connect(_on_turn_ended)


#region Effects
## Attach [param effect] to this entity, optionally sourced from [param source_node]
## (a keystone or addon carrier). Runs `_on_granted`, which by default applies the
## effect's modifiers and — for an [AuraEffect] — computes its first buffed set.
##
## Call only once the entity's world is coherent: `navigator` live, `core_location`
## set, `stat_board` duplicated. An aura granted before then reads an empty subgraph.
func grant_effect(effect: Effect, source_node: SkillNode = null) -> EffectInstance:
	if effect == null:
		return null
	var inst := EffectInstance.new()
	inst.effect = effect
	inst.source_node = source_node
	inst.context = EffectContext.new(_combat, inst)
	_effect_instances.append(inst)
	for hook in effect.implemented_hooks():
		if not _hook_buckets.has(hook):
			_hook_buckets[hook] = []
		_hook_buckets[hook].append(inst)
	effect._on_granted(inst.context)
	return inst


## Detach an effect, reverting every modifier it granted (wherever it landed —
## this entity's board or any node's `node_board`).
func revoke_effect(inst: EffectInstance) -> void:
	if inst == null or not _effect_instances.has(inst):
		return
	inst.effect._on_revoked(inst.context)
	for hook in _hook_buckets:
		_hook_buckets[hook].erase(inst)
	_effect_instances.erase(inst)


## Revoke every effect a given node granted — the deallocation path. Node-bound
## effects are dormant while the node is unowned.
func revoke_effects_from(source_node: SkillNode) -> void:
	for inst in _effect_instances.duplicate():
		if inst.source_node == source_node:
			revoke_effect(inst)


## Fire [param hook] on every effect that implements it, passing its context
## first. Iterates a copy: a hook may grant or revoke effects re-entrantly.
func dispatch(hook: StringName, args: Array = []) -> void:
	var bucket: Array = _hook_buckets.get(hook, [])
	if bucket.is_empty():
		return
	# #647: two auras touching the same node board in ONE dispatch settle once,
	# not twice. The scope is what [method EntityCombat.hold_batch] batches into;
	# the boards actually touched are held open until the drain below, so a
	# dispatch that touches none pays nothing. The early return above is safe to
	# take unbracketed — nothing can have opened a batch yet.
	_combat.begin_dispatch()
	for inst: EffectInstance in bucket.duplicate():
		var call_args: Array = [inst.context]
		call_args.append_array(args)
		inst.effect.callv(hook, call_args)
	# Unconditional by construction — GDScript has no `finally`, so this is the
	# ONE close site, and the loop above has no `return`/`break` past it. A hook
	# that errors aborts its own frame and returns into `callv`, so the drain
	# still runs; a hook that grants or revokes re-entrantly nests the scope
	# (see [method EntityCombat.begin_dispatch]) rather than escaping it.
	_combat.end_dispatch()


func get_effects() -> Array[EffectInstance]:
	return _effect_instances.duplicate()


## Increment [param tag]'s refcount, creating the entry at 1 if new.
func add_tag(tag: StringName) -> void:
	_combat.add_tag(tag)


## Decrement [param tag]'s refcount; drops the entry entirely at 0 so
## [method get_active_tags] only ever reports what's actually live.
func remove_tag(tag: StringName) -> void:
	_combat.remove_tag(tag)


func has_tag(tag: StringName) -> bool:
	return _combat.has_tag(tag)


## How many times [param tag] is currently applied; 0 when it is not held.
##
## The count, not just the name, is what crosses in an [EntitySnapshot] (#561):
## a tag applied twice and removed once is still active, so a resync that
## restored names only would collapse every stacked marker to one application —
## the repair path silently becoming the bug.
func get_tag_count(tag: StringName) -> int:
	return _tags.get(tag, 0)


## The live tag set — no [StatRegistry] entry, no board slot.
func get_active_tags() -> Array[StringName]:
	var out: Array[StringName] = []
	for t in _tags:
		out.append(t)
	return out
#endregion


## Listens for TurnManager.turn_started. Each entity self-handles its own
## start-of-turn upkeep so we don't grow a god-mode TurnManager. Per-turn
## bookkeeping today: replenish pools (per each pool's per_turn_mode, including
## skill_points' CUSTOM wound-heal), run the gated node regen sweep (D-9), run
## the class hook, then dispatch `_on_turn_start` — which is where a class's
## healing aura (D-10, `HealAuraEffect` on `CoreClass.effects`, #720) lands.
##
## NONE of it runs on the entity's FIRST turn: you open the game in the state
## you spawned in, not one free tick of income richer. Every pool is authored at
## its cap on `default_entity_board.tres`, so the skipped REFILLs and the
## health/mana ADDs were no-ops anyway — what the skip actually removes is a
## turn of `xp_per_turn` that used to level a fresh entity before it had made a
## single move. See [member turns_taken].
## Registers [param node] on this entity's sparse spikes-spent set — called
## by [method BladePopResolver.LiveGate._mark_spent] the moment a melee
## contact drains the node's `spikes` pool on the LIVE world (never a shadow
## — see that method's doc). [method _on_turn_started] is the sole reader,
## regenerating exactly this set once per turn and clearing it.
func mark_spikes_spent(node: SkillNode) -> void:
	if node != null:
		_spiked_nodes_spent[node] = true


## True iff a [ReloadCommand] from this entity would do something: it has a
## [Quiver] and can pay the 1 AP. The turn-cursor half of the gate is
## [CommandApplier]'s.
func can_reload() -> bool:
	if stat_board == null or stat_board.arrows == null:
		return false
	var ap := stat_board.action_points
	return ap == null or ap.available() >= 1


## The projected [method reload] mint, `{AmmoType.id: n}` in roster order,
## PRE-capacity ([method Quiver.add] clamps at reload time). The base arrow's
## `arrows_per_reload` is summed node-locally over the turn-start leaf set
## ∪ core (allocation level and Watchtower bonuses live on the node board,
## see `default_node_board.tres`); each special's `<id>_arrows_per_reload`
## is flat off the entity board. The one implementation both [method reload]
## and the Quiver tray's reload row (#954) read, so the row never promises
## arrows the command will not mint.
func reload_yield() -> Dictionary:
	# Leaves ∪ core as a SET: a core with one neighbour is itself a leaf, and
	# it must not mint twice. A leaf lost since turn start (attack, forced
	# dealloc) no longer produces — `owned_by == self` is exactly the
	# "is this that one entity's node" question (ownership-vocabulary rule).
	var producers: Dictionary[SkillNode, bool] = {}
	for n in _turn_start_leaves:
		if is_instance_valid(n) and n.owned_by == self:
			producers[n] = true
	if core_location != null:
		producers[core_location] = true
	var out: Dictionary = {}
	for t in _AMMO_TYPES.sorted():
		var n_minted := 0
		if t.id == AmmoTypeRoster.BASE_ID:
			for node in producers:
				n_minted += int(node.get_local_value(t.per_reload_stat_id))
		elif stat_board != null:
			var flat := stat_board.get_stat(t.per_reload_stat_id)
			n_minted = int(flat.get_value()) if flat != null else 0
		if n_minted > 0:
			out[t.id] = n_minted
	return out


## Reload the quiver (#955): 1 AP, then every AmmoType gets its
## [method reload_yield] mint, clamped by capacity. Returns the number of
## arrows actually added. A full quiver still pays.
func reload() -> int:
	if not can_reload():
		return 0
	var quiver: Quiver = stat_board.arrows
	if stat_board.action_points != null:
		stat_board.action_points.deplete(1)
	var added := 0
	var mint := reload_yield()
	for id in mint:
		added += quiver.add(id, int(mint[id]))
	return added


func _on_turn_started(entity: Entity) -> void:
	if entity != self or stat_board == null:
		return
	# An ADOPTED cursor is not a turn beginning (#756) — it is the authority's
	# turn arriving inside a snapshot that already holds everything the lines
	# below would compute, [member turns_taken] included. See
	# [member TurnManager.is_adopting].
	if _turn_manager != null and _turn_manager.is_adopting:
		return
	# The reload producer set (#955), before the first-turn gate below: the
	# opening turn has no income, but it may reload — the quiver starts empty.
	_turn_start_leaves = navigator.get_leaf_nodes() if navigator != null \
			else ([] as Array[SkillNode])
	# Counted before the gate, so the tally stays honest about turns SERVED.
	turns_taken += 1
	# #956: the volley budget is per turn, first turn included — above the
	# turns_taken == 1 upkeep skip on purpose.
	volleys_launched_this_turn = 0
	if turns_taken > 1:
		_apply_turn_upkeep()
	# The entity-hosted status tick (#996): after the pool upkeep above (so
	# `core_healing` lands before a DoT drains), before the node ticks
	# ([signal Events.turn_started] fires once this handler returns — the
	# existing order). Every real turn, the first included, exactly like a
	# node's tick — a poison landed before your first turn ticks on it.
	_combat.tick_statuses()


## The per-turn upkeep of a turn that is not the entity's first: pools,
## node regen, class hook, spike regen, the `_on_turn_start` dispatch.
func _apply_turn_upkeep() -> void:
	# All pool upkeep is declarative — each pool replenishes per its def's
	# per_turn_mode (AP/DP/movement REFILL, mana/xp ADD, skill_points CUSTOM
	# wound-heal, health HOST_ADD). New pools opt in via their def; nothing is
	# wired here beyond the HOST_ADD hand-off below.
	stat_board.apply_per_turn_upkeep()
	# #997: a HOST_ADD pool's companion enters through THIS host's heal door,
	# so `healing_received` is consulted exactly once — `health` ← `core_healing`
	# — and an entity-hosted Wither inverts the trickle like any node heal.
	# The door only knows `health`; the mode is declared on the def, the
	# route is here, and a pool that is not `health` cannot take it.
	for pool in stat_board.get_pool_stats():
		var amount: float = pool.host_upkeep_amount(stat_board)
		if amount <= 0.0:
			continue
		if pool.definition.id != &"health":
			push_warning("Entity: HOST_ADD pool '%s' has no host door (only `health` does)" % pool.definition.id)
			continue
		# The door's `source` is a HitInstance or null — the per-turn stat
		# id it used to carry was read by nothing. A HealInstance gets
		# `effective_amount` and the bar numbers written back.
		var heal := HealInstance.new()
		heal.amount = amount
		heal.attacker = self
		heal.target = core_location
		heal.origin = core_location
		_combat.heal(amount, heal)
	# D-9: turn-start refill-to-full is gone. Every owned node instead runs a
	# gated, ramping regen (SkillNode.apply_turn_regen) — damage persists
	# across turns. D-10's class aura (now a HealAuraEffect on
	# core_class.effects, #720) is layered on top via the `_on_turn_start`
	# dispatch below: it walks the OWNED subgraph itself (never
	# graph.navigator — see .claude/rules/graph.md "Reach queries") and heals
	# outside this gate, through combat and with no ramp.
	if navigator != null:
		for n in navigator.get_mirrored_nodes():
			n.apply_turn_regen()
	if core_class != null:
		core_class.on_turn_started(self)
	# #778: sparse spikes regen — exactly the nodes marked spent since the
	# last upkeep, never a sweep of the whole owned subgraph (see
	# _spiked_nodes_spent's doc for why that sweep is unaffordable). No
	# dormant-node exception, deliberately: an owner who never reaches this
	# method never regenerates, and a node under a blocker absorbing a finite
	# number of pops for the whole run is the intended behaviour (#778).
	for n in _spiked_nodes_spent:
		if not is_instance_valid(n):
			continue
		var b := n.get_combat().board()
		var pool := b.get_stat(&"spikes") as PoolStat if b != null else null
		if pool == null:
			continue
		var regen: float = float(n.get_local_value(&"spike_regen"))
		if regen > 0.0:
			pool.replenish(regen)
	_spiked_nodes_spent.clear()
	dispatch(&"_on_turn_start")


## Listens for TurnManager.turn_ended. Transfers unused action points into next
## turn's DP/MP surplus (#152), then runs effect dispatch. Surplus is written
## here — not on turn start — because unused AP is only known once the turn is
## over; turn-start REFILL then leaves the surplus untouched (it sits outside the
## cap). set_surplus *overwrites*, so a turn ending with 0 unused AP self-clears
## last turn's boost.
func _on_turn_ended(entity: Entity) -> void:
	if entity != self:
		return
	_transfer_unused_ap_to_surplus()
	# #956: per-leaf shot budget resets at the FIRER's turn end, over exactly
	# the nodes it fired from — never a sweep — and whoever owns them now.
	for n in _fired_nodes_this_turn:
		if is_instance_valid(n):
			n.shots_fired_this_turn = 0
	_fired_nodes_this_turn.clear()
	dispatch(&"_on_turn_end")


func _transfer_unused_ap_to_surplus() -> void:
	if stat_board == null or stat_board.action_points == null:
		return
	# `ap_transfer_rate` is a real board stat, so class identity (Pacifist ↑,
	# Berserker → 0) and future DEX scaling tune it via modifiers, no code change.
	# roundi the *product* so a fractional rate doesn't truncate the unused AP.
	var rate: float = stat_board.ap_transfer_rate.get_value() if stat_board.ap_transfer_rate != null else DEFAULT_AP_TRANSFER_RATE
	var boost := roundi(stat_board.action_points.current * rate)
	if stat_board.deallocation_points != null:
		stat_board.deallocation_points.set_surplus(boost)
	if stat_board.movement_points != null:
		stat_board.movement_points.set_surplus(boost)


## Listens for initiative.replenished (clock crossed its cap). Joins the ready
## group; TurnManager picks the highest-overshoot member and removes it on
## start_turn. The CyclicPoolStatDef has already carried the overshoot forward,
## so `current` is back near zero — readiness is the group membership, not the value.
func _on_initiative_ready() -> void:
	add_to_group(READY_GROUP)


## Listens for xp.replenished (pool crossed into full). Pool growth + current
## carry-over are handled by the def when it's a `GrowablePoolStatDef`; here
## we mint 1 SP via grant() (bumps both max and current), bump the `level` stat,
## and emit leveled_up. Writing base_value auto-emits value_changed, so any
## level-scaling formula modifier bound to `level` recalculates (#200/#194).
func _on_xp_replenished() -> void:
	if stat_board == null or stat_board.xp == null:
		return
	if stat_board.level != null:
		stat_board.level.base_value += 1
	if stat_board.skill_points != null:
		stat_board.skill_points.grant(sp_minted_for_level(level))
	leveled_up.emit(level)
	dispatch(&"_on_level_up", [level])

## How many skill points reaching `lvl` mints. A pure function of the level
## number, deliberately: the model applies a whole multi-level cascade in one
## synchronous call, so by the time the HUD narrates level 3 of 4, `self.level`
## already reads 6 — anything narrating a *past* beat must ask about that
## beat's level, not the entity's current one.
##
## D-16 (#271): the per-level yield is a stat, not a hardcoded 1, so a
## CoreClass/keystone/node can deviate through the normal modifier pipeline.
## Falls back to 1 for sparse boards with no such stat. The milestone bonus
## (+1 on every 5th level) rides on top and lives ONLY here — #320 item 7.
func sp_minted_for_level(lvl: int) -> int:
	var sp_gain := 1
	if stat_board != null and stat_board.sp_gain_on_levelup != null:
		sp_gain = roundi(stat_board.sp_gain_on_levelup.value)
	if lvl % MILESTONE_LEVEL_INTERVAL == 0:
		sp_gain += 1
	return sp_gain


## Listens for health.depleted (Entity's core health reduced to 0) → entity dies.
func _on_health_depleted() -> void:
	die()


## Mark the entity dead and announce it. Entity stays dumb here: the actual
## cleanup (force-deallocate every owned node, free NPCs, player game-over) is
## owned by systems reacting to `Events.entity_died` off the bus — same pattern
## as BattleSystem←skill_node_depleted. Idempotent: death can fire re-entrantly
## from inside a forced-dealloc cascade (chip damage to `health`), so guard.
func die() -> void:
	if is_dead:
		return
	# Load-bearing ORDER, not just an idempotency latch: this must be set
	# before `entity_dying` emits below, because `LootSystem._on_cascade_started`
	# (#837) reads `defender.is_dead` to tell BattleSystem's core-outward
	# death wave apart from a live combat cascade — both fire the same
	# `cascade_started` signal, and only this ordering makes "already true by
	# the time the death wave's own entity_dying handler runs" hold.
	is_dead = true
	# The entity-hosted rows die with it (#996) — the live twin of
	# `simulate_entity_death`'s clear; `is_allocated()` (alive) gates any
	# later apply. Before `died` so no listener sees a corpse still ticking.
	_combat.clear_statuses()
	died.emit()
	# Before the bus phases: effects see the corpse fully intact (nodes still
	# owned, modifiers still applied), same pre-strip world LootSystem relies on.
	dispatch(&"_on_entity_dying")
	# Two-phase, in order: `entity_dying` fires with the corpse still intact
	# (LootSystem snapshots loot + awards XP here), THEN `entity_died` drives
	# cleanup (AllocationSystem strips nodes, GameRoot despawns). emit() is
	# synchronous, so every dying-handler finishes before any died-handler —
	# the phases sequence themselves, no tree-order dependency. See Events.
	Events.entity_dying.emit(self)
	Events.entity_died.emit(self)
	# #504: the death is drawn at the moment the model dies, so this fires here
	# rather than out of a replayed timeline. LAST, after `entity_died`, because
	# GameRoot's handler for it despawns the corpse and AllocationSystem's
	# `entity_died` strip must have run against a still-owned world first (see
	# `.claude/rules/entity-death.md`).
	Events.entity_death_shown.emit(self)


func _emit_entity_wounded(amount: int) -> void:
	Events.entity_wounded.emit(self, amount)


func _emit_entity_healed(amount: int) -> void:
	Events.entity_healed.emit(self, amount)


func _emit_entity_xp_gained(amount: float) -> void:
	Events.entity_xp_gained.emit(self, amount)


## Group lookup, not tree walk: TurnManager lives at `GameRoot/Systems/...`,
## a sibling of Graph, so an ancestor get_children() walk never reaches it.
## TurnManager joins its group in `_enter_tree`, which fires before any
## spawned entity's _ready.
func _find_turn_manager() -> TurnManager:
	if turn_manager_override != null:
		return turn_manager_override
	return get_tree().get_first_node_in_group(TurnManager.GROUP) as TurnManager


## The entity's Graph: [member graph_override] when a scene wired one, otherwise
## the nearest Graph ancestor.
func _find_graph() -> Graph:
	if graph_override != null:
		return graph_override
	var n: Node = get_parent()
	while n != null:
		if n is Graph:
			return n as Graph
		n = n.get_parent()
	return null


func _to_string() -> String:
	return "Entity<%s--%s>" % [display_name, core_location as Variant if core_location else 'N/A']
