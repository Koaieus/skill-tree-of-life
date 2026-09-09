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
	## The swing's own drag clock and bunker field, at their END state. Null
	## exactly when [method MeleeAttackPlan.build_swing_clock] /
	## [method MeleeAttackPlan.build_obstacle_field] returned null — the
	## ordinary swing, which allocates neither.
	var clock: BladeSwingClock = null
	var obstacles: BladeObstacleField = null


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
## Defenders the cached prediction says will pop a vertex or shatter an edge,
## as a set — read by [method get_node_role] with no work of its own.
var _predicted_defenders: Dictionary[SkillNode, bool] = {}


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
	if _prediction != null:
		return
	if not is_valid():
		return
	var world := CombatWorld.shadow()
	prediction_runs += 1
	_prediction = _resolve_swing(world)
	world.free_shadow()
	for pop in _prediction.pops.pops:
		if pop.defender != null:
			_predicted_defenders[pop.defender] = true


## Drop the cached prediction. Called from every site that emits
## [signal HighlightProvider.state_changed] — the selection, the swing
## direction and the temp-upgrade set are all inputs to the resolve.
func _invalidate_prediction() -> void:
	_prediction = null
	_predicted_defenders.clear()


## Drop the prediction and tell the surfaces. Every site in this plan that used
## to emit [signal HighlightProvider.state_changed] goes through here instead:
## the selection, the swing direction and the temp-upgrade set are all inputs to
## the resolve, so "the state changed" and "the prediction is stale" are the same
## event and must never be able to drift apart.
func _notify_selection_changed() -> void:
	_invalidate_prediction()
	state_changed.emit()


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
	var result := SwingResult.new()
	var outcome := AttackOutcome.new()
	result.outcome = outcome
	outcome.cadence = ScheduleEntry.Cadence.SWING
	outcome.resolve_seed = resolve_seed
	if not is_valid():
		return result
	var state := build_blade_state()
	if state == null:
		return result
	var drivers := build_drivers(state)
	# Fortification drag (#780): a wall of fortified nodes bogs the swing's own
	# clock down, cumulatively, from the moment the blade first touches one. Null
	# when there is none in reach, which is the ordinary swing. ONE instance for
	# the whole swing, carried across every chunk — see BladeSwingClock.Bank.
	var clock := build_swing_clock(state)
	# A bunker's grip stall (#781) is expressed on the clock, so a swing with
	# plates in reach but no wall still gets one. An untouched clock is
	# bit-inert (test_blade_swing_drag pins it), and the field already forces
	# the GDScript backend, so this costs nothing extra.
	var obstacles := state.obstacles
	if clock == null and obstacles != null:
		clock = BladeSwingClock.new(SWING_DURATION)
	var space_state := source.get_world_2d().direct_space_state
	var exclude := collect_target_excludes()
	var graph: Graph = attacker.navigator.graph if attacker != null and attacker.navigator != null else null
	# #170/#502/#536: ONE pop gate for the whole swing, re-evaluated per event at
	# land time, so it sees this swing's own cascades. Since #801 it also sees
	# them EARLY ENOUGH TO MATTER: a death lands before the samples after it are
	# simulated, so the solver can react to it.
	var gate := BladePopResolver.LiveGate.new(state, attacker)
	result.live_gate = gate
	result.pops = gate.result
	result.clock = clock
	result.obstacles = obstacles
	# #530: each batch stable-sorts on SkillNode.stable_id, so the hit SET a pop
	# cascade sees never depends on physics broadphase order.
	var sweep: BladeHitScan.Sweep = null
	if space_state != null:
		sweep = BladeHitScan.Sweep.new(state, space_state, graph, 0xFFFFFFFF, exclude)

	var dt := BladeSim.DEFAULT_DT
	var total_steps := int(ceil(SWING_DURATION / dt))
	var trajectory := BladeTrajectory.new()
	trajectory.sample_dt = dt
	trajectory.samples = [state.positions.duplicate()]
	var zero_speeds := PackedFloat32Array()
	zero_speeds.resize(state.positions.size())
	var speed_history: Array[PackedFloat32Array] = [zero_speeds]
	var events: Array[BladeHitEvent] = []
	var hits: Array[DamageInstance] = []
	# ONE crit stream for the whole swing, handed to every batch's `decide_all`
	# in turn (#507). Batches run in `t` order and `OutcomeSchedule._sorted` is
	# stable on insertion, so the stream is consumed in exactly the order a
	# single `decide_all` over the finished hit list would have consumed it —
	# which is why an unsevered swing rolls the identical crits it did before
	# the interleave. #186's per-round salt is gone with the rounds.
	var rng := CritRoll.stream_for(resolve_seed)

	var chunk_start := 0
	while chunk_start < total_steps:
		# OPTIMISTIC BAKE: the whole remaining swing in one call, assuming
		# nothing dies. Because a bake is a pure function of the state, walking
		# it sample by sample and re-baking from the first death produces the
		# bit-identical trajectory a true per-sample interleave would (#801) —
		# at one solver call per SEVERANCE instead of one per sample.
		var chunk := BladeSim.simulate_range(
				state, drivers, chunk_start, total_steps - chunk_start, dt,
				BladeSim.DEFAULT_ITERATIONS, 0.0, BladeSim.DEFAULT_SUBSTEPS,
				true, clock)
		var chunk_speeds := state.speed_history
		var severed_at := -1
		for j in range(1, chunk.samples.size()):
			var step := chunk_start + j
			var pose: PackedVector2Array = chunk.samples[j]
			var speeds: PackedFloat32Array = chunk_speeds[j]
			trajectory.samples.append(pose)
			speed_history.append(speeds)
			var pops_before := gate.result.pops.size()
			if sweep != null:
				var batch := sweep.scan_sample(float(step) * dt, pose, speeds)
				if not batch.is_empty():
					events.append_array(batch)
					_land_batch(outcome, batch, state, gate, world, rng, hits)
			# A bunker break (#781) is decided INSIDE the bake, by the field, at
			# the substep the strain crossed the threshold — so it is checked
			# per sample whether or not anything was hit, and severs exactly
			# like a pop: stop, rewind, apply, re-bake.
			var broke := obstacles != null and obstacles.has_break_at(step)
			if gate.result.pops.size() != pops_before or broke:
				severed_at = step
				break
		if severed_at < 0:
			break
		# REWIND TO THE DEATH. The bake above ran past it, so `state` is at the
		# end of the swing, not at `severed_at`. The bake recorded the exact
		# state at every sample — `prev_samples` alongside `samples`, and the
		# clock its own bank (#803) — so landing on the severance sample is a
		# read, not a re-run. (`_step` rewrites `prev_positions` once per
		# SUBSTEP, so it is a mid-sample pose that `samples` alone could never
		# recover; #801 re-baked the head of the chunk to get it before both
		# backends emitted it.) Duplicated because `_step` writes through the
		# reference, and the trajectory keeps these same arrays.
		var local := severed_at - chunk_start
		state.positions = chunk.samples[local].duplicate()
		state.prev_positions = chunk.prev_samples[local].duplicate()
		if clock != null:
			clock.restore(clock.history[local])
		if obstacles != null:
			obstacles.restore(obstacles.history[local])
		# THE WHOLE OF A SEVERANCE: a corpse frozen where it died, its
		# constraints and its driver gone, and drag written onto whatever it was
		# holding on. Nothing else — everything downstream then coasts by plain
		# Verlet, because that is what Verlet does to a particle nothing is
		# pulling on.
		# The bank restored just above IS the one the break was armed in — the
		# field banks once per sample, after that sample's substeps — so the
		# break is consumed HERE, off the rewound field, with nothing re-run.
		if obstacles != null:
			var brk := obstacles.consume_break()
			if brk != null:
				gate._sever_edge(brk.edge_idx, float(severed_at) * dt, brk.defender, 0.0)
		for pop in gate.result.pops:
			if pop.particle_idx >= 0:
				state.remove_vertex(pop.particle_idx)
		for severance in gate.result.severances:
			for v in severance.vertices:
				state.set_damping(v, BladeState.SEVERED_DRAG)
		drivers = _surviving_drivers(drivers, state, gate)
		chunk_start = severed_at
	state.speed_history = speed_history
	result.trajectory = trajectory
	result.events = events
	result.hits = hits
	# One coherent timeline over every batch. The record carries each hit's
	# structural key and every peer compiles its own seconds from it.
	outcome.schedule = OutcomeSchedule.compile(outcome)
	# The AI's shape-risk signal: how many of the attacker's own vertices this
	# swing actually DESTROYED. Pops only (#799) — a vertex that merely lost its
	# path to the handle coasts on in this same trajectory and is not a loss.
	outcome.popped_nodes += gate.result.vertex_pop_count()
	return result


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
	# Bunker field (#781) — the defender-side twin of the drag clock, attached
	# here so every consumer of this state (the resolve, the AI rollout) deflects
	# off the same plates. Null for the ordinary swing.
	blade_state.obstacles = build_obstacle_field(blade_state)
	return blade_state


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
	var reach := _blade_reach(blade_state)
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


## Build this swing's [BladeObstacleField] from the graph, or return null when
## no deflecting node (`deflection` true — a BOOL stat, presence only, §805;
## only [BunkerAddon] authors it) is anywhere near the arc (#781). Null is the
## common case and it is
## load-bearing: with no field there is no accumulator, no pushout and no
## GDScript fallback — a map with zero bunkers cannot produce a break, by
## construction, at any blade size or speed. Same cull, same blade-side
## exclusion and the same live-graph read as [method build_swing_clock], so a
## mirror peer redrawing the swing builds the identical field.
func build_obstacle_field(blade_state: BladeState) -> BladeObstacleField:
	if blade_state == null or attacker == null or attacker.navigator == null:
		return null
	var graph := attacker.navigator.graph
	if graph == null:
		return null
	var pivot := blade_state.positions[blade_state.pivot_index]
	var reach := _blade_reach(blade_state)
	var self_set := selection_set()
	var field := BladeObstacleField.new()
	for sn in graph.get_skill_nodes():
		if _is_blade_side(sn, self_set):
			continue
		if not bool(sn.get_local_value(&"deflection")):
			continue
		if pivot.distance_to(sn.global_position) > reach + sn.radius:
			continue
		field.add_zone(sn.global_position, sn.radius, sn)
	return field if field.has_zones() else null


## The widest arc any part of the blade sweeps: the farthest particle's
## distance from the pivot plus its own radius.
static func _blade_reach(blade_state: BladeState) -> float:
	var pivot := blade_state.positions[blade_state.pivot_index]
	var reach := 0.0
	for i in blade_state.positions.size():
		var r: float = blade_state.radii[i] if i < blade_state.radii.size() else 0.0
		reach = maxf(reach, pivot.distance_to(blade_state.positions[i]) + r)
	return reach


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
## [method Graph.get_skill_nodes] through [method _is_blade_side] per node.
## `self_set` (the selection itself) is still unioned in explicitly: a blade
## member is always MINE by construction ([method _can_be_blade] gates
## selection on `owned_by == attacker`), so this is redundant on every path
## that exists today, but it keeps the exact "self_set OR MINE OR ALLY"
## membership [method _is_blade_side] still answers for [method
## build_swing_clock] / [method build_obstacle_field] (#807/#808, untouched
## here) rather than silently narrowing it.
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
