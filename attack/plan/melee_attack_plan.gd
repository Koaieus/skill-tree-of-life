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
	if what == NOTIFICATION_PREDELETE and _blade_mirror != null:
		_blade_mirror.free()
		_blade_mirror = null


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
		state_changed.emit()
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
		state_changed.emit()


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
	state_changed.emit()
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
	state_changed.emit()
	return true


## Refund `node`'s temp upgrade, if any — frees the attached addon.
func remove_temp_upgrade(node: SkillNode) -> void:
	if _free_temp_addons(node):
		state_changed.emit()


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
	state_changed.emit()


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
## Every severed fragment this swing flew, in birth order (#186) — the driven
## blade's own fragments first, then any fragment a fragment shed. Empty on a
## swing that lost nothing, which is the overwhelming majority.
##
## Exposed because a fragment's flight is a THING THAT HAPPENED and the visual
## layer will need it: today [MeleePreview] replays [member last_trajectory]
## only, so a coasting fragment deals its damage without being drawn. Wiring
## that picture up (together with the pop cue's missing velocity) is its own
## issue, called out in #186's NOTES and deliberately not ridden in here.
var last_free_flights: Array[BladeFreeFlight.Flight] = []


func resolve_against(world: CombatWorld) -> AttackOutcome:
	var outcome := AttackOutcome.new()
	outcome.cadence = ScheduleEntry.Cadence.SWING
	outcome.resolve_seed = resolve_seed
	if not is_valid():
		return outcome
	var blade_state := build_blade_state()
	if blade_state == null:
		return outcome
	var drivers := build_drivers(blade_state)
	# Fortification drag (#780): a wall of fortified nodes bogs the swing's own
	# clock down, cumulatively, from the moment the blade first touches one. Null
	# when there is none in reach, which is the ordinary swing.
	var swing_clock := build_swing_clock(blade_state)
	var trajectory := BladeSim.simulate(
			blade_state, drivers, SWING_DURATION, BladeSim.DEFAULT_DT,
			BladeSim.DEFAULT_ITERATIONS, 0.0, BladeSim.DEFAULT_SUBSTEPS,
			true, 0.0, PackedVector2Array(), swing_clock)
	var space_state := source.get_world_2d().direct_space_state
	var exclude := collect_target_excludes()
	# #530: the scan itself stable-sorts on SkillNode.stable_id, so the hit
	# SET a pop cascade sees below never depends on physics broadphase order —
	# nothing here re-sorts.
	var events := BladeHitScan.scan(
			trajectory, blade_state, space_state, attacker.navigator.graph,
			0xFFFFFFFF, exclude)
	last_trajectory = trajectory
	last_events = events
	# #170/#502/#536: ONE pop gate, re-evaluated per event at land time, so it
	# sees this swing's own cascades. The up-front batch estimate it replaced
	# could not — and disagreed with this one about a vertex that disintegrates
	# before it pops. `popped_nodes` is stamped from this gate's result once
	# the apply below has run it.
	var gate := BladePopResolver.LiveGate.new(blade_state, attacker)
	last_live_gate = gate
	last_pops = gate.result
	var di_list: Array[DamageInstance] = []
	for ev in events:
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
		# consumes it (docs/domain/attack-timeline.md).
		var di := BladeDamageInstance.new(ev, gate)
		di.amount = blade_state.vertex_damage[ev.particle_idx]
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
		outcome.hits.append(di)
		di_list.append(di)
	last_hits = di_list
	# Seconds, once, before `decide_all` consumes its stream in landing order.
	outcome.schedule = OutcomeSchedule.compile(outcome)
	# Every blade landing rolls its own crit (#507 — owner call: "a hit can
	# crit"), off the stamped seed, never `randf()`. So a wide blade sweeping
	# many nodes gets more lottery tickets than a narrow one; settled as
	# intended, not a reason to fall back to one roll per swing.
	# `decide_all` sorts by the compiled schedule index itself, so this does not
	# depend on BladeHitScan emitting events in `t` order.
	CritRoll.decide_all(outcome, CritRoll.stream_for(resolve_seed))
	# Melee selects on physics, so nothing above read `world`: every live read
	# it makes is inside `BladeDamageInstance.land_on` -> `LiveGate.admit`,
	# which is what this pass runs. Un-awaited — see the same call in
	# [method RangedAttackPlan.resolve_against] for why that is safe.
	OutcomeApplier.apply(outcome, world)
	# #186: everything the swing SEVERED is now known — it could not have been
	# known any earlier, because a pop is decided at land time against the live
	# world, not at scan time. So free flight is a second round over the same
	# world, gated and applied by the same machinery, appending to the same
	# outcome. The hits it produces therefore ride the AttackRecord like any
	# other landing and a peer replays them; nothing re-derives a solver.
	_fly_severed_fragments(outcome, world, blade_state, trajectory, gate,
			space_state, exclude)
	# The AI's shape-risk signal, now a RESULT of the gate rather than a
	# separate estimate of it: how many of the attacker's own vertices this
	# swing actually DESTROYED. Pops only, never `dead_at.size()` (#799) —
	# `dead_at` also holds the vertices those pops merely orphaned, and since
	# #186 an orphan is not a loss: it coasts on as a free fragment and lands
	# its own hits above. `_fly_severed_fragments` has already added whatever
	# the coasting rounds got popped for in turn.
	outcome.popped_nodes += gate.result.vertex_pop_count()
	return outcome


## Distinct crit streams per free-flight round (#186). One stream per attack is
## the rule, but a round is not a re-roll of the same landings — it is a fresh
## set of them — and reusing `resolve_seed` unsalted would make every round
## draw the identical sequence. Derived, so the whole attack still reproduces
## from one seed.
const _FREE_FLIGHT_STREAM_SALT: int = 0x27D4EB2F


## Fly every fragment this swing severed, and every fragment those shed in turn
## (#186). One round per fragment: re-simulate it as an UNPINNED body from its
## separation velocity, scan the trajectory, and land what it hits.
##
## [b]A round gets its own [BladePopResolver.LiveGate], and must.[/b] The
## swing's gate has these vertices in `dead_at` — correctly, they have left the
## DRIVEN blade — so reusing it would refuse every hit the fragment goes on to
## make. The fragment is a new body; it gets a new gate over its own compacted
## state. The world is unchanged between them, so a spikes pool the swing
## already drained is still drained when the fragment arrives (#186 acceptance
## 2), which is the part that actually has to be shared and is, by being the
## world rather than the gate.
##
## [b]Ordering caveat, deliberate.[/b] These land after the whole driven swing
## has landed, not interleaved by `t`. On the authority that reordering is
## invisible: `resolve_against` computes against a SHADOW world and what
## reaches the live world is the record, whose merged schedule IS in `t` order
## (recompiled below). The only residue is that two landings on the SAME node,
## one driven and one free, may see each other's mitigation in shadow order.
## Interleaving properly would mean an [OutcomeApplier] that can be suspended
## mid-walk and resumed with hits discovered during it — a real change to the
## applier, and not one #186 needs.
func _fly_severed_fragments(
		outcome: AttackOutcome,
		world: CombatWorld,
		root_state: BladeState,
		root_traj: BladeTrajectory,
		root_gate: BladePopResolver.LiveGate,
		space_state: PhysicsDirectSpaceState2D,
		exclude: Array[RID]) -> void:
	last_free_flights = []
	if space_state == null or root_gate == null or root_gate.result.fragments.is_empty():
		return
	var graph: Graph = attacker.navigator.graph if attacker != null and attacker.navigator != null else null
	# Each entry: [source_state, source_trajectory, source_birth_t, fragment].
	# A queue rather than a single pass because a coasting fragment can be
	# popped in turn and shed a fragment of its own; every such fragment is
	# strictly smaller than its parent, so this terminates.
	var queue: Array = []
	for f in root_gate.result.fragments:
		queue.append([root_state, root_traj, 0.0, f])
	var round_idx := 0
	while not queue.is_empty():
		var job: Array = queue.pop_front()
		var flight := BladeFreeFlight.spawn(
				job[0] as BladeState, job[1] as BladeTrajectory, float(job[2]),
				job[3] as BladePopResolver.Fragment, SWING_DURATION)
		if flight == null:
			continue  # born at or past the end of the swing — nothing left to fly
		round_idx += 1
		last_free_flights.append(flight)
		var gate := BladePopResolver.LiveGate.new(flight.state, attacker)
		var events := BladeHitScan.scan(
				flight.trajectory, flight.state, space_state, graph,
				0xFFFFFFFF, exclude)
		var sub := AttackOutcome.new()
		sub.cadence = ScheduleEntry.Cadence.SWING
		sub.resolve_seed = resolve_seed
		for ev in events:
			# The scan works in the fragment's own local time; the gate, the
			# schedule and the record all work in swing time.
			ev.t += flight.birth_t
			# An EDGE contact mints no DamageInstance, exactly as on the driven
			# swing (ADR 0005): edges give rigidity, nodes deal damage. A coasting
			# fragment's edges still collide — that is what stops one entering a
			# bunker's interior — and #781's break will consume these events, but
			# there is no damage for a crit roll or a schedule entry to be about.
			if ev.is_edge_hit():
				continue
			var di := BladeDamageInstance.new(ev, gate)
			# No disconnection scale (#186 acceptance 3): the SAME coefficient a
			# driven vertex would carry, and #779's speed curve — applied in
			# BladeDamageInstance.land_on off `ev.speed`, which for a coasting
			# fragment is exactly its coasting speed — is the only thing that
			# makes a fragment hit for less. Or, if it was flung hard, for more.
			di.amount = flight.state.vertex_damage[ev.particle_idx]
			di.type = DamageInstance.Type.PHYSICAL
			di.target = ev.target as SkillNode
			di.origin = source
			di.source = self
			di.attacker = attacker
			di.structural_key = ev.t / maxf(0.001, SWING_DURATION)
			sub.hits.append(di)
		sub.schedule = OutcomeSchedule.compile(sub)
		CritRoll.decide_all(sub, CritRoll.stream_for(
				resolve_seed + round_idx * _FREE_FLIGHT_STREAM_SALT))
		OutcomeApplier.apply(sub, world)
		# A coasting vertex a spike destroys is destroyed for real, so it is a
		# loss on exactly the terms the driven swing's pops are (#799). Its
		# gate is per-round and local, hence the accumulate here rather than a
		# single read at the end.
		outcome.popped_nodes += gate.result.vertex_pop_count()
		for hit in sub.hits:
			outcome.hits.append(hit)
		for f in gate.result.fragments:
			queue.append([flight.state, flight.trajectory, flight.birth_t, f])
	if round_idx > 0:
		# One coherent timeline over driven + free landings. The record carries
		# each hit's structural key and every peer compiles its own seconds from
		# it, so this is what stops a fragment's landings from claiming schedule
		# indices the driven swing already used.
		outcome.schedule = OutcomeSchedule.compile(outcome)


## Build a fresh BladeState from the current selection. `MeleePreview` does
## NOT call this — it builds its own via `SkillBlade.build_from_skill_nodes`
## (see C8, the three-way construction duplication). Kept public for callers
## within this plan.
func build_blade_state() -> BladeState:
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
	return blade_state


## [SkillNode, SkillNode] pairs over the live graph, restricted to the
## current selection — i.e. the induced subgraph of pivot + members.
func get_induced_edges() -> Array:
	var out: Array = []
	if attacker == null or attacker.navigator == null:
		return out
	var graph := attacker.navigator.graph
	if graph == null:
		return out
	var selection := selection_set()
	for e in graph.get_edges():
		if selection.has(e.from) and selection.has(e.to):
			out.append([e.from, e.to])
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


## Build this swing's [BladeSwingClock] from the graph, or return null when no
## fortified node is anywhere near the arc (#780).
##
## [b]Null is the common case and it matters.[/b] A null clock leaves both
## [BladeArcDriver] and [method BladeSim.simulate] on the exact expressions they
## ran before drag existed, native backend included — so Fortification costs a
## swing that never meets it precisely nothing.
##
## Read off the LIVE graph, at the same pre-attack moment on every machine: a
## mirror peer re-runs `resolve()` on a throwaway shadow purely to DRAW
## ([BattleSystem]'s apply path), before the record lands, so it builds this
## field from the same node states the authority did (#780 acceptance 6).
##
## Zones are culled to what the blade can physically reach — the farthest
## particle's distance from the pivot, which is exactly the radius of the
## widest arc any part of it sweeps.
func build_swing_clock(blade_state: BladeState) -> BladeSwingClock:
	if blade_state == null or attacker == null or attacker.navigator == null:
		return null
	var graph := attacker.navigator.graph
	if graph == null:
		return null
	var pivot := blade_state.positions[blade_state.pivot_index]
	var reach := 0.0
	for i in blade_state.positions.size():
		var r: float = blade_state.radii[i] if i < blade_state.radii.size() else 0.0
		reach = maxf(reach, pivot.distance_to(blade_state.positions[i]) + r)
	var self_set := selection_set()
	var clock := BladeSwingClock.new(SWING_DURATION)
	for sn in graph.get_skill_nodes():
		if _is_blade_side(sn, self_set):
			continue
		var amount := float(sn.get_local_value(&"swing_drag"))
		if amount <= 0.0:
			continue
		if pivot.distance_to(sn.global_position) > reach + sn.radius:
			continue
		clock.add_zone(sn.global_position, sn.radius, amount)
	return clock if clock.has_zones() else null


func _set_swing_cw(value: bool) -> void:
	if swing_cw == value:
		return
	swing_cw = value
	state_changed.emit()


## RIDs to feed BladeHitScan as the physics-query exclude list — covers only
## the blade members themselves (don't hit their own subgraph) and nodes
## owned by the attacker. #502: unallocated nodes are NOT excluded here
## anymore — the scan now sees them too, so a swing sweeping across ground
## that just died mid-cascade produces the same events it would against
## ground that was never allocated (no visible difference, per contract).
## The live ownership/allocation gate moves to consumption time; see
## [BladeDamageInstance.land_on] / [BladePopResolver.LiveGate].
func collect_target_excludes() -> Array[RID]:
	var out: Array[RID] = []
	if attacker == null or attacker.navigator == null:
		return out
	var graph := attacker.navigator.graph
	if graph == null:
		return out
	var self_set := selection_set()
	for sn in graph.get_skill_nodes():
		# MINE|ALLY (#384's vocabulary), not `owned_by == attacker`: a blade
		# must pass through a co-op partner's territory as cleanly as its own.
		# Excluding at SCAN time — the blade never queries these colliders — is
		# deliberate despite the land-time-gate rule (docs/domain/attack-timeline.md):
		# faction can't change mid-swing, so the only drift is an ally node
		# deallocating to NEUTRAL mid-cascade and us skipping a hit we could
		# have landed. Negligible; don't add a land-time re-check for it.
		if _is_blade_side(sn, self_set):
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


## True if [param sn] belongs to the swinging side: a blade member itself, or
## MINE/ALLY territory the blade passes through cleanly (#384's vocabulary,
## never `owned_by == attacker`). The one place that question is answered — both
## the scan excludes and the drag field (#780) must agree on it, or a blade
## would bog down on its own wall.
func _is_blade_side(sn: SkillNode, self_set: Dictionary) -> bool:
	var bit := sn.ownership_bit(attacker)
	return self_set.has(sn) \
			or bit == SkillNode.Ownership.MINE \
			or bit == SkillNode.Ownership.ALLY


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
