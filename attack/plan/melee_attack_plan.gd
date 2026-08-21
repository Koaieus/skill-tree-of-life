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
## Pure resolve-time ESTIMATE (#502) — [BladePopResolver.resolve] run once,
## before anything lands, so it reads the pre-swing world for every event
## uniformly. Feeds [member AttackOutcome.thinned_nodes] for AI scoring, which
## can't run the live applier against the real world (docs/domain/
## attack-timeline.md's substrate section). NOT what [MeleePreview] replays
## for a real launch — see [member last_live_gate].
var last_pops: BladePopResolver.Result = null
## The LIVE gate driving the swing actually being applied — [BladeDamageInstance
## .land_on] calls [method BladePopResolver.LiveGate.admit] on this exact
## instance, once per hit, in true land order, as [OutcomeApplier] applies
## [member last_hits]. Its `result` accumulates what ACTUALLY happened: the
## applier's accepted set, never a rescan and never the pre-swing estimate
## ([member last_pops]). Null until [method resolve] runs.
##
## [b]#504: nothing reads `result` back anymore, and that is the point.[/b]
## [MeleePreview] used to snapshot it at the top of `launch()` to re-announce
## spike pops on its animation clock, which only worked because the whole
## outcome was applied BEFORE the replay began. The swing now animates
## concurrently with the mutation, so that snapshot would be empty — the pop is
## emitted from [BladePopResolver.LiveGate] as it happens instead. Do not
## reintroduce a reader here that assumes this is complete at any particular
## moment; it fills in over the beat clock.
var last_live_gate: BladePopResolver.LiveGate = null
## The [DamageInstance]s (concretely [BladeDamageInstance]) [method resolve]
## built from [member last_events] — one per non-edge event, in order, whether
## or not it will actually land (that decision is [member last_live_gate]'s,
## made at [method BladeDamageInstance.land_on] time). [MeleePreview] consumes
## these FIFO as its live replay passes each event through the SAME sequence,
## so its reveal can show [member HitInstance.effective_amount] (set by
## [method SkillNode.take_damage] when the real applier landed it) instead of
## re-deriving damage from a freshly rebuilt blade state, which drifts from
## what actually landed. Melee only ever produces [DamageInstance]s (never
## heals), so this stays narrowly typed rather than the [AttackOutcome]-wide
## [code]Array[HitInstance][/code] (#381).
var last_hits: Array[DamageInstance] = []


func resolve() -> AttackOutcome:
	var outcome := AttackOutcome.new()
	outcome.resolve_seed = resolve_seed
	if not is_valid():
		return outcome
	var blade_state := build_blade_state()
	if blade_state == null:
		return outcome
	var drivers := build_drivers(blade_state)
	var trajectory := BladeSim.simulate(blade_state, drivers, SWING_DURATION)
	var space_state := source.get_world_2d().direct_space_state
	var exclude := collect_target_excludes()
	var events := BladeHitScan.scan(
			trajectory, blade_state, space_state, 0xFFFFFFFF, exclude)
	# #170/#502: pure, up-front ESTIMATE only — BladePopResolver.resolve runs
	# before anything lands, so it can't see this swing's own cascades. Feeds
	# thinned_nodes for AI scoring / AP estimation; the REAL gate for a live
	# launch is last_live_gate below, re-evaluated per event at land time.
	var pops := BladePopResolver.resolve(events, blade_state, attacker)
	outcome.thinned_nodes = pops.dead_at.size()
	last_trajectory = trajectory
	last_events = events
	last_pops = pops
	var gate := BladePopResolver.LiveGate.new(blade_state, attacker)
	last_live_gate = gate
	var di_list: Array[DamageInstance] = []
	for ev in events:
		# D-1 MVP: edges are inert. Skip them so preview/AP estimation matches
		# the live swing's per-event behaviour in skill_blade.gd.
		if ev.is_edge_hit():
			continue
		# #502: no pre-filtering by pops/allocation here — every non-edge event
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
		di.arrival_time = ev.t
		outcome.hits.append(di)
		di_list.append(di)
	last_hits = di_list
	# Every blade landing rolls its own crit (#507 — owner call: "a hit can
	# crit"), off the stamped seed, never `randf()`. So a wide blade sweeping
	# many nodes gets more lottery tickets than a narrow one; settled as
	# intended, not a reason to fall back to one roll per swing.
	# `decide_all` sorts by `arrival_time` itself, so this does not depend on
	# BladeHitScan emitting events in `t` order.
	CritRoll.decide_all(outcome, CritRoll.stream_for(resolve_seed))
	return outcome


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
	var selection: Dictionary = {}
	if source != null:
		selection[source] = true
	for b in blade_nodes:
		selection[b] = true
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
	var self_set: Dictionary = {}
	if source != null:
		self_set[source] = true
	for b in blade_nodes:
		self_set[b] = true
	for sn in graph.get_skill_nodes():
		# MINE|ALLY (#384's vocabulary), not `owned_by == attacker`: a blade
		# must pass through a co-op partner's territory as cleanly as its own.
		# Excluding at SCAN time — the blade never queries these colliders — is
		# deliberate despite the land-time-gate rule (docs/domain/attack-timeline.md):
		# faction can't change mid-swing, so the only drift is an ally node
		# deallocating to NEUTRAL mid-cascade and us skipping a hit we could
		# have landed. Negligible; don't add a land-time re-check for it.
		var bit := sn.ownership_bit(attacker)
		if self_set.has(sn) or bit == SkillNode.Ownership.MINE or bit == SkillNode.Ownership.ALLY:
			out.append(sn.get_rid())
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
