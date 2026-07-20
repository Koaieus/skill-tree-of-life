@tool
class_name TagAuraEffect
extends Effect

## [AuraEffect]'s sibling on the tag channel: radiates a status [member tag]
## (not a numeric modifier) over the same reach/metric/distance_scale knobs,
## granted through [method EffectContext.grant_tag] instead of `grant`. See
## docs/design/status-tags.md.
##
## Same origin rule as [AuraEffect]: the source is [member EffectContext.source_node]
## (a node-carried tag aura radiates from its own node) falling back to
## [member EffectContext.core_location] for an entity-wide one.
##
## [member distance_scale] gates membership here rather than magnitude — a tag
## is granted/not granted, so a zero scale at a given distance excludes the
## node (mirrors how [ShellScale] carves a ring for [AuraEffect]); any nonzero
## scale grants it at full strength.
##
## [b]Stateless[/b], same reason as [AuraEffect]: this resource may be shared
## across every entity of a class, so it keeps no buffed-set dict — a recompute
## always starts from `ctx.revoke_all()`.

## The tag this aura grants. Empty means "not configured" — recompute no-ops.
@export var tag: StringName = &""
## Which nodes the aura touches. `null` = every node in [member scope].
@export var reach: RangeFinder = null
## How distance is measured for [member distance_scale]. `null` reuses whatever
## [member reach] reported.
@export var metric: DistanceMetric = null
## `null` = every selected node gets the tag, unconditionally.
@export var distance_scale: DistanceScale = null
@export var scope: AuraEffect.Scope = AuraEffect.Scope.OWNED


func _on_granted(ctx: EffectContext) -> void:
	recompute(ctx)


func _on_node_allocated(ctx: EffectContext, _node: SkillNode, _forced: bool) -> void:
	recompute(ctx)


func _on_node_deallocated(ctx: EffectContext, _node: SkillNode, _forced: bool) -> void:
	recompute(ctx)


func _on_core_moved(ctx: EffectContext, _from: SkillNode, _to: SkillNode) -> void:
	recompute(ctx)


## Drop every granted tag and re-derive from the current world — a full
## rebuild, not an incremental diff, for the same reasons as [method AuraEffect.recompute].
func recompute(ctx: EffectContext) -> void:
	ctx.revoke_all()
	if tag == &"":
		return
	# Origin rule: a node-carried tag aura radiates from its own node; an
	# entity-wide one falls back to the core. See docs/design/status-tags.md.
	var source := ctx.source_node if ctx.source_node != null else ctx.core_location
	var mirror := _mirror(ctx)
	if source == null or mirror == null:
		return

	var dists := _distances(source, mirror)
	var bound := _bound(dists)
	for node in dists:
		if not is_instance_valid(node):
			continue
		var s: float = 1.0 if distance_scale == null else distance_scale.scale(dists[node], bound)
		if is_zero_approx(s):
			continue
		ctx.grant_tag(tag, node)


func get_description() -> String:
	if not description.is_empty():
		return description
	var label := String(tag)
	if reach == null:
		return "Grants %s to every node in your constellation" % label
	return "Grants %s in reach" % label


func _mirror(ctx: EffectContext) -> GraphMirror:
	if scope == AuraEffect.Scope.GLOBAL:
		var g := ctx.graph
		return g.navigator if g != null else null
	return ctx.navigator


## Reach selects the set; metric measures it. Mirrors [method AuraEffect._distances].
func _distances(source: SkillNode, mirror: GraphMirror) -> Dictionary[SkillNode, float]:
	var selected: Dictionary[SkillNode, float] = {}
	if reach != null:
		selected = reach.gather(source, mirror)
	else:
		for n in mirror.get_mirrored_nodes():
			selected[n] = 0.0
	if metric == null:
		return selected
	var nodes: Array[SkillNode] = []
	for n in selected:
		nodes.append(n)
	return metric.distances(source, nodes, mirror)


## Domain for the normalizing scales. Mirrors [method AuraEffect._bound].
func _bound(dists: Dictionary[SkillNode, float]) -> float:
	if reach != null and metric == null:
		var r := reach.max_reach()
		if r > 0.0:
			return r
	return DistanceMetric.max_of(dists)
