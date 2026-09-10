class_name MeleeAttackPlan
extends AttackPlan

## A melee attack as an induced sub-subgraph of the attacker's owned territory:
## one PIVOT (left-click, when unset) plus up to `blade_size` MEMBERS
## (left-click toggle, once the pivot is set) that must form a connected
## subgraph through the pivot. Left-clicking a node further out mass-selects
## the shortest owned-territory path leading to it too (one atomic toggle,
## rejected outright if it overruns the budget). Deselecting any member
## cascades the other way — anyone newly disconnected from the pivot drops
## too — keeping the blade well-formed at every step. Right-click pops the
## pivot (and every member with it) back to "no pivot yet" — see
## docs/design/click_grammar.md.

const _BLADE_SIZE_ID: StringName = &"blade_size"

## Swing duration the sim is built around. Real-time playback (live or
## ghost) honours the same value so preview matches commit.
const SWING_DURATION: float = 1.2

## The pivot — right-clicked, owned-by-attacker. Always in the blade mirror.
var source: SkillNode = null

## The selected member nodes (excludes pivot). Each is owned-by-attacker and
## reachable from the pivot through this list + the pivot via graph edges.
var blade_nodes: Array[SkillNode] = []

## AI-ONLY, TRANSIENT (#823). Members [method build_blade_state] should weld
## as if they carried a real [ClampAddon], with NO board mutation — a proposal
## the rollout is scoring, not a real attached addon. Read by
## [method build_blade_state] right after the real addon-dispatch loop, so
## both the coarse-tier probe (which calls `build_blade_state` directly) and
## the finalist tier (`resolve()` -> ... -> `build_blade_state` internally)
## see the same phantom braces — a parameter on `build_blade_state` alone
## would reach only the former. Deliberately absent from [method to_dict]:
## a launched swing carries real addons via [method AIController._execute_candidate]'s
## `toggle_temp_upgrade_on` calls, never a phantom set crossing the wire.
var ai_phantom_clamp_nodes: Array[SkillNode] = []

const CLAMP_UPGRADE: Dictionary = {
	id = &"clamp",
	scene = preload("res://skill_node/addons/clamp_addon.tscn"),
	script = preload("res://skill_node/addons/clamp_addon.gd"),
}
const SPIKE_UPGRADE: Dictionary = {
	id = &"spike_ring",
	scene = preload("res://skill_node/addons/spike_ring_addon.tscn"),
	script = preload("res://skill_node/addons/spike_ring_addon.gd"),
}
## Offerable temp-upgrade kinds (#406) — order is tray/button order. A temp
## upgrade is a REAL SkillNodeAddon, `add_child`ed exactly like a permanent
## one (marked `is_temporary`), spent from the same blade_size budget as
## blade_nodes. A `script` ref rides alongside each `scene` only because
## `SkillNode.can_attach_addon`'s uniqueness check needs the addon's Script
## identity before an instance exists. A future "edge sharpener" is one more
## entry, zero other code changes.
## An `id` rides alongside because a catalog entry has to survive a trip over
## the wire (#509's ToggleTempUpgradeCommand): `scene`/`script` are process-
## local references and the catalog's *position* is not a contract.
const TEMP_UPGRADE_CATALOG: Array[Dictionary] = [CLAMP_UPGRADE, SPIKE_UPGRADE]


## The catalog entry named by `id`, or an empty Dictionary if there is none.
## Returns the CONST entry itself, never a rebuilt copy, so the identity
## checks the catalog is used with (`TEMP_UPGRADE_CATALOG.has(upgrade)` in
## [method can_apply_temp_upgrade]) keep working on the result.
static func upgrade_by_id(id: StringName) -> Dictionary:
	for upgrade in TEMP_UPGRADE_CATALOG:
		if upgrade.id == id:
			return upgrade
	return {}

## Lazy per-scene cost cache — instantiate once off the tree, read the
## authored SkillNodeAddon.temp_upgrade_cost, free, cache. Needed because
## cost lives on the addon instance but budget checks must answer "what
## would this cost" before an instance exists.
static var _cost_cache: Dictionary = {}

static func _cost_for(scene: PackedScene) -> int:
	if not _cost_cache.has(scene):
		var tmp := scene.instantiate()
		_cost_cache[scene] = (tmp as SkillNodeAddon).temp_upgrade_cost
		tmp.free()
	return _cost_cache[scene]

## Arc / sweep target — kept as Vector2 for now per the original sketch;
## targeting integration comes when previews land.
var blade_target: Vector2

## Swing direction. false = CCW (positive sweep, the default); true = CW
## (negative sweep). Toggle persists across plan resets via BattleSystem's
## sticky preference. See docs/design/mvp_decisions.md §D-1.
var swing_cw: bool = false: set = _set_swing_cw

# Plan-driven mirror of `{source} ∪ blade_nodes`. Used to answer
# "what islands off the pivot if I drop this member" via
# nodes_islanded_by_removing(). No graph signal subscriptions —
# this plan calls mirror_add / mirror_remove directly.
var _blade_mirror: GraphMirror = null


func _init() -> void:
	mode = BattleSystem.AttackMode.MELEE


func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE:
		return
	if _blade_mirror != null:
		_blade_mirror.free()
		_blade_mirror = null
	# #821: a sliced prediction holds a CombatWorld shadow open across frames,
	# and that shadow holds the reference cycles `EntityCombat.free_shadow`
	# documents — so dying mid-slice has to release it here.
	#
	# INLINED, not a call to `_cancel_pending_prediction`: by PREDELETE this
	# object can no longer dispatch a method on itself ("call ... on a null
	# instance"), which is also why the mirror teardown above is inline.
	_pending_prediction = null
	if _pending_world != null:
		_pending_world.free_shadow()
		_pending_world = null
	# #796: same trap, same fix, for a mirror's committed-swing replay resolve
	# — it also holds a shadow open across frames. INLINED for the same
	# PREDELETE reason as above; not a call to `advance_replay_resolve`.
	_replay_run = null
	if _replay_world != null:
		_replay_world.free_shadow()
		_replay_world = null


# ── Wire ───────────────────────────────────────────────────────────────────

## Wire form: the base fields plus pivot id, blade member ids, sweep target and
## direction — exactly the inputs [BladeSim] needs to reform a bit-identical
## blade on any peer (`blade_sim.gd:28-31` is a pure fixed-dt XPBD loop with no
## frame delta and no RNG, so re-simulating to DRAW is deterministic and
## mutates nothing).
##
## The `last_*` fields are resolution residue, not plan input, and stay off the
## wire deliberately: a peer that re-runs [method resolve] for its animation
## rebuilds them itself, and a peer that does not has no use for them. The
## temp-upgrade addons attached to blade members are not here either — they are
## real [SkillNodeAddon] children put there by [ToggleTempUpgradeCommand],
## which already crosses on its own.
func to_dict(graph: Graph) -> Dictionary:
	var d := super(graph)
	d["source"] = graph.get_stable_id(source) if graph != null and source != null else 0
	var ids: Array[int] = []
	if graph != null:
		for n in blade_nodes:
			if n != null:
				ids.append(graph.get_stable_id(n))
	d["blade"] = ids
	d["blade_target"] = blade_target
	d["swing_cw"] = swing_cw
	return d


## Rebuilds through the same pivot/member primitives a click would drive
## ([method _set_pivot] / the mirror add in [method _try_select_blade]), so the
## rebuilt plan's `_blade_mirror` is populated and
## [method get_induced_edges] answers correctly — a plan whose members were
## appended straight to [member blade_nodes] would draw a blade with no edges.
## The BUDGET gate is deliberately not re-run: the authority already decided
## this blade is legal, and re-adjudicating it on a peer is exactly what host
## authority exists to avoid.
static func from_dict(d: Dictionary, graph: Graph) -> MeleeAttackPlan:
	var plan := MeleeAttackPlan.new()
	plan._read_base(d, graph)
	plan.swing_cw = bool(d.get("swing_cw", false))
	plan.blade_target = d.get("blade_target", Vector2.ZERO)
	if graph == null:
		return plan
	var pivot := graph.get_by_stable_id(int(d.get("source", 0)))
	if pivot == null:
		return plan
	plan._set_pivot(pivot)
	for id in d.get("blade", [] as Array):
		var member := graph.get_by_stable_id(int(id))
		if member == null:
			continue
		plan._blade_mirror.mirror_add(member)
		plan.blade_nodes.append(member)
	return plan


# ── Input ──────────────────────────────────────────────────────────────────

func pop() -> bool:
	if source == null:
		return false
	reset()
	return true


func _on_node_left_clicked(node: SkillNode) -> void:
	if attacker == null or node == null:
		return
	if source == null:
		if node.owned_by != attacker:
			return
		_set_pivot(node)
		_notify_selection_changed()
		return
	if node == source:
		# Self-targeting fallthrough: the pivot is never a valid blade member,
		# so clicking it again isn't a denial — it's "never mind", same as a
		# right-click. See docs/design/click_grammar.md.
		pop()
		return
	if not _can_be_blade(node):
		return
	var changed := false
	if blade_nodes.has(node):
		_deselect_blade(node)
		changed = true
	elif _try_select_path(node):
		changed = true
	if changed:
		_notify_selection_changed()


# ── Reform (#466) ──────────────────────────────────────────────────────────

## Whether `members` — in THIS order — would rebuild a legal blade on `pivot`
## for `attacker`. A pure simulation of the gates a click sequence passes:
## [method _can_be_blade]'s ownership rule plus [method _try_select_blade]'s
## budget and strict adjacency. Touches neither the world nor any plan.
##
## [b]Purity is the design, not an optimisation.[/b] The tempting alternative —
## run [method try_reform] on a scratch plan and roll it back — cannot be used,
## because the rollback goes through [method _clear_pivot], which frees
## `is_temporary` addons off the REAL SkillNodes it names. A feasibility
## question must never be able to destroy a live plan's temp upgrades.
##
## [b]Deliberately not a topology hash[/b] of the owned subgraph, which is what
## #466 originally sketched. Such a hash has to tolerate an allocation
## SUPERSET — the common case, since staking grows territory without
## invalidating an old blade — and a superset-tolerant hash is ill-defined.
## Replaying the gates answers exactly the question asked, is exact rather than
## a lossy proxy, and costs O(members) over `Graph`'s cached adjacency index.
static func can_reform_selection(attacker: Entity, pivot: SkillNode,
		members: Array[SkillNode]) -> bool:
	if attacker == null or attacker.navigator == null:
		return false
	if pivot == null or not is_instance_valid(pivot):
		return false
	# The attacker's own view of the board, same as _is_neighbor_of_blade_set
	# takes — never a caller-supplied Graph.
	var graph := attacker.navigator.graph
	if graph == null:
		return false
	# Pivot ownership, then validate()'s own floor: a pivot with no members is
	# not a launchable blade, so reforming into one would be no win.
	if pivot.owned_by != attacker or members.is_empty():
		return false
	# Mirrors _budget_remaining() for a FRESH selection: temp-upgrade spend is
	# zero there, because reform always builds on a cleared plan.
	if members.size() > int(pivot.get_local_value(_BLADE_SIZE_ID)):
		return false
	# Grown in the stored order, exactly as the replay grows it — so a member
	# reachable only through one listed AFTER it is refused here too, keeping
	# predicate and replay in lockstep. See try_reform on why no reordering.
	var accepted: Dictionary[SkillNode, bool] = {pivot: true}
	for m in members:
		if m == null or not is_instance_valid(m):
			return false
		if m == pivot or accepted.has(m):
			return false
		if m.owned_by != attacker:
			return false
		var adjacent := false
		for other in graph.get_neighbours(m):
			if accepted.has(other):
				adjacent = true
				break
		if not adjacent:
			return false
		accepted[m] = true
	return true


## Rebuild this plan's selection as `pivot` + `members`, replaying the stored
## order through the STRICT single-member primitive. All-or-nothing: refused
## outright, plan untouched, when [method can_reform_selection] says no.
##
## [b]Never [method _try_select_path].[/b] That is the click path's mass-select,
## and on a member that has drifted out of adjacency it silently pulls in a
## shortest path to reach it — reporting success while producing a DIFFERENT,
## larger blade. #466 asks for the opposite: grey out rather than half-reform.
## The size check below is what keeps that true if this ever gets rewired.
##
## The stored order is authoring order, which was chain-valid when captured, so
## an unchanged (or merely grown) territory always replays. Accepted
## limitation: a blade still constructible in some OTHER order is refused. No
## reordering search — an honest refusal beats a surprising blade.
##
## A half-built selection is replaced, and its temp-upgrade addons are freed
## with it (that is [method _clear_pivot]'s contract, not a new rule here).
func try_reform(pivot: SkillNode, members: Array[SkillNode]) -> bool:
	if not can_reform_selection(attacker, pivot, members):
		return false
	_clear_pivot()
	_set_pivot(pivot)
	for m in members:
		if _try_select_blade(m):
			continue
		# can_reform_selection just cleared this, so a refusal here means the
		# two have drifted apart. Refuse rather than keep a partial blade.
		push_warning("MeleeAttackPlan.try_reform: gate drift on %s, refused" % m)
		_clear_pivot()
		return false
	if blade_nodes.size() != members.size():
		push_warning("MeleeAttackPlan.try_reform: rebuilt blade differs, refused")
		_clear_pivot()
		return false
	_notify_selection_changed()
	return true


# ── Validation + visualization ─────────────────────────────────────────────

func validate() -> Array[String]:
	var errors: Array[String] = []
	if not source:
		errors.append(&'No source node selected')
	if blade_nodes.is_empty():
		errors.append(&'No blade nodes selected')
	return errors


func get_node_role(node: SkillNode) -> HighlightRole:
	if node == null:
		return HighlightRole.NONE
	if source != null and node == source:
		return HighlightRole.ORIGIN
	if blade_nodes.has(node):
		return HighlightRole.MEMBER
	# #782: what the cached prediction says will bite back. A pure dictionary
	# read — never a rebuild; see [member _prediction].
	if _predicted_defenders.has(node):
		return HighlightRole.PREDICTED_THREAT
	if source != null \
			and attacker != null \
			and node.owned_by == attacker \
			and _budget_remaining() > 0 \
			and _is_neighbor_of_blade_set(node):
		return HighlightRole.IN_RANGE
	return HighlightRole.NONE


## Current cap on `blade_nodes.size()` — reads `blade_size` node-locally off
## the pivot (wielder baseline merged with node-local addons, e.g. a
## "greatsword pivot" granting local blade_size). Defaults to 1 when there's
## no pivot yet (e.g. a stat-less test entity).
func max_blades() -> int:
	if source == null:
		return 1
	return int(source.get_local_value(_BLADE_SIZE_ID))


## Budget left for blade-member selection AND temp upgrades — one shared
## pool, so both callers (get_node_role / _try_select_blade / temp-upgrade
## gating) read the same number instead of each recomputing it.
func _budget_remaining() -> int:
	return max_blades() - blade_nodes.size() - temp_upgrade_cost_total()


## Sum of temp_upgrade_cost across every currently-attached is_temporary
## addon on the pivot + selected members. Reads real addon state — no
## separate tracked total to drift out of sync with it.
func temp_upgrade_cost_total() -> int:
	var total := 0
	var nodes: Array[SkillNode] = []
	if source != null:
		nodes.append(source)
	nodes.append_array(blade_nodes)
	for node in nodes:
		for a in node.get_addons():
			if a.is_temporary:
				total += a.temp_upgrade_cost
	return total


## Sum of temp_upgrade_cost across attached is_temporary addons matching
## `upgrade`'s script specifically — the per-kind breakdown
## temp_upgrade_cost_total() sums across every kind. Used by the command-tray
## blips to show budget spend broken out by kind (#406).
func temp_upgrade_cost_for(upgrade: Dictionary) -> int:
	var total := 0
	var nodes: Array[SkillNode] = []
	if source != null:
		nodes.append(source)
	nodes.append_array(blade_nodes)
	for node in nodes:
		for a in node.get_addons():
			if a.is_temporary and a.get_script() == upgrade.script:
				total += a.temp_upgrade_cost
	return total


## True if `node` (a selected member — the pivot is never a valid target, it
## drives the swing and has no meaningful collision area) can receive
## `upgrade`: an open addon slot, no unique-collision, and the combined
## member + upgrade spend stays within max_blades().
func can_apply_temp_upgrade(node: SkillNode, upgrade: Dictionary) -> bool:
	if node == null or node == source or not blade_nodes.has(node):
		return false
	if not TEMP_UPGRADE_CATALOG.has(upgrade):
		return false
	if not node.can_attach_addon(upgrade.script):
		return false
	return _budget_remaining() >= _cost_for(upgrade.scene)


## Whether ANY currently-eligible node could accept `upgrade` right now —
## cheap plan-level affordability check for UI button enablement, independent
## of which specific node gets clicked.
func has_temp_upgrade_budget(upgrade: Dictionary) -> bool:
	return source != null and _budget_remaining() >= _cost_for(upgrade.scene)


## Spend budget and attach a real `upgrade` addon to `node`. Returns false
## (no-op) if can_apply_temp_upgrade() rejects it.
func apply_temp_upgrade(node: SkillNode, upgrade: Dictionary) -> bool:
	if not can_apply_temp_upgrade(node, upgrade):
		return false
	var addon := (upgrade.scene as PackedScene).instantiate() as SkillNodeAddon
	addon.is_temporary = true
	node.add_child(addon)
	_notify_selection_changed()
	return true


## Refund `node`'s temp upgrade, if any — frees the attached addon.
func remove_temp_upgrade(node: SkillNode) -> void:
	if _free_temp_addons(node):
		_notify_selection_changed()


## `node`'s currently-attached is_temporary addon matching `upgrade`'s
## script, or null.
func _existing_temp_upgrade(node: SkillNode, upgrade: Dictionary) -> SkillNodeAddon:
	if node == null:
		return null
	for a in node.get_addons():
		if a.is_temporary and a.get_script() == upgrade.script:
			return a
	return null


## Would [method toggle_temp_upgrade] change anything? Composed from the two
## halves that method already branches on, never a third copy of either — a
## refund is always legal, so the only question a fresh apply has to answer is
## `can_apply_temp_upgrade`. Lifted out so [method CommandApplier._validate] can
## gate a [ToggleTempUpgradeCommand] before it is confirmed (#540).
func can_toggle_temp_upgrade(node: SkillNode, upgrade: Dictionary) -> bool:
	if node == null or upgrade.is_empty():
		return false
	if _existing_temp_upgrade(node, upgrade) != null:
		return true
	return can_apply_temp_upgrade(node, upgrade)


## Click-to-toggle entry point for the UI (#406): if `node` already carries
## this exact temp upgrade, refund it (same shape as a blade-member toggle);
## otherwise try to apply a new one. Returns true if anything changed.
func toggle_temp_upgrade(node: SkillNode, upgrade: Dictionary) -> bool:
	if _existing_temp_upgrade(node, upgrade) != null:
		remove_temp_upgrade(node)
		return true
	return apply_temp_upgrade(node, upgrade)


## Frees every is_temporary addon on `node`. The one place temp-upgrade
## removal is written — every mutation site below calls this instead of
## duplicating the free loop. Returns true if anything was freed.
func _free_temp_addons(node: SkillNode) -> bool:
	var freed := false
	for a in node.get_addons():
		if a.is_temporary:
			node.remove_child(a)
			a.queue_free()
			freed = true
	return freed


# ── State mutations (all assume legitimacy already gated) ──────────────────

func _set_pivot(node: SkillNode) -> void:
	_clear_pivot()
	source = node
	_ensure_mirror()
	_blade_mirror.mirror_add(node)


func _clear_pivot() -> void:
	_ensure_mirror()
	# Mutate all plan state first, free addons last: remove_child fires
	# _detach_addon synchronously (modifier removal touches stat-board
	# signals), so a handler reacting to that mid-call must never see a
	# half-updated plan.
	var to_free: Array[SkillNode] = blade_nodes.duplicate()
	for b in blade_nodes:
		_blade_mirror.mirror_remove(b)
	blade_nodes.clear()
	if source != null:
		to_free.append(source)
		_blade_mirror.mirror_remove(source)
	source = null
	for n in to_free:
		_free_temp_addons(n)


func _try_select_blade(node: SkillNode) -> bool:
	if _budget_remaining() <= 0:
		return false
	if not _is_neighbor_of_blade_set(node):
		return false
	_ensure_mirror()
	_blade_mirror.mirror_add(node)
	blade_nodes.append(node)
	return true


## Mass-select: `node` doesn't have to be adjacent to the current blade set —
## if it's further out, select the shortest owned-territory path leading to
## it too, as one atomic toggle. Gated by the same budget as a single member;
## a path that doesn't fit is rejected outright (no partial selection).
func _try_select_path(node: SkillNode) -> bool:
	if _is_neighbor_of_blade_set(node):
		return _try_select_blade(node)
	if attacker == null or attacker.navigator == null:
		return false
	var blade_set: Array[SkillNode] = [source]
	blade_set.append_array(blade_nodes)
	# node -> ... -> nearest blade-set member, inclusive of both ends.
	var path := attacker.navigator.shortest_path_to_any(node, blade_set)
	if path.is_empty():
		return false
	# The last element is already selected; everyone else is the excursion.
	var to_add := path.slice(0, path.size() - 1)
	if to_add.size() > _budget_remaining():
		return false
	# Add from the blade-set end outward so every step lands adjacent to an
	# already-selected node, same legality _try_select_blade enforces.
	to_add.reverse()
	for n in to_add:
		_try_select_blade(n)
	return true


func reset() -> void:
	if source == null and blade_nodes.is_empty():
		return
	_clear_pivot()
	_notify_selection_changed()


func _deselect_blade(node: SkillNode) -> void:
	_ensure_mirror()
	# Snapshot the cascade BEFORE we touch the mirror — the islanded set
	# is everything reachable from the about-to-be-dropped node but no
	# longer from the pivot. Removing `node` from the mirror first would
	# leave its component dangling and the query would over-report.
	var islanded := _blade_mirror.nodes_islanded_by_removing(node, source)
	_blade_mirror.mirror_remove(node)
	blade_nodes.erase(node)
	for n in islanded:
		_blade_mirror.mirror_remove(n)
		blade_nodes.erase(n)
	_free_temp_addons(node)
	for n in islanded:
		_free_temp_addons(n)


# ── Internals ──────────────────────────────────────────────────────────────

func _ensure_mirror() -> void:
	if _blade_mirror != null:
		return
	_blade_mirror = GraphMirror.new()
	if attacker != null and attacker.navigator != null:
		_blade_mirror.graph = attacker.navigator.graph


func _can_be_blade(node: SkillNode) -> bool:
	if attacker == null or node == null:
		return false
	if node.owned_by != attacker:
		return false
	if source == null or node == source:
		return false
	return true


## Scan artifacts from the most recent [method resolve] call — the exact
## trajectory / hit events that produced [member last_events]'s owning
## [AttackOutcome]. [MeleePreview] replays THESE (never a fresh rescan) so the
## live swing's animation can't drift from the damage BattleSystem already
## applied synchronously off [method resolve]'s outcome (#474): a rescan taken
## after the depletion cascade would rebuild [method collect_target_excludes]
## against the post-cascade world and re-derive damage from a fresh blade
## state, drifting from what [OutcomeApplier] actually landed — a bug about
## replaying a finished mutation, not a reason to freeze the LANDING gate
## itself. #502 moves that gate to consumption time deliberately; see
## [BladePopResolver.LiveGate] and docs/domain/attack-timeline.md.
var last_trajectory: BladeTrajectory = null
var last_events: Array[BladeHitEvent] = []
## What the swing's pop gate settled — [member last_live_gate]'s own `result`,
## under the name its readers ([MeleePreview], which draws the dead vertices)
## have always used. Complete by the time [method resolve_against] returns,
## because that method lands the outcome before it returns; there is no longer a
## separate pre-swing estimate for this to disagree with (#536).
var last_pops: BladePopResolver.Result = null
## The gate driving the swing — [method BladeDamageInstance.land_on] calls
## [method BladePopResolver.LiveGate.admit] on this exact instance, once per
## hit, in true land order, as [OutcomeApplier] applies [member last_hits]. Its
## `result` accumulates what ACTUALLY happened: the applier's accepted set,
## never a rescan. Null until [method resolve_against] runs, and complete once
## it has.
##
## [b]It is complete on return, but the pop CUE still does not come from
## here.[/b] Under #536 this gate runs against the shadow world the authority
## computes on, so nothing it does may announce itself (#504's requirement that
## the cue ride the mutation clock is what that would break). The pop is
## recorded onto the hit and emitted by [method OutcomeApplier.land_one] on the
## live replay — see [member HitInstance.popped_vertex]. Do not reintroduce an
## announcement here or in [MeleePreview]'s animation replay; racing two timers
## at the same `t` is the disease, not the fix.
var last_live_gate: BladePopResolver.LiveGate = null
## The [DamageInstance]s (concretely [BladeDamageInstance]) [method resolve]
## built from [member last_events] — one per VERTEX event, in order, whether or
## not it will actually land (that decision is [member last_live_gate]'s, made
## at [method BladeDamageInstance.land_on] time).
##
## [b]An EDGE event has no entry here[/b], so this is a subsequence of
## [member last_events] rather than a parallel array. ADR 0005: nodes deal
## damage, edges give rigidity. An edge contact is real — it is what stops a
## bunker entering the blade's interior — but it carries no damage, and minting
## a zero-amount [DamageInstance] for it would still buy a crit roll, a
## schedule entry, a landing beat and a line in the [AttackRecord]. That is a
## change to the COUNTING RULE with no gameplay content behind it, which is the
## thing `docs/design/combat_system.md` says to leave alone. Edge contacts live
## on in [member last_events] for the visual playback and for #781's bunker
## break. The reveal can show [member HitInstance.effective_amount] (set by
## [method SkillNode.take_damage] when the real applier landed it) instead of
## re-deriving damage from a freshly rebuilt blade state, which drifts from
## what actually landed. Melee only ever produces [DamageInstance]s (never
## heals), so this stays narrowly typed rather than the [AttackOutcome]-wide
## [code]Array[HitInstance][/code] (#381).
var last_hits: Array[DamageInstance] = []


## Everything one swing resolution produced, in one bundle (#782).
##
## [b]Why this exists.[/b] [method resolve_against] used to publish its
## artifacts straight onto the [code]last_*[/code] fields, which made "resolve a
## swing" and "declare that swing the committed one" the same act. The preview
## needs the first without the second: it resolves the CURRENT selection against
## a throwaway shadow purely to draw it, and must not touch the artifacts
## [MeleePreview.launch] replays for the swing the authority actually landed.
## So [method _resolve_swing] is the single implementation, and the two callers
## differ only in where they put the result — see the repo rule against parallel
## mirrors of the same logic.
class SwingResult extends RefCounted:
	var outcome: AttackOutcome = null
	var trajectory: BladeTrajectory = null
	var events: Array[BladeHitEvent] = []
	var pops: BladePopResolver.Result = null
	var live_gate: BladePopResolver.LiveGate = null
	var hits: Array[DamageInstance] = []
	## The swing's own drag clock and defender field, at their END state. Both
	## null exactly when [method MeleeAttackPlan.build_defender_zones] came back
	## empty — the ordinary swing, which allocates neither. Since #811 they
	## travel together: one field, one clock, or neither.
	var clock: BladeSwingClock = null
	var obstacles: BladeObstacleField = null



## One resumable run of the swing resolve — the loop [method
## MeleeAttackPlan._resolve_swing] used to hold inline, hoisted into an object
## so it can be driven either straight through (the authoritative path: one
## optimistic bake of the whole remaining swing per severance) or a slice at a
## time across frames (#821's aim-time preview).
##
## [b]There is still exactly ONE chunked loop.[/b] Slicing is not a second code
## path — [method advance] takes a step budget, and an unbounded budget (<= 0)
## reproduces the old whole-remainder bake exactly. Everything the severance
## head-replay already did to stitch a chunk boundary is what a slice boundary
## rides on: one [BladeSwingClock] instance carried across, one
## [BladeObstacleField] carried across, and [member BladeState.speed_history]
## accumulated out of each bake's chunk-local array.
##
## [b]Those three histories are chunk-local BY DESIGN[/b] — `clock.history`,
## `obstacles.history` and `state.speed_history` are rebuilt per bake, so a
## sliced caller has to stitch them rather than assume they accumulate. Getting
## it wrong is not a visible glitch: a fresh clock mid-swing un-banks a
## Fortification wall's drag and silently stops it sheltering what is behind it
## (`test_blade_chunked_parity.gd:200-203`). That an arbitrary boundary is
## bit-identical to no boundary at all is pinned by
## `test_a_dragged_swing_is_bit_identical_across_a_chunk_boundary`.
##
## A slice boundary differs from a severance boundary in exactly one way: there
## is nothing to rewind to. The bake ran to the boundary and stopped, so the
## state, the clock and the field are already where the next bake continues
## from — nothing is restored, which is the shape that parity test runs.
class SwingResolve extends RefCounted:
	## The bundle, LIVE. `outcome`, `pops`, `live_gate`, `clock` and `obstacles`
	## are set before the first step; `trajectory`, `events` and `hits` the
	## moment the guards pass — and they are the very arrays the run appends to,
	## so a PARTIAL run is readable and grows in place. See
	## [method MeleeAttackPlan.prediction_partial].
	var result: SwingResult = SwingResult.new()

	var _plan: MeleeAttackPlan = null
	var _world: CombatWorld = null
	var _outcome: AttackOutcome = null
	var _state: BladeState = null
	var _drivers: Array[BladeDriver] = []
	var _clock: BladeSwingClock = null
	var _obstacles: BladeObstacleField = null
	var _gate: BladePopResolver.LiveGate = null
	var _sweep: BladeHitScan.Sweep = null
	var _trajectory: BladeTrajectory = null
	var _speed_history: Array[PackedFloat32Array] = []
	var _events: Array[BladeHitEvent] = []
	var _hits: Array[DamageInstance] = []
	var _rng: RandomNumberGenerator = null
	var _dt: float = BladeSim.DEFAULT_DT
	var _total_steps: int = 0
	## The GLOBAL sample index the next bake starts from. Moves to a severance
	## sample (rewound) or to the end of the last bake (a slice boundary).
	var _chunk_start: int = 0
	var _done: bool = false
	## #796: the peer draw-only resim's fidelity knob. Both default to the
	## authoritative/aim-time values (`BladeSim.DEFAULT_SUBSTEPS`, scaling on) —
	## only [method MeleeAttackPlan.begin_replay_resolve] ever passes anything
	## else, and it does so because ADR 0002 makes that call's whole run
	## draw-only: no hit, pop or damage number this class produces is kept, so
	## degrading its solve buys nothing to lose.
	var _substeps: int = BladeSim.DEFAULT_SUBSTEPS
	var _enable_length_scaling: bool = true


	func _init(plan: MeleeAttackPlan, world: CombatWorld,
			substeps: int = BladeSim.DEFAULT_SUBSTEPS,
			enable_length_scaling: bool = true) -> void:
		_plan = plan
		_world = world
		_substeps = substeps
		_enable_length_scaling = enable_length_scaling
		var resolve_seed := plan.resolve_seed
		var outcome := AttackOutcome.new()
		_outcome = outcome
		result.outcome = outcome
		outcome.cadence = ScheduleEntry.Cadence.SWING
		# Spelled through a local rather than `plan.resolve_seed` because
		# `test_attack_determinism.gd` pins this line, and the next crit-stream
		# one, as SOURCE TEXT — a refactor that quietly stopped drawing off the
		# stamped seed is exactly what that guard exists to catch.
		outcome.resolve_seed = resolve_seed
		if not plan.is_valid():
			_done = true
			return
		_state = plan.build_blade_state()
		if _state == null:
			_done = true
			return
		_drivers = plan.build_drivers(_state)
		# The defender field (#811) carries both kinds; the clock is its
		# accumulator half. Fortification drag (#780) bogs the swing's own clock
		# down cumulatively from the moment the blade first touches a wall, and a
		# bunker's grip stall (#781) is expressed on the same clock — so a swing
		# with any defender in reach gets one, and a swing with none gets neither.
		# ONE clock for the whole swing, carried across every chunk — see
		# BladeSwingClock.Bank. An untouched clock is bit-inert
		# (test_blade_swing_drag pins it) and the field already forces the GDScript
		# backend, so a plates-only swing pays nothing extra for having one.
		_obstacles = _state.obstacles
		if _obstacles != null:
			_clock = BladeSwingClock.new(MeleeAttackPlan.SWING_DURATION)
		var space_state := plan.source.get_world_2d().direct_space_state
		var exclude := plan.collect_target_excludes()
		var graph: Graph = plan.attacker.navigator.graph \
				if plan.attacker != null and plan.attacker.navigator != null else null
		# #170/#502/#536: ONE pop gate for the whole swing, re-evaluated per event at
		# land time, so it sees this swing's own cascades. Since #801 it also sees
		# them EARLY ENOUGH TO MATTER: a death lands before the samples after it are
		# simulated, so the solver can react to it.
		_gate = BladePopResolver.LiveGate.new(_state, plan.attacker)
		result.live_gate = _gate
		result.pops = _gate.result
		result.clock = _clock
		result.obstacles = _obstacles
		# #530: each batch stable-sorts on SkillNode.stable_id, so the hit SET a pop
		# cascade sees never depends on physics broadphase order.
		if space_state != null:
			_sweep = BladeHitScan.Sweep.new(_state, space_state, graph, 0xFFFFFFFF, exclude)

		_total_steps = int(ceil(MeleeAttackPlan.SWING_DURATION / _dt))
		_trajectory = BladeTrajectory.new()
		_trajectory.sample_dt = _dt
		_trajectory.samples = [_state.positions.duplicate()]
		var zero_speeds := PackedFloat32Array()
		zero_speeds.resize(_state.positions.size())
		_speed_history = [zero_speeds]
		# ONE crit stream for the whole swing, handed to every batch's `decide_all`
		# in turn (#507). Batches run in `t` order and `OutcomeSchedule._sorted` is
		# stable on insertion, so the stream is consumed in exactly the order a
		# single `decide_all` over the finished hit list would have consumed it —
		# which is why an unsevered swing rolls the identical crits it did before
		# the interleave. #186's per-round salt is gone with the rounds.
		_rng = CritRoll.stream_for(resolve_seed)
		# Published now, not at the end: these three ARE the partial picture.
		result.trajectory = _trajectory
		result.events = _events
		result.hits = _hits


	func is_done() -> bool:
		return _done


	## How far the trajectory has been resolved, 0..1. For a surface that wants
	## to say "still computing" — nothing does yet (#821 raised it as a design
	## question rather than inventing an answer).
	func progress() -> float:
		if _total_steps <= 0:
			return 1.0
		return clampf(float(_chunk_start) / float(_total_steps), 0.0, 1.0)


	## The trajectory-TIME length this run will finish at, known from the swing
	## duration up front — unlike [method BladeTrajectory.duration], which
	## derives purely from `samples.size()` and so underreports while a slice
	## run is still mid-flight. #796: a mirror's [method MeleePreview.launch]
	## needs the real span to size its playback tween BEFORE the resim driving
	## it has finished.
	func total_duration() -> float:
		return float(_total_steps) * _dt


	## Resolve at most [param max_steps] more trajectory samples; true when the
	## whole swing is resolved. A budget of 0 or less means "the rest of it",
	## which is the authoritative path's single call.
	func advance(max_steps: int) -> bool:
		if _done:
			return true
		var budget := max_steps
		while _chunk_start < _total_steps:
			var remaining := _total_steps - _chunk_start
			# OPTIMISTIC BAKE: the whole remaining swing in one call, assuming
			# nothing dies. Because a bake is a pure function of the state, walking
			# it sample by sample and re-baking from the first death produces the
			# bit-identical trajectory a true per-sample interleave would (#801) —
			# at one solver call per SEVERANCE instead of one per sample. A budget
			# caps the same call short; the boundary it creates is stitched exactly
			# like a severance boundary, minus the rewind.
			var count := remaining if budget <= 0 else mini(budget, remaining)
			var chunk := BladeSim.simulate_range(
					_state, _drivers, _chunk_start, count, _dt,
					BladeSim.DEFAULT_ITERATIONS, 0.0, _substeps,
					_enable_length_scaling, _clock)
			var chunk_speeds := _state.speed_history
			var severed_at := -1
			for j in range(1, chunk.samples.size()):
				var step := _chunk_start + j
				var pose: PackedVector2Array = chunk.samples[j]
				var speeds: PackedFloat32Array = chunk_speeds[j]
				_trajectory.samples.append(pose)
				_speed_history.append(speeds)
				var pops_before := _gate.result.pops.size()
				if _sweep != null:
					var batch := _sweep.scan_sample(float(step) * _dt, pose, speeds)
					if not batch.is_empty():
						_events.append_array(batch)
						_plan._land_batch(_outcome, batch, _state, _gate, _world, _rng, _hits)
				# A bunker break (#781) is decided INSIDE the bake, by the field, at
				# the substep the strain crossed the threshold — so it is checked
				# per sample whether or not anything was hit, and severs exactly
				# like a pop: stop, rewind, apply, re-bake.
				var broke := _obstacles != null and _obstacles.has_break_at(step)
				if _gate.result.pops.size() != pops_before or broke:
					severed_at = step
					break
			if severed_at < 0:
				# A PLAIN BOUNDARY. The bake ran to `_chunk_start + count` and the
				# state, the clock and the field are all standing there — nothing to
				# rewind, nothing to restore. When `count` was the whole remainder
				# this ends the loop, which is the pre-#821 shape verbatim.
				_chunk_start += count
			else:
				# REWIND TO THE DEATH. The bake above ran past it, so `state` is at the
				# end of the swing, not at `severed_at`. The bake recorded the exact
				# state at every sample — `prev_samples` alongside `samples`, and the
				# clock its own bank (#803) — so landing on the severance sample is a
				# read, not a re-run. (`_step` rewrites `prev_positions` once per
				# SUBSTEP, so it is a mid-sample pose that `samples` alone could never
				# recover; #801 re-baked the head of the chunk to get it before both
				# backends emitted it.) Duplicated because `_step` writes through the
				# reference, and the trajectory keeps these same arrays.
				#
				# The three histories are indexed CHUNK-LOCAL, so the index is
				# relative to this bake's own start — never the global step.
				var local := severed_at - _chunk_start
				_state.positions = chunk.samples[local].duplicate()
				_state.prev_positions = chunk.prev_samples[local].duplicate()
				if _clock != null:
					_clock.restore(_clock.history[local])
				if _obstacles != null:
					_obstacles.restore(_obstacles.history[local])
				# THE WHOLE OF A SEVERANCE: a corpse frozen where it died, its
				# constraints and its driver gone, and drag written onto whatever it was
				# holding on. Nothing else — everything downstream then coasts by plain
				# Verlet, because that is what Verlet does to a particle nothing is
				# pulling on.
				# The bank restored just above IS the one the break was armed in — the
				# field banks once per sample, after that sample's substeps — so the
				# break is consumed HERE, off the rewound field, with nothing re-run.
				if _obstacles != null:
					var brk := _obstacles.consume_break()
					if brk != null:
						_gate._sever_edge(brk.edge_idx, float(severed_at) * _dt, brk.defender, 0.0)
				for pop in _gate.result.pops:
					if pop.particle_idx >= 0:
						_state.remove_vertex(pop.particle_idx)
				for severance in _gate.result.severances:
					for v in severance.vertices:
						_state.set_damping(v, BladeState.SEVERED_DRAG)
				_drivers = MeleeAttackPlan._surviving_drivers(_drivers, _state, _gate)
				_chunk_start = severed_at
			if budget > 0:
				budget -= count
				if budget <= 0:
					break
		if _chunk_start < _total_steps:
			return false
		_finish()
		return true


	func _finish() -> void:
		_done = true
		_state.speed_history = _speed_history
		# One coherent timeline over every batch. The record carries each hit's
		# structural key and every peer compiles its own seconds from it.
		_outcome.schedule = OutcomeSchedule.compile(_outcome)
		# The AI's shape-risk signal: how many of the attacker's own vertices this
		# swing actually DESTROYED. Pops only (#799) — a vertex that merely lost its
		# path to the handle coasts on in this same trajectory and is not a loss.
		_outcome.popped_nodes += _gate.result.vertex_pop_count()

## The prediction [MeleePreview] draws and [method get_node_role] marks off:
## this exact selection, resolved once against a shadow world, cached until the
## selection changes (#782). Null when nothing has asked for one yet, when the
## plan is invalid, or from the moment the selection moves until the next
## [method refresh_prediction].
##
## [b]Nothing here rebuilds it lazily on read.[/b] A melee resolve is a ~70
## sample physics scan plus a shadow snapshot — an order of magnitude past
## [MagicAttackPlan]'s graph walk, which CAN afford to rebuild inside
## [method get_node_role]. Doing that here would fire a full resolve per overlay
## repaint, and worse: a committed swing's forced-dealloc cascade emits
## [signal HighlightProvider.state_changed] per step, so a repaint-driven
## rebuild would resolve the half-dead plan once per cascade step, mid-swing.
## The refresh is therefore PUSHED, by the one surface that wants it —
## [method MeleePreview._refresh], which already gates on `_live_swing` and
## `is_valid()`. A machine with no preview mounted pays nothing.
var _prediction: SwingResult = null
## How many times [method refresh_prediction] has actually run a resolve, for
## the whole life of this plan. The acceptance-5 counter (#782): N preview
## cycles on an unchanged selection must leave this at 1.
var prediction_runs: int = 0
## The slice run in flight, or null. Non-null exactly between the first
## [method advance_prediction] of a selection and the one that completes it or
## the [method _invalidate_prediction] that cancels it (#821).
var _pending_prediction: SwingResolve = null
## The shadow world [member _pending_prediction] is resolving against, held
## open across frames and freed on completion or cancellation. Never the live
## world — a prediction mutates nothing real.
var _pending_world: CombatWorld = null
## Defenders the cached prediction says will pop a vertex or shatter an edge,
## as a set — read by [method get_node_role] with no work of its own.
var _predicted_defenders: Dictionary[SkillNode, bool] = {}

## #796: a MIRROR's committed-swing draw-only resim, in flight, or null. Not
## the aim-time [member _pending_prediction] — that one runs before a commit
## and is cancellable; this one runs AFTER a commit, for a swing that is
## already decided ([AttackRecord] already applied elsewhere per ADR 0002), so
## it always runs to completion rather than being invalidated mid-flight.
var _replay_run: SwingResolve = null
## The shadow world [member _replay_run] resolves against, held open across
## frames and freed on completion — never the live world, same contract as
## [member _pending_world].
var _replay_world: CombatWorld = null


## The cached prediction for the current selection, or null if there is none.
## A pure read — see [member _prediction] for why this never rebuilds.
func prediction() -> SwingResult:
	return _prediction


## Resolve the current selection against a throwaway shadow and cache it.
##
## Idempotent per selection: a second call with the cache still warm is a no-op,
## which is what keeps [member prediction_runs] at 1 across a preview loop that
## rebuilds its ghost forever. [method _invalidate_prediction] is what makes the
## next call do work again.
##
## The shadow is freed on every path — it holds the reference cycles
## [method EntityCombat.free_shadow] documents. What survives it is safe to
## keep: a [BladePopResolver.Pop] names its defender by [SkillNode] (identity,
## not state), and the trajectory is plain geometry.
##
## [b]The seed is deliberately NOT stamped.[/b] A preview runs on the unstamped
## (0) crit stream; the committed swing stamps a fresh one. Pops and shatters do
## not read damage — a pop is spike pool vs. blunting, a shatter is strain — so
## the two agree in every ordinary case. They can part only where a crit-driven
## kill cascades and changes a later defender's board mid-swing. That is one
## more entry on the list of accepted mispredicts, not a reason to show the
## player a roll that has not happened yet.
func refresh_prediction() -> void:
	# ONE implementation, driven to the end: an unbounded budget makes
	# [method advance_prediction] bake the whole remaining swing in one call,
	# which is exactly what this method used to do inline.
	while not advance_prediction(0):
		pass


## Resolve at most [param max_steps] more trajectory samples of the current
## selection's prediction, and report whether a COMPLETE one is now cached.
## A budget of 0 or less means "the whole remaining swing", which is
## [method refresh_prediction].
##
## [b]#821: this is the aim-time path.[/b] A melee resolve is a ~72 sample
## physics scan and it used to run whole, synchronously, on every node click
## while aiming — a multi-frame stall on the one input the player is watching
## for an answer to. It is draw-only and nothing replays it, so it carries none
## of the determinism obligations the authoritative resolve does and can simply
## be stepped: [MeleePreview] pumps a frame's worth per frame and draws the
## partial arc it has, which is the picture the player wants ("roughly where
## does this go") sooner than a finished one would arrive.
##
## Threading it was the rejected alternative — [WorkerThreadPool] is #796's
## answer for the AUTHORITATIVE resolve, which has #559's wind-up to hide
## behind. Here there is no wind-up, and a partial picture beats a whole one
## that arrives later.
##
## The in-flight run holds the shadow world open across frames; every input to
## the resolve routes through [method _invalidate_prediction], which cancels it
## and frees that shadow, so a superseded slice can never finish or overwrite a
## fresher prediction.
func advance_prediction(max_steps: int) -> bool:
	if _prediction != null:
		return true
	if not is_valid():
		_cancel_pending_prediction()
		return false
	if _pending_prediction == null:
		_pending_world = CombatWorld.shadow()
		_pending_prediction = SwingResolve.new(self, _pending_world)
		# Counted per RUN, not per slice: one logical prediction per selection is
		# what this number has always meant (#782 acceptance 5, #821 acceptance 4).
		prediction_runs += 1
	if not _pending_prediction.advance(max_steps):
		return false
	_prediction = _pending_prediction.result
	_cancel_pending_prediction()
	for pop in _prediction.pops.pops:
		if pop.defender != null:
			_predicted_defenders[pop.defender] = true
	return true


## The prediction to DRAW: the completed one when there is one, otherwise the
## partial an in-flight slice run has produced so far. Its trajectory, events
## and hits are the live arrays the run is still appending to — read them, never
## hold them past an invalidation.
##
## [method prediction] stays the strict accessor (complete or nothing); this is
## the one surface that wants a half-drawn arc.
func prediction_partial() -> SwingResult:
	if _prediction != null:
		return _prediction
	return _pending_prediction.result if _pending_prediction != null else null


## True while a sliced resolve is part-way through. For a caller deciding
## whether to keep pumping.
func is_predicting() -> bool:
	return _pending_prediction != null


## Drop the cached prediction, and CANCEL any slice run in flight. Called from
## every site that emits [signal HighlightProvider.state_changed] — the
## selection, the swing direction and the temp-upgrade set are all inputs to the
## resolve.
func _invalidate_prediction() -> void:
	_prediction = null
	_predicted_defenders.clear()
	_cancel_pending_prediction()


## Release the in-flight run and its shadow world. The run is simply dropped:
## it holds no handle on anything real (its landings went into the shadow), so
## letting it go IS the cancellation — nothing left alive can write a stale
## result over a fresher one.
func _cancel_pending_prediction() -> void:
	_pending_prediction = null
	if _pending_world != null:
		_pending_world.free_shadow()
		_pending_world = null


## Drop the prediction and tell the surfaces. Every site in this plan that used
## to emit [signal HighlightProvider.state_changed] goes through here instead:
## the selection, the swing direction and the temp-upgrade set are all inputs to
## the resolve, so "the state changed" and "the prediction is stale" are the same
## event and must never be able to drift apart.
func _notify_selection_changed() -> void:
	_invalidate_prediction()
	state_changed.emit()


## #796: start a MIRROR's committed-swing draw-only resim, stepped across
## frames rather than baked whole before [method MeleePreview.launch] can even
## begin. Per ADR 0002 every hit, pop and damage number this swing will show
## already comes off the confirmed [AttackRecord], replayed on the real world
## by [method BattleSystem.apply_launch_command] — this run exists only to
## draw a plausible arc, so [param substeps] / [param enable_length_scaling]
## are a pure graphics knob with zero correctness consequence.
##
## Idempotent: a second call while one is already in flight is a no-op, so a
## caller need not track whether it already started one.
##
## Publishes [member last_trajectory] / [member last_events] / [member
## last_pops] / [member last_live_gate] to the run's LIVE arrays immediately,
## the same "published now, not at the end" shape [SwingResolve] already uses
## for the aim-time preview — a reader that looks at them before the run
## finishes sees the partial picture and nothing stale.
func begin_replay_resolve(substeps: int, enable_length_scaling: bool) -> void:
	if _replay_run != null:
		return
	_replay_world = CombatWorld.shadow()
	_replay_run = SwingResolve.new(self, _replay_world, substeps, enable_length_scaling)
	last_trajectory = _replay_run.result.trajectory
	last_events = _replay_run.result.events
	last_hits = _replay_run.result.hits
	last_pops = _replay_run.result.pops
	last_live_gate = _replay_run.result.live_gate


## Step the in-flight replay resolve by at most [param max_steps] samples.
## True once it is fully resolved — including when nothing was in flight, so a
## caller can call this unconditionally every frame. Frees the shadow world on
## the completing call, same as [method _cancel_pending_prediction].
func advance_replay_resolve(max_steps: int) -> bool:
	if _replay_run == null:
		return true
	if not _replay_run.advance(max_steps):
		return false
	_replay_run = null
	if _replay_world != null:
		_replay_world.free_shadow()
		_replay_world = null
	return true


## True while a mirror's committed-swing resim is still stepping. For
## [MeleePreview]'s frame pump to know whether there is work to do.
func is_replaying() -> bool:
	return _replay_run != null


## The trajectory-time length the in-flight replay resolve will finish at, or
## the already-finished trajectory's own duration once there is no run left.
## For [method MeleePreview.launch] to size its playback tween correctly
## whether or not the resim driving it is done — see [method
## SwingResolve.total_duration] for why [method BladeTrajectory.duration]
## cannot answer this mid-flight.
func replay_duration() -> float:
	if _replay_run != null:
		return _replay_run.total_duration()
	return last_trajectory.duration() if last_trajectory != null else 0.0


func resolve_against(world: CombatWorld) -> AttackOutcome:
	var swing := _resolve_swing(world)
	# Publishing is all that separates the committed resolve from the preview
	# one. An invalid plan leaves the previous swing's artifacts in place
	# rather than nulling them — behaviour this refactor preserves, because
	# `_resolve_swing` returns early with a null trajectory and the guard below
	# is what used to be the early `return outcome`.
	if swing.trajectory != null:
		last_trajectory = swing.trajectory
		last_events = swing.events
		last_hits = swing.hits
	if swing.live_gate != null:
		last_live_gate = swing.live_gate
		last_pops = swing.pops
	return swing.outcome


## The one implementation of "swing this blade and land what it hits". See
## [SwingResult] for why the artifacts come back in a bundle instead of being
## written onto this plan.
func _resolve_swing(world: CombatWorld) -> SwingResult:
	var run := SwingResolve.new(self, world)
	# Unbounded: one optimistic bake per severance, exactly the loop this method
	# ran inline before #821 hoisted it into [SwingResolve]. The slice budget is
	# the ONLY thing the preview varies — see that class for why there is not a
	# second chunked path.
	while not run.advance(0):
		pass
	return run.result


## Mint, crit and LAND one sample's contacts, appending what landed to
## [param outcome] and [param hits].
##
## [b]The interleave is sim / scan / LAND, not sim / scan / gate.[/b] The pop
## gate is reached from [method BladeDamageInstance.land_on] inside
## [method OutcomeApplier.apply]'s walk — only APPLYING produces the world the
## next pop decision has to read. This is the per-batch idiom #186's free-flight
## round already used (sub-outcome → compile → same crit rng → apply → merge),
## in a loop; no suspendable applier is needed.
func _land_batch(
		outcome: AttackOutcome,
		batch: Array[BladeHitEvent],
		state: BladeState,
		gate: BladePopResolver.LiveGate,
		world: CombatWorld,
		rng: RandomNumberGenerator,
		hits: Array[DamageInstance]) -> void:
	var sub := AttackOutcome.new()
	sub.cadence = ScheduleEntry.Cadence.SWING
	sub.resolve_seed = resolve_seed
	for ev in batch:
		# An EDGE contact produces no DamageInstance at all (ADR 0005): edges
		# give rigidity, nodes deal damage. It stays in `last_events` — it is a
		# real contact, and #781's bunker break is its consumer — but it buys no
		# crit roll, no schedule entry and no AttackRecord line, because there
		# is no damage for any of those to be about.
		if ev.is_edge_hit():
			continue
		# #502: no pre-filtering by pops/allocation here — every VERTEX event
		# becomes a candidate DamageInstance. Whether it actually lands is
		# BladeDamageInstance.land_on's call, live, when OutcomeApplier
		# consumes it (docs/domain/attack-timeline.md). There is no
		# disconnection scale (#186 acceptance 3): a coasting vertex carries the
		# SAME coefficient a driven one would, and #779's speed curve — applied
		# off `ev.speed`, which for a coasting vertex is its coasting speed — is
		# the only thing that makes it hit for less. Or, flung hard, for more.
		var di := BladeDamageInstance.new(ev, gate)
		di.amount = state.vertex_damage[ev.particle_idx]
		di.type = DamageInstance.Type.PHYSICAL
		di.target = ev.target as SkillNode
		di.origin = source
		di.source = self
		di.attacker = attacker
		# Melee is #543's honest caveat: its structural parameter IS continuous
		# time the sim produced, so it is NORMALIZED against the swing rather
		# than "not timing at all". The compiler scales it back out by
		# [member PresentationTempo.swing_duration], which is what lets the
		# picture be stretched without re-simulating the blade.
		di.structural_key = ev.t / maxf(0.001, SWING_DURATION)
		sub.hits.append(di)
	if sub.hits.is_empty():
		return
	sub.schedule = OutcomeSchedule.compile(sub)
	CritRoll.decide_all(sub, rng)
	# Melee selects on physics, so nothing above read `world`: every live read
	# it makes is inside `BladeDamageInstance.land_on` -> `LiveGate.admit`,
	# which is what this pass runs. Un-awaited — see the same call in
	# [method RangedAttackPlan.resolve_against] for why that is safe.
	OutcomeApplier.apply(sub, world)
	for hit in sub.hits:
		outcome.hits.append(hit)
		hits.append(hit)


## [param drivers] minus every driver on a vertex the swing has stopped
## driving — a destroyed one (frozen; a driver would move a corpse) and a
## COASTING one (severed from the handle; a driver would keep swinging it as if
## the arm were still attached). Everything else is untouched, so an unsevered
## swing gets its own list back.
static func _surviving_drivers(
		drivers: Array[BladeDriver],
		state: BladeState,
		gate: BladePopResolver.LiveGate) -> Array[BladeDriver]:
	var coasting: Dictionary = {}
	for severance in gate.result.severances:
		for v in severance.vertices:
			coasting[v] = true
	var kept: Array[BladeDriver] = []
	for d in drivers:
		var ad := d as BladeArcDriver
		if ad != null and (state.is_vertex_removed(ad.particle) or coasting.has(ad.particle)):
			continue
		kept.append(d)
	return kept


## Build a fresh BladeState from the current selection. `MeleePreview` does
## NOT call this — it builds its own via `SkillBlade.build_from_skill_nodes`
## (see C8, the three-way construction duplication). Kept public for callers
## within this plan.
##
## [param zones] is the defender set to hang a [BladeObstacleField] off (#811).
## Null means "find them yourself" — one [method BladeDefenderZones.query] at
## this blade's own whip bound, which is what a single swing wants. A caller
## evaluating MANY blades at one pivot passes a prebuilt, shared set instead
## ([AiBladeRollout]: 192 proposals, 6 queries), and an EMPTY set means "no
## field at all", which is how that caller gets a bare state to measure the
## shared bound from.
func build_blade_state(zones: BladeDefenderZones = null) -> BladeState:
	if source == null:
		return null
	var selection: Array[SkillNode] = [source]
	selection.append_array(blade_nodes)
	var positions: Array[Vector2] = []
	var radii: Array[float] = []
	var pivot_idx := 0
	var sn_to_idx: Dictionary = {}
	for i in selection.size():
		var sn := selection[i]
		sn_to_idx[sn] = i
		positions.append(sn.global_position)
		radii.append(sn.radius)
		if sn == source:
			pivot_idx = i
	var induced_edges := get_induced_edges()
	var edge_indices: Array[Vector2i] = []
	for pair in induced_edges:
		edge_indices.append(Vector2i(sn_to_idx[pair[0]], sn_to_idx[pair[1]]))
	var blade_state := BladeState.build(positions, pivot_idx, edge_indices, radii)
	# Per-vertex damage from each source node's own blade_damage (wielder base
	# merged with node-local spike modifiers) — keeps preview/AI scoring in step
	# with the live swing in skill_blade.gd.
	for i in selection.size():
		blade_state.vertex_damage[i] = selection[i].get_local_value(&"blade_damage")
	# Per-vertex blunting, the defensive counterpart (#778) — same localized
	# read, so preview / AI scoring pop the same vertices the live swing does.
	for i in selection.size():
		blade_state.vertex_blunting[i] = selection[i].get_local_value(&"blunting")
	# No per-EDGE fill: ADR 0005 — an edge carries no stats, derived or
	# otherwise. Its geometry comes from its endpoints, its damage from nowhere.
	# Dispatch to addons after vertex_damage is populated (mirror
	# skill_blade.gd's build_from_skill_nodes) — keeps preview/resolve in
	# parity with the live swing's constraint set (e.g. Clamp's weld brace).
	for i in selection.size():
		for addon in selection[i].get_addons():
			addon.apply_to_blade(blade_state, i)
	# #823: phantom clamps the AI rollout is SCORING, not real attached
	# addons — same static ClampAddon uses for a real one
	# (ClampAddon.apply_to_blade delegates to this exact function), applied
	# after real addons so a phantom never shadows a real weld's constraint.
	for node in ai_phantom_clamp_nodes:
		if sn_to_idx.has(node):
			ClampAddon.append_weld_braces(blade_state, sn_to_idx[node])
	# The merged defender field (#780 walls + #781 plates, one query since #811)
	# — attached here so every consumer of this state (the resolve, the AI
	# rollout) meets the same defenders. Null for the ordinary swing.
	attach_defender_field(blade_state, zones if zones != null else build_defender_zones(blade_state))
	return blade_state


## Hang a [BladeObstacleField] on [param blade_state] for [param zones], or
## leave it null when there is no defender in reach — the ordinary swing, and
## the case that keeps the native solver backend reachable
## ([method BladeSim.simulate_range] gates on it).
static func attach_defender_field(blade_state: BladeState, zones: BladeDefenderZones) -> void:
	blade_state.obstacles = BladeObstacleField.new(zones) \
			if zones != null and not zones.is_empty() else null


## [SkillNode, SkillNode] pairs over the live graph, restricted to the
## current selection — i.e. the induced subgraph of pivot + members.
##
## #809: walks [method Graph.get_neighbours] (cached adjacency, O(degree))
## over the selection instead of scanning every [Edge] in the level
## (O(total graph)) — the selection is at most `blade_size + 1` nodes, so this
## is O(selection x degree) instead of O(edges).
##
## [b]Order changed on purpose, and is now explicit rather than incidental.[/b]
## The old scan emitted pairs in edge-CHILD order (whatever [method
## Graph.get_edges] happened to return); this emits them sorted by the LOWER
## endpoint's [member SkillNode.stable_id], ties broken by [method
## Graph.get_neighbours]'s own per-node order. Every consumer (`BladeState`'s
## constraint list, `AttackPlan`'s wire payload) treats this as a set of
## pairs, never a golden sequence, so a stable-but-different order is a
## behavioural no-op — see `.claude/rules/degree.md`'s neighbouring guidance
## and the #809 acceptance note on iteration order.
##
## Self-loops are preserved at their true multiplicity: [method
## Graph.get_neighbours] lists a self-looped node as its own neighbour TWICE
## per loop edge (`graph.gd`'s adjacency build), so a node's self-loop count
## is that occurrence count halved.
func get_induced_edges() -> Array:
	var out: Array = []
	if attacker == null or attacker.navigator == null:
		return out
	var graph := attacker.navigator.graph
	if graph == null:
		return out
	var selection := selection_set()
	var ordered: Array = selection.keys()
	ordered.sort_custom(func(a: SkillNode, b: SkillNode) -> bool: return a.stable_id < b.stable_id)
	for sn in ordered:
		var self_loop_hits := 0
		for neighbour in graph.get_neighbours(sn):
			if neighbour == sn:
				self_loop_hits += 1
				continue
			if not selection.has(neighbour):
				continue
			# Only take the pair from its lower-stable_id side, so an A-B edge
			# (or a repeated A-B multi-edge) surfaces exactly once per
			# underlying [Edge] rather than once from each endpoint's list.
			if neighbour.stable_id > sn.stable_id:
				out.append([sn, neighbour])
		for _i in self_loop_hits / 2:
			out.append([sn, sn])
	return out


## Public so callers can run their own [method BladeSim.simulate] pass over
## the same drivers this plan's own [method resolve] uses (#378 slice C: the
## AI's coarse-fidelity rollout re-simulates candidate blades before scanning
## only the survivors at full fidelity).
func build_drivers(blade_state: BladeState) -> Array[BladeDriver]:
	var drivers: Array[BladeDriver] = []
	var pivot_pos := blade_state.positions[blade_state.pivot_index]
	var seen: Dictionary = {}
	var sweep := -TAU if swing_cw else TAU
	for e in blade_state.edges:
		var other := -1
		if e.x == blade_state.pivot_index:
			other = e.y
		elif e.y == blade_state.pivot_index:
			other = e.x
		if other < 0 or seen.has(other):
			continue
		seen[other] = true
		var offset := blade_state.positions[other] - pivot_pos
		drivers.append(BladeArcDriver.new(
				other, pivot_pos, offset.length(), offset.angle(),
				sweep, SWING_DURATION))
	return drivers


## Ask the physics engine which defenders this swing can meet (#811).
##
## [b]One query replaces two O(map) walks.[/b] #780's `build_swing_clock` and
## #781's `build_obstacle_field` each walked all ~800 [SkillNode]s and resolved
## a stat on every one — 1744 us and 1701 us on `first_level`, measured with
## ZERO defenders present, i.e. entirely the cost of asking. Since #810 the
## predicate is a collision layer bit, so the broadphase answers it: mask =
## `swing_drag` bit | `deflection` bit, and the result is O(defenders in range).
##
## [b]Read off the LIVE graph, at the same pre-attack moment on every
## machine.[/b] A mirror peer re-runs `resolve()` on a throwaway shadow purely
## to DRAW ([BattleSystem]'s apply path) before the record lands, and
## [CombatWorld.shadow] has no physics space of its own — so this queries the
## live [World2D], exactly as [BladeHitScan] already does from
## [method _resolve_swing]. The set is frozen once, before the first sample, and
## never rebuilt mid-swing: a plate popped on wave N keeps its zone for the rest
## of the swing, which is #781's behaviour unchanged.
##
## The blade side is excluded by RID via [method collect_target_excludes] — the
## same list [BladeHitScan] gets, so "a node I or an ally own never defends
## against my own swing" is answered once instead of by a second membership
## predicate.
func build_defender_zones(blade_state: BladeState) -> BladeDefenderZones:
	if blade_state == null:
		return BladeDefenderZones.new()
	return query_defender_zones(
			blade_state.positions[blade_state.pivot_index], whip_bound(blade_state))


## [method build_defender_zones] with the disc given explicitly — the seam a
## caller with MANY blades at one pivot builds its shared set through
## ([AiBladeRollout] takes the widest whip bound over that pivot's proposals and
## issues ONE query for all of them; the result is immutable, so sharing it is
## safe even though those proposals are then simulated concurrently).
func query_defender_zones(center: Vector2, radius: float) -> BladeDefenderZones:
	if source == null or attacker == null or attacker.navigator == null:
		return BladeDefenderZones.new()
	var world := source.get_world_2d()
	if world == null:
		return BladeDefenderZones.new()
	return BladeDefenderZones.query(
			world.direct_space_state, center, radius,
			collect_target_excludes(), attacker.navigator.graph)


## The radius the defender query asks about: how far from the pivot any part of
## this blade could plausibly get during the swing.
##
## [b]Not the rest reach.[/b] The deleted `_blade_reach` bounded the swing by
## the farthest particle's CURRENT distance from the pivot, which is 65% short
## — swinging a floppy blade straightens it. A 5-node W blade whose rest reach
## is 432 px was measured whipping out to 714.6 px, and every fortified or
## bunkered node in that annulus silently failed to drag or deflect while
## [BladeHitScan], which senses off the live pose, damaged them normally (#808).
##
## [b]The chain-length bound.[/b] BFS from the pivot over the blade's own
## induced subgraph — at most `blade_size + 1` vertices — summing rest edge
## lengths, which is what the chain measures once pulled straight. For that W
## blade it gives 721.1 px against the measured 714.6, i.e. within 1%. Then
## [constant BladeDefenderZones.STRETCH_MARGIN] for XPBD's soft distance
## constraints, plus the widest blade disc and an edge half-thickness so a
## defender the blade merely grazes is still returned.
##
## Deliberately generous, and never to be re-tightened: with the predicate on
## the collision mask, a wider radius costs the solver a few float compares per
## substep and costs the QUERY nothing, while a narrower one silently drops
## defenders. A severed fragment can coast outside even this — #808's "coasting
## blade parts can go anywhere" — and is covered iff the radius happens to
## cover it; that is an accepted, one-directional degradation, not a bound
## anyone relies on.
static func whip_bound(blade_state: BladeState) -> float:
	var n := blade_state.positions.size()
	if n == 0:
		return 0.0
	var adjacency: Array[PackedInt32Array] = []
	adjacency.resize(n)
	for i in n:
		adjacency[i] = PackedInt32Array()
	for e_idx in blade_state.edges.size():
		if blade_state.removed_edges.has(e_idx):
			continue
		var e := blade_state.edges[e_idx]
		if e.x == e.y:
			continue
		adjacency[e.x].append(e.y)
		adjacency[e.y].append(e.x)
	var dist := PackedFloat32Array()
	dist.resize(n)
	dist.fill(-1.0)
	var pivot := blade_state.pivot_index
	dist[pivot] = 0.0
	var queue: Array[int] = [pivot]
	var head := 0
	var farthest := 0.0
	while head < queue.size():
		var v: int = queue[head]
		head += 1
		for w in adjacency[v]:
			if dist[w] >= 0.0:
				continue
			dist[w] = dist[v] + blade_state.positions[v].distance_to(blade_state.positions[w])
			farthest = maxf(farthest, dist[w])
			queue.append(w)
	var widest := 0.0
	for r in blade_state.radii:
		widest = maxf(widest, r)
	return farthest * BladeDefenderZones.STRETCH_MARGIN + widest + BladeHitScan.EDGE_RADIUS


func _set_swing_cw(value: bool) -> void:
	if swing_cw == value:
		return
	swing_cw = value
	_notify_selection_changed()


## RIDs to feed BladeHitScan as the physics-query exclude list — covers only
## the blade members themselves (don't hit their own subgraph) and nodes
## owned by the attacker. #502: unallocated nodes are NOT excluded here
## anymore — the scan now sees them too, so a swing sweeping across ground
## that just died mid-cascade produces the same events it would against
## ground that was never allocated (no visible difference, per contract).
## The live ownership/allocation gate moves to consumption time; see
## [BladeDamageInstance.land_on] / [BladePopResolver.LiveGate].
##
## #809: starts from the pre-mirrored owned subgraphs — [member
## Entity.navigator]'s own [method GraphMirror.get_mirrored_nodes] (MINE) plus
## every ALLIED entity's own navigator (ALLY) — instead of filtering all of
## [method Graph.get_skill_nodes] through a per-node ownership predicate.
## `self_set` (the selection itself) is still unioned in explicitly: a blade
## member is always MINE by construction ([method _can_be_blade] gates
## selection on `owned_by == attacker`), so this is redundant on every path
## that exists today, but it keeps the exact "self_set OR MINE OR ALLY"
## membership rather than silently narrowing it.
##
## [b]This is now the ONE answer to "is that node on my side".[/b] Since #811
## it is also the defender query's exclude list
## ([method build_defender_zones]) — the deleted `_is_blade_side` was a second
## implementation of the same membership, and a blade that bogged down on its
## own wall would have been the symptom of the two drifting apart (#384's
## vocabulary throughout: ownership bits, never `owned_by == attacker`).
##
## Allies are enumerated via [constant Entity.GROUP] (the same whole-tree
## roll call [TurnManager] / [VictorySystem] / [GameRoot] already use), not
## [member Graph.entities_container] — a plan's `attacker` isn't guaranteed to
## sit under that container (fixtures parent entities straight onto the
## graph), while every live [Entity] is unconditionally in its group from
## [method Entity._ready].
##
## [b]Order changed on purpose.[/b] The old scan walked [method
## Graph.get_skill_nodes]'s child order; [method GraphMirror.get_mirrored_nodes]
## is explicit that its own order is dictionary-iteration, not stable — so
## this sorts the union by [member SkillNode.stable_id] before minting RIDs.
## Physics-server exclude lists are unordered by nature (see [method
## BladeHitScan.Sweep]'s call site), so this is a determinism/legibility
## choice, not a correctness one; #809's acceptance note on iteration order.
func collect_target_excludes() -> Array[RID]:
	var out: Array[RID] = []
	if attacker == null or attacker.navigator == null:
		return out
	var seen: Dictionary = {}
	var nodes: Array[SkillNode] = []
	for sn in selection_set():
		if sn != null and not seen.has(sn):
			seen[sn] = true
			nodes.append(sn)
	for sn in attacker.navigator.get_mirrored_nodes():
		if not seen.has(sn):
			seen[sn] = true
			nodes.append(sn)
	var tree := attacker.get_tree()
	if tree != null:
		for node in tree.get_nodes_in_group(Entity.GROUP):
			var ally := node as Entity
			if ally == null or ally == attacker or ally.navigator == null:
				continue
			if attacker.attitude_to(ally) != Entity.Attitude.ALLIED:
				continue
			for sn in ally.navigator.get_mirrored_nodes():
				if not seen.has(sn):
					seen[sn] = true
					nodes.append(sn)
	nodes.sort_custom(func(a: SkillNode, b: SkillNode) -> bool: return a.stable_id < b.stable_id)
	for sn in nodes:
		out.append(sn.get_rid())
	return out


## Pivot + members as a set — the blade's own nodes, and nothing else.
func selection_set() -> Dictionary:
	var out: Dictionary = {}
	if source != null:
		out[source] = true
	for b in blade_nodes:
		out[b] = true
	return out


func _is_neighbor_of_blade_set(node: SkillNode) -> bool:
	# Adjacency to pivot OR any current blade member, via the live graph's
	# edges. The mirror can't answer this for candidates (they're not yet
	# in it); use the graph directly.
	if attacker == null or attacker.navigator == null:
		return false
	var graph := attacker.navigator.graph
	if graph == null:
		return false
	for e in graph.get_edges():
		var other: SkillNode = null
		if e.from == node:
			other = e.to
		elif e.to == node:
			other = e.from
		else:
			continue
		if other == source or blade_nodes.has(other):
			return true
	return false
