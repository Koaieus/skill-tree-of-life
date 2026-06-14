class_name MeleeAttackPlan
extends AttackPlan

## A melee attack as an induced sub-subgraph of the attacker's owned territory:
## one PIVOT (right-clicked) plus up to `blade_size` MEMBERS (left-clicked) that
## must form a connected subgraph through the pivot. Deselecting any member
## cascades — anyone newly disconnected from the pivot drops too — keeping the
## blade well-formed at every step.

const _BLADE_SIZE_ID: StringName = &"blade_size"

## The pivot — right-clicked, owned-by-attacker. Always in the blade mirror.
var source: SkillNode = null

## The selected member nodes (excludes pivot). Each is owned-by-attacker and
## reachable from the pivot through this list + the pivot via graph edges.
var blade_nodes: Array[SkillNode] = []

## Arc / sweep target — kept as Vector2 for now per the original sketch;
## targeting integration comes when previews land.
var blade_target: Vector2

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

func _on_node_right_clicked(node: SkillNode) -> void:
	if attacker == null or node == null or node.owned_by != attacker:
		return
	if node == source:
		_clear_pivot()
	else:
		_set_pivot(node)
	state_changed.emit()


func _on_node_left_clicked(node: SkillNode) -> void:
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


func get_highlight_role(node: SkillNode) -> HighlightRole:
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


## Current cap on `blade_nodes.size()` — reads `blade_size` from the
## attacker's stat board. Defaults to 1 when the board / stat is missing
## (e.g. a stat-less test entity).
func max_blades() -> int:
	if attacker == null or attacker.stat_board == null:
		return 1
	var s := attacker.stat_board.get_stat(_BLADE_SIZE_ID)
	if s == null:
		return 1
	return int(s.value)


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
