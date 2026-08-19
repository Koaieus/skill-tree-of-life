@tool
class_name BattleSystem
extends Node

enum AttackMode {
	NONE,
	MELEE,
	RANGED,
	MAGIC
}

signal attack_plan_changed(plan: AttackPlan)
## Fired once a launch commits (resource checks passed, about to resolve).
## `spell` is the active [MagicAttackPlan]'s spell, null for melee/ranged.
## Consumed by [AnnouncementLayer] (#117, #135) for the mode-tinted CALLOUT FX.
signal attack_launched(mode: AttackMode, spell: SpellDef)
## Fires for both plan swap and plan-internal mutation. Subscribers that
## care about lifecycle (mount per-mode UI) use [signal attack_plan_changed];
## subscribers that care about content (re-paint highlights) use this one.
signal attack_plan_state_changed

## Forced-deallocation cascade about to run. `layers[i]` holds every cascade
## node at BFS graph-distance `i` from the impact node; `layers[0] == [impact]`.
## Emitted BEFORE the synchronous force_deallocate loop so VFX can snapshot
## owner colour + schedule a staggered ripple. See docs/domain/allocation-vfx.md.
signal cascade_started(layers: Array, defender: Entity)

## #485: this cascade's chip damage is about to kill [param defender], which
## finishes the entity-death strip — [param nodes] is whatever territory that
## strip is about to take beyond this cascade's own [signal cascade_started]
## set (usually the core). Deliberately NOT folded into `cascade_started`'s
## `layers` — [LootSystem] reads that signal as this cascade's removal set and
## separately accounts for the core; see the emitter in `_on_node_depleted`
## for the double-pay this caused when tried. [param impact] is the same
## impact node `cascade_started` fired with, for a consumer that wants to
## chain its stagger off the same reveal.
signal death_strip_scheduled(nodes: Array[SkillNode], defender: Entity, impact: SkillNode)

## The currently-selected spell for magic attacks. Updated by the spell-picker
## UI; consumed by [method _new_plan] when constructing a [MagicAttackPlan].
## Null means "use the plan's bundled fallback". Live mutation is supported:
## changing this while a magic plan is active re-equips on the active plan
## via [method MagicAttackPlan.set_spell].
signal selected_spell_changed(spell: SpellDef)
var selected_spell: SpellDef = null:
	set(value):
		if selected_spell == value:
			return
		selected_spell = value
		if attack_plan is MagicAttackPlan:
			(attack_plan as MagicAttackPlan).set_spell(value)
		selected_spell_changed.emit(value)

@export var turn_manager: TurnManager
@export var allocation_system: AllocationSystem
@export var graph: Graph
@export var attack_vfx: AttackVFX
@export var melee_preview: MeleePreview

## Presentation clock (#485): entity-level wound-toast holds pending release,
## keyed by the impact node whose `node_death_shown` reveal is what releases
## them. See `_on_node_depleted` / `_on_node_death_shown`.
var _pending_wound_reveals: Dictionary[SkillNode, Entity] = {}

## Presentation clock (#487): the core `health` bar's pending reveals, keyed
## by whichever SkillNode's own reveal releases them — a cascaded node (chip
## damage) or a core node hit directly (overflow damage, via
## [signal Events.core_health_chipped]). Entry: `{"defender": Entity, "delta": float}`.
## Released by [method _release_pending_health], called from both
## `_on_damage_shown` (core overflow — the core node never emits
## `node_death_shown`) and `_on_node_death_shown` (cascade chip).
var _pending_health_reveals: Dictionary[SkillNode, Dictionary] = {}


var attack_plan: AttackPlan:
	set(value):
		if attack_plan == value:
			return
		if attack_plan != null and attack_plan.state_changed.is_connected(_on_plan_state_changed):
			attack_plan.state_changed.disconnect(_on_plan_state_changed)
		attack_plan = value
		if attack_plan != null:
			attack_plan.state_changed.connect(_on_plan_state_changed)
		attack_plan_changed.emit(value)
		attack_plan_state_changed.emit()


func _on_plan_state_changed() -> void:
	attack_plan_state_changed.emit()

var attack_mode: AttackMode:
	get(): return attack_plan.mode if attack_plan else AttackMode.NONE

var is_attacking: bool:
	get(): return attack_plan != null

## True while resolve()..VFX-await..AP-deduction is in flight, independent
## of whether attack_plan is still set (#406 — the plan now stays live
## through the melee await so its temp-upgrade addons render correctly).
## The one thing that blocks a second launch_attack() mid-swing.
var is_launching := false

func cancel_attack() -> void:
	if is_attacking and not is_launching:
		_reset()
	else:
		push_warning('Cannot cancel attack: not attacking, or a swing is resolving')


## Clear the active plan's selection state without dropping the plan itself —
## keeps the mode set and any sticky preferences (melee swing_cw, magic spell)
## alive. UI's RESET button routes here.
func reset_plan() -> void:
	if attack_plan != null and not is_launching:
		attack_plan.reset()

## The single choke point that tears a plan down (#406) — always calls
## reset() first, so a plan's attached temp-upgrade addons (real SkillNode
## children, not plan-owned state) are freed no matter which path got here:
## cancel, RESET-adjacent teardown, or post-launch.
func _reset() -> void:
	if attack_plan:
		attack_plan.reset()
		attack_plan = null

func request_attack_mode(mode: AttackMode) -> void:
	if is_launching or attack_mode == mode:
		return
	match mode:
		AttackMode.NONE:    cancel_attack()
		AttackMode.MELEE:   attack_plan = _new_plan(MeleeAttackPlan)
		AttackMode.RANGED:  attack_plan = _new_plan(RangedAttackPlan)
		AttackMode.MAGIC:   attack_plan = _new_plan(MagicAttackPlan)

func _new_plan(plan_class: Script) -> AttackPlan:
	var p: AttackPlan = plan_class.new()
	p.attacker = turn_manager.current_entity
	if p is MagicAttackPlan and selected_spell != null:
		(p as MagicAttackPlan).spell = selected_spell
	if p is MeleeAttackPlan:
		(p as MeleeAttackPlan).swing_cw = next_melee_cw
	return p


## Sticky preference for the next [MeleeAttackPlan]'s [member MeleeAttackPlan.swing_cw].
## Toggled by UI; survives plan resets so the player doesn't re-pick direction
## every time they switch into melee mode.
var next_melee_cw: bool = false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	Events.skill_node_depleted.connect(_on_node_depleted)
	# Presentation clock (#482): one connection for the whole board — a per-node
	# subscription would sweep every SkillNode on every emit (skill-node-scale).
	Events.damage_shown.connect(_on_damage_shown)
	Events.node_death_shown.connect(_on_node_death_shown)
	Events.heal_shown.connect(_on_heal_shown)
	Events.core_health_chipped.connect(_on_core_health_chipped)


## A hit has visually landed: let its target's withheld paint through — one
## slot off the refcount (#487), not a full release, if a volley put more
## than one hold on this node. `amount` is this hit's positive HP magnitude;
## `release_presentation` wants the SIGNED pool delta, so damage steps down.
func _on_damage_shown(target: SkillNode, amount: float) -> void:
	if target != null:
		target.release_presentation(-amount)
	_release_pending_health(target)


func _on_node_death_shown(node: SkillNode) -> void:
	if node != null:
		# announce_death=false: this call is ITSELF a response to
		# Events.node_death_shown (whether from a coordinator, AllocationVFX's
		# cascade ripple, or this node's own auto-announce on full release) —
		# re-announcing here would just re-trigger this same handler (#487).
		node.release_presentation(0.0, false)
	# Presentation clock (#485): the impact node's reveal is also what lets
	# the wound TOAST through — see `_on_node_depleted`'s hold and
	# `_pending_wound_reveals`.
	if node != null and _pending_wound_reveals.has(node):
		var stored_defender = _pending_wound_reveals[node]
		_pending_wound_reveals.erase(node)
		if is_instance_valid(stored_defender):
			var defender: Entity = stored_defender
			defender.release_wound_presentation()
	_release_pending_health(node)


## A heal has visually landed: let its target's withheld paint through. Mirrors
## [method _on_damage_shown] — heals step the shown HP up.
func _on_heal_shown(target: SkillNode, amount: float) -> void:
	if target != null:
		target.release_presentation(amount)


## A direct hit overflowed a core node's own combat HP into its owner's
## `health` pool (#487) — queue the core bar's reveal to release on THIS
## node's own damage/death reveal (below), never earlier.
func _on_core_health_chipped(node: SkillNode, entity: Entity, delta: float) -> void:
	if node == null or entity == null:
		return
	_pending_health_reveals[node] = {"defender": entity, "delta": delta}
	# #479: a direct core hit that empties `health` in one blow bypasses
	# `_on_node_depleted` entirely (the core never emits `depleted`), so the
	# cascade-chip-damage lethality PREDICTION above never runs for this path.
	# No prediction needed here though — `SkillNode.take_damage` already ran
	# `health.deplete(overflow)` (which synchronously fires `depleted` →
	# `Entity.die()`) before emitting `core_health_chipped`, so `entity.is_dead`
	# is exact truth by the time this handler runs. Stagger the rest of the
	# territory off THIS node's own reveal, same as the cascade path.
	# The core ITSELF stays excluded (mirrors the cascade path excluding its
	# impact node from `extra`) — it's already held once by [OutcomeApplier]
	# as the direct hit target and releases off its own `damage_shown`; adding
	# it to the death-strip snapshot list too would double the hold with no
	# second release to match ([AllocationVFX._fire_cascade_slot] deliberately
	# skips re-releasing the impact node), leaving its paint stuck forever.
	# Its own shatter still happens — [AllocationSystem]'s later
	# `force_deallocate` on the core fires the standalone (unstaggered)
	# fallback in [AllocationVFX._on_force_deallocated], same as any
	# non-cascade dealloc.
	if entity.is_dead:
		var extra := _remaining_owned_nodes(entity, [node])
		if not extra.is_empty():
			death_strip_scheduled.emit(extra, entity, node)


## Release [param node]'s queued core-health chip, if any — called from both
## `_on_damage_shown` (a direct core hit; the core node never emits
## `node_death_shown`) and `_on_node_death_shown` (a cascaded node's chip).
func _release_pending_health(node: SkillNode) -> void:
	if node == null or not _pending_health_reveals.has(node):
		return
	var entry: Dictionary = _pending_health_reveals[node]
	_pending_health_reveals.erase(node)
	var stored_defender = entry.get("defender")
	if is_instance_valid(stored_defender):
		var defender: Entity = stored_defender
		defender.release_health_presentation(float(entry.get("delta", 0.0)))


## Commit the active plan. Three phases:
##   1. resolve() → AttackOutcome (pure, no side-effects on plan/world)
##   2. apply the WHOLE outcome synchronously — hits, heals, and (via
##      SkillNode.take_damage → Events.skill_node_depleted) the forced-dealloc
##      cascade — before any await runs (#474: host-authoritative sync needs
##      world state to be a pure function of the resolved outcome, never of a
##      peer's own animation framerate)
##   3. hand the already-applied outcome to VFX as a PURE OBSERVER — it may
##      read `outcome`/`melee_plan.last_events` to time its playback but must
##      never mutate; then AP/plan cleanup
##
## AP is deducted up front; the plan itself stays live through the whole
## await (#406 — a melee plan's attached temp-upgrade addons must keep
## rendering through the live swing) and is cleared in one place, after.
## `is_launching` — not `attack_plan != null` — is what blocks a second
## launch_attack() call during the await window.
func launch_attack() -> void:
	if not is_attacking or is_launching:
		push_warning("BattleSystem.launch_attack: no plan, or already launching")
		return
	if not attack_plan.is_valid():
		push_warning("BattleSystem.launch_attack: invalid plan: %s" % str(attack_plan.validate()))
		return
	var entity := turn_manager.current_entity if turn_manager != null else null
	if entity == null:
		push_warning("BattleSystem.launch_attack: no current entity")
		return
	var outcome := attack_plan.resolve()
	var board: StatBoard = entity.stat_board
	var ap_pool: PoolStat = board.action_points if board != null else null
	if ap_pool != null and ap_pool.available() < outcome.ap_cost:
		push_warning("BattleSystem.launch_attack: insufficient AP (%d < %d)" \
				% [int(ap_pool.current), outcome.ap_cost])
		return
	var mana_pool: PoolStat = board.mana if board != null else null
	if outcome.mana_cost > 0 and mana_pool != null \
			and mana_pool.available() < outcome.mana_cost:
		push_warning("BattleSystem.launch_attack: insufficient mana (%d < %d)" \
				% [int(mana_pool.current), outcome.mana_cost])
		return
	is_launching = true
	if ap_pool != null:
		ap_pool.deplete(float(outcome.ap_cost))
	if outcome.mana_cost > 0 and mana_pool != null:
		mana_pool.deplete(float(outcome.mana_cost))
	var launched_spell: SpellDef = (attack_plan as MagicAttackPlan).spell if attack_plan is MagicAttackPlan else null
	attack_launched.emit(attack_plan.mode, launched_spell)
	# Costs are already deducted; the plan is still live, so an effect can read
	# its targets. Replaces the issue's `_on_battle_start` — there is no battle.
	if attack_plan.attacker != null:
		attack_plan.attacker.dispatch(&"_on_attack_launched", [attack_plan.mode, launched_spell])
	# World mutation happens here, synchronously, for every mode — before any
	# VFX await starts. Whether attack_vfx/melee_preview is null or live, the
	# resulting world state is identical (#474 acceptance).
	_apply_outcome(outcome)
	# Melee: hand off to the MeleePreview (which has the ghost mounted) for a
	# PURE-ANIMATION replay of the swing already applied above. The plan stays
	# live (attack_plan is NOT cleared) through the whole await — its
	# temp-upgrade addons (#406) must stay attached and rendering through both
	# the ghost preview loop and the actual committed swing. _reset() (which
	# frees them) runs once, after.
	if attack_plan is MeleeAttackPlan and melee_preview != null:
		var melee_plan: MeleeAttackPlan = attack_plan
		await melee_preview.launch(melee_plan)
		_flush_presentation(outcome)
		# is_launching flips false BEFORE _reset() (not after) — _reset()'s
		# attack_plan = null synchronously fires attack_plan_changed, and
		# PlayerInputController's gate-refresh listener reads is_launching
		# the instant that signal fires. Clearing it after would have that
		# listener observe a stale "still launching" and never re-enable
		# AttackModeBar.
		is_launching = false
		_reset()
		return
	var coord_scene: PackedScene = null
	if attack_plan is MagicAttackPlan:
		var magic_plan: MagicAttackPlan = attack_plan
		if magic_plan.spell != null:
			coord_scene = magic_plan.spell.vfx_coordinator_scene
	if attack_vfx != null:
		if coord_scene != null:
			await attack_vfx.play(coord_scene, outcome)
		else:
			await attack_vfx.play_ranged_volley(outcome)
	_flush_presentation(outcome)
	is_launching = false
	_reset()


## Make the presentation events TOTAL for this attack's direct hits and heals
## (#482 / #481/#482).
##
## The VFX coordinators are the normal emitters, but they only run when one is
## mounted and unmuted — headless tests, a null `attack_vfx`, a melee plan with
## no preview, or a spell with no coordinator scene all skip them. Any target
## still holding its paint by the time the awaits are done therefore never got
## its reveal, so we emit it here: same signal, same subscribers (SkillNode
## paint, AuraOverlay, AllocationVFX cascade), just at the end of the attack
## instead of mid-flight. Without this the latch would fail *open* and leave a
## hit node showing its pre-hit tint forever.
##
## Deduped per target, and per HIT (#487) — a multi-hit spell/volley can list
## the same node several times, one hold per hit; looping `outcome.hits` and
## emitting once per hit drains exactly as many holds as were taken. The emit
## itself is what releases (`_on_damage_shown`/`_on_heal_shown`, connected in
## `_ready`) — no separate release call here, and no manual `node_death_shown`
## emit either: [method SkillNode.release_presentation] announces a hit
## target's own death itself, exactly once, on its OWN final release (see its
## `announce_death` param) — emitting it again per-hit here is what used to
## double-drain a multi-hit volley's refcount.
func _flush_presentation(outcome: AttackOutcome) -> void:
	for hit in outcome.hits:
		var target: SkillNode = hit.target
		if target == null or not target.presentation_hold:
			continue
		if hit.kind == HitInstance.Kind.HEAL:
			Events.heal_shown.emit(target, hit.effective_amount)
		else:
			Events.damage_shown.emit(target, hit.effective_amount)
	# Cascade nodes (forced-dealloc'd by `_on_node_depleted`, never listed in
	# `outcome.hits`) are held by THIS system, not [OutcomeApplier] — their
	# `_pending_wound_reveals`/`_pending_health_reveals` entries only release
	# off `Events.node_death_shown`, which only [AllocationVFX] emits, and only
	# when it's mounted. Same fail-open contract as the loop above: whatever's
	# still queued when the awaits are done gets its reveal here instead of
	# never — otherwise an unmounted-VFX attack (headless test, no `attack_vfx`)
	# leaves the entity's health/wound presentation withheld forever, which
	# now also means [signal Events.entity_death_shown] never fires and a dead
	# entity's corpse never despawns (see `Entity.release_health_presentation`).
	#
	# Only drain a node with NOTHING left holding it (`not n.presentation_hold`)
	# — AllocationVFX's own ripple runs on `CASCADE_STEP` timers that outlive
	# this await, so a still-held node has a real reveal coming and force-firing
	# here would collapse #487's staggered core-bar chip into one frame.
	var pending_reveal_nodes: Dictionary[SkillNode, bool] = {}
	for n in _pending_wound_reveals:
		pending_reveal_nodes[n] = true
	for n in _pending_health_reveals:
		pending_reveal_nodes[n] = true
	for n in pending_reveal_nodes:
		if n != null and not n.presentation_hold:
			Events.node_death_shown.emit(n)


## The one place world mutation happens for an attack: every hit in
## [member AttackOutcome.hits] lands via [OutcomeApplier] — which, via
## take_damage → Events.skill_node_depleted → _on_node_depleted (both
## synchronous), also runs the forced-dealloc cascade. VFX never calls this;
## it only replays what already landed. See the class-level VFX note.
##
## Presentation clock (#482): [OutcomeApplier] withholds each target's paint
## BEFORE the model moves, so tint / allocation-fill / HP bar keep the
## pre-hit look until the VFX actually arrives. Released by
## `_on_damage_shown` / `_on_heal_shown` / `_on_node_death_shown` — and
## `_flush_presentation` guarantees one of those fires.
func _apply_outcome(outcome: AttackOutcome) -> void:
	OutcomeApplier.apply(outcome)


## Forced-deallocation cascade. Runs when a (non-core) node hits 0 HP: the
## depleted node and every node disconnected from the defender's core when
## it leaves are force-dealloc'd. Each cascaded node costs the defender:
##   * 1 wounded SP — currency exchange (invested SP → wounded, reserves a
##     slot in the pool until healed, mirrors PoE mana reservation).
##   * `dealloc_damage` HP off the entity's `health` pool — bypass-mitigation
##     chip damage tunable per class.
##
## "Forced-deallocation lives elsewhere" in AllocationSystem comments —
## that elsewhere is here.
func _on_node_depleted(node: SkillNode) -> void:
	if node == null or allocation_system == null:
		return
	var defender: Entity = node.owned_by
	if defender == null:
		return
	# Cascade snapshot — must be computed BEFORE removing the depleted node
	# from the navigator mirror, or its islanded set goes stale.
	var cascade: Array[SkillNode] = [node]
	if defender.navigator != null and defender.core_location != null:
		cascade.append_array(defender.navigator.nodes_islanded_by_removing(
				node, defender.core_location))
	var board: StatBoard = defender.stat_board
	# Per-cascade dealloc damage — read once, applied per cascaded node. Older
	# hand-authored boards lacking the stat fall back to the def default (1).
	var hp_per_node: float = 1.0
	if board != null and board.dealloc_damage != null:
		hp_per_node = float(board.dealloc_damage.value)
	# BFS the cascade set from impact (in original graph topology) so VFX can
	# ripple outward layer-by-layer. Computed before force_deallocate to keep
	# the navigator state coherent — graph edges still exist either way, but
	# owner state is what changes mid-loop.
	var layers: Array = _cascade_layers(node, cascade)
	cascade_started.emit(layers, defender)
	# #485: predict whether this cascade's chip damage finishes the defender
	# off. If so, the entity-death strip (`AllocationSystem.deallocate_all_owned`,
	# about to run synchronously from inside the loop below via
	# `health.deplete → depleted → die() → entity_died`) is about to force-dealloc
	# the REST of its territory. `death_strip_scheduled` is a SEPARATE signal from
	# `cascade_started` deliberately — `LootSystem._on_cascade_started` treats
	# `layers` as this cascade's removal set and adds its own +1 for the core
	# (`_award_kill_xp`'s "`_held_nodes` excludes the core" contract); folding the
	# death strip into `layers` double-paid the core (60 XP vs 50, caught by
	# test_kill_xp_ledger.gd). AllocationVFX is the only other subscriber and
	# stitches this into the SAME visual ripple via its own manifest, so the
	# separation costs nothing visually. Only covers death via THIS chip-damage
	# path — a direct core hit that empties `health` in one blow bypasses
	# `_on_node_depleted` entirely (core never emits `depleted`, see
	# entity-death.md) and is not covered here.
	if board != null and board.health != null:
		var predicted_chip: float = 0.0
		for n in cascade:
			if n != null and n.owned_by == defender:
				predicted_chip += hp_per_node * float(maxi(n.allocation_level, 1))
		if predicted_chip >= board.health.current:
			var extra := _remaining_owned_nodes(defender, cascade)
			if not extra.is_empty():
				death_strip_scheduled.emit(extra, defender, node)
	# #485: hold the wound TOAST until this impact's reveal — see
	# `_on_node_death_shown` / `Entity.release_wound_presentation`. Recorded
	# even when this cascade wounds nothing (defensive; `wound()` below is
	# what actually accumulates an amount to reveal).
	defender.hold_wound_presentation()
	_pending_wound_reveals[node] = defender
	for n in cascade:
		if n == null or n.owned_by != defender:
			continue
		# Snapshot the fill BEFORE force_deallocate — owner_changed zeroes
		# allocation_level via _refresh_alloc_count, so any read after the
		# call returns 0 and the wound count / damage multiplier would silently
		# collapse (#337; same shape as LootSystem's pre-cleanup snapshot). A
		# 2/2 node costs 2 wounds and 2x dealloc_damage; the maxi(1, ·) floor
		# keeps the pre-staking 1/1 costs exactly as they were.
		var fill: int = n.allocation_level
		allocation_system.force_deallocate(n)
		if board != null:
			if board.skill_points != null:
				board.skill_points.wound(maxi(fill, 1))
			if board.health != null and hp_per_node > 0.0:
				var dmg: float = hp_per_node * float(maxi(fill, 1))
				# Presentation clock (#487): hold BEFORE the deplete, so the
				# core bar's pre-cascade value is what gets snapshotted, and
				# queue the release against THIS node's own reveal — the same
				# `layer * CASCADE_STEP` slot AllocationVFX reveals its paint
				# on (see `_on_node_death_shown`). Without this the core bar
				# used to drop for every cascaded node all at once, at
				# model-mutation time — chip damage from a node that hasn't
				# even visually died yet.
				defender.hold_health_presentation()
				board.health.deplete(dmg)
				_pending_health_reveals[n] = {"defender": defender, "delta": -dmg}


## BFS the cascade set from [param impact] over graph edges restricted to
## the cascade. Returns Array[Array[SkillNode]] where [i] holds every cascade
## node at distance i from impact ([0] == [impact]). Falls back to a single
## layer when [member graph] is unset (headless tests).
func _cascade_layers(impact: SkillNode, cascade: Array[SkillNode]) -> Array:
	if graph == null:
		var lone: Array[SkillNode] = []
		lone.append_array(cascade)
		return [lone]
	var in_cascade: Dictionary[SkillNode, bool] = {}
	for n in cascade:
		if n != null:
			in_cascade[n] = true
	var visited: Dictionary[SkillNode, bool] = {impact: true}
	var first_layer: Array[SkillNode] = [impact]
	var layers: Array = [first_layer]
	var frontier: Array[SkillNode] = [impact]
	while not frontier.is_empty():
		var next_frontier: Array[SkillNode] = []
		for n in frontier:
			for nb in graph.get_neighbours(n):
				if not in_cascade.has(nb) or visited.has(nb):
					continue
				visited[nb] = true
				next_frontier.append(nb)
		if not next_frontier.is_empty():
			layers.append(next_frontier)
		frontier = next_frontier
	# Defensive: any cascade node BFS missed (shouldnt happen by construction)
	# parks on an outermost layer so it still gets a VFX.
	var orphans: Array[SkillNode] = []
	for n in cascade:
		if n != null and not visited.has(n):
			orphans.append(n)
	if not orphans.is_empty():
		layers.append(orphans)
	return layers


## Every node [param defender] still owns outside [param exclude] (the
## chip-damage cascade set already accounted for). Used by #485's death-strip
## lookahead to fold the rest of a dying entity's territory into the same
## cascade manifest as one trailing layer. Falls back to empty when
## [member graph] is unset (headless tests) — no worse than the pre-#485
## unstaggered strip in that case.
func _remaining_owned_nodes(defender: Entity, exclude: Array[SkillNode]) -> Array[SkillNode]:
	var out: Array[SkillNode] = []
	if graph == null:
		return out
	var excluded: Dictionary[SkillNode, bool] = {}
	for n in exclude:
		if n != null:
			excluded[n] = true
	for n in graph.get_skill_nodes():
		if n.owned_by == defender and not excluded.has(n):
			out.append(n)
	return out
