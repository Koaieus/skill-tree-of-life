class_name MeleeAttackPlan
extends AttackPlan

## A melee attack as an induced sub-subgraph of the attacker's owned territory:
## one PIVOT (left-click, when unset) plus up to `blade_size` MEMBERS
## (left-click toggle, once the pivot is set) that must form a connected
## subgraph through the pivot. Deselecting any member cascades — anyone newly
## disconnected from the pivot drops too — keeping the blade well-formed at
## every step. Right-click pops the pivot (and every member with it) back to
## "no pivot yet" — see docs/design/click_grammar.md.

const _BLADE_SIZE_ID: StringName = &"blade_size"

## Swing duration the sim is built around. Real-time playback (live or
## ghost) honours the same value so preview matches commit.
const SWING_DURATION: float = 1.2

## The pivot — right-clicked, owned-by-attacker. Always in the blade mirror.
var source: SkillNode = null

## The selected member nodes (excludes pivot). Each is owned-by-attacker and
## reachable from the pivot through this list + the pivot via graph edges.
var blade_nodes: Array[SkillNode] = []

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
	elif _try_select_blade(node):
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
			and blade_nodes.size() < max_blades() \
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


# ── State mutations (all assume legitimacy already gated) ──────────────────

func _set_pivot(node: SkillNode) -> void:
	_ensure_mirror()
	for b in blade_nodes:
		_blade_mirror.mirror_remove(b)
	blade_nodes.clear()
	if source != null:
		_blade_mirror.mirror_remove(source)
	source = node
	_blade_mirror.mirror_add(node)


func _clear_pivot() -> void:
	_ensure_mirror()
	for b in blade_nodes:
		_blade_mirror.mirror_remove(b)
	blade_nodes.clear()
	if source != null:
		_blade_mirror.mirror_remove(source)
	source = null


func _try_select_blade(node: SkillNode) -> bool:
	if blade_nodes.size() >= max_blades():
		return false
	if not _is_neighbor_of_blade_set(node):
		return false
	_ensure_mirror()
	_blade_mirror.mirror_add(node)
	blade_nodes.append(node)
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


func resolve() -> AttackOutcome:
	var outcome := AttackOutcome.new()
	if not is_valid():
		return outcome
	var blade_state := build_blade_state()
	if blade_state == null:
		return outcome
	var drivers := _build_drivers(blade_state)
	var trajectory := BladeSim.simulate(blade_state, drivers, SWING_DURATION)
	var space_state := source.get_world_2d().direct_space_state
	var exclude := collect_target_excludes()
	var events := BladeHitScan.scan(
			trajectory, blade_state, space_state, 0xFFFFFFFF, exclude)
	# #170: defensive spikes pop the attacker's own vertices (and disintegrate
	# whatever they sever from the handle). Gate hits by the same resolution the
	# live swing uses so AI scoring / AP estimation matches what actually lands.
	var pops := BladePopResolver.resolve(events, blade_state, attacker)
	for ev in events:
		# D-1 MVP: edges are inert. Skip them so preview/AP estimation matches
		# the live swing's per-event behaviour in skill_blade.gd.
		if ev.is_edge_hit():
			continue
		if pops.is_dead(ev.particle_idx, ev.t):
			continue  # this vertex was popped / disintegrated by now
		var di := DamageInstance.new()
		di.amount = blade_state.vertex_damage[ev.particle_idx]
		di.type = DamageInstance.Type.PHYSICAL
		di.target = ev.target as SkillNode
		di.origin = source
		di.source = self
		outcome.hits.append(di)
	return outcome


## Build a fresh BladeState from the current selection. Public so the
## MeleePreview controller can share the same construction with resolve().
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


func _build_drivers(blade_state: BladeState) -> Array[BladeDriver]:
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


## RIDs to feed BladeHitScan as the physics-query exclude list — covers
## the blade members themselves (don't hit their own subgraph), plus
## unallocated nodes and nodes owned by the attacker. The scan picks up
## everything else in the world that overlaps the swing.
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
		if self_set.has(sn) or not sn.is_allocated() or sn.owned_by == attacker:
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
