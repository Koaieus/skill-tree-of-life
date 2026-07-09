@tool
class_name AuraEffect
extends Effect

## A buff (or debuff) radiating from the entity's core to nodes around it,
## re-evaluated whenever the world moves under it.
##
## Three orthogonal knobs:
##
## - [member reach] — [i]which[/i] nodes are touched. `null` floods the whole scope.
## - [member metric] — [i]how far[/i] each is, feeding the scale. `null` reuses the
##   distances [member reach] already produced.
## - [member distance_scale] — the multiplier applied to each modifier's `value`
##   at that distance. `null` is flat.
##
## Sign lives on the modifier: negative values make a debuff aura. So the Ninja's
## "−1 armor per hop from core, going negative" is
## `reach: null, metric: HopMetric, distance_scale: ProportionalScale,
## modifiers: [armor ADD_BONUS -1]`. The Serpent is two of these side by side, one
## per metric — which is why `Array[Effect]` needs no `CompositeEffect`.
##
## [b]Stateless.[/b] This resource may be shared by every entity of a class, so it
## keeps no buffed-set dict. The applied handles live in the per-grant
## [EffectInstance] ledger, and a recompute reads them back from there. A `_buffed`
## member here would have every Ninja silently clobbering every other Ninja's aura.

enum Scope {
	OWNED,   ## Measure over the entity's own subgraph (EntityNavigator).
	GLOBAL,  ## Measure over the whole graph — reaches unowned / enemy nodes.
}

## Which nodes the aura touches. `null` = every node in [member scope]. Prefer
## null over a sentinel-large bound when pairing with [ProportionalScale]: a
## bound that "should never bind" is a trap the moment a map outgrows it.
@export var reach: RangeFinder = null
## How distance is measured for [member distance_scale]. `null` reuses whatever
## [member reach] reported. Set it when the two disagree — the Serpent selects
## topologically but scales spatially.
@export var metric: DistanceMetric = null
## `null` = flat (full strength everywhere in reach).
@export var distance_scale: DistanceScale = null
@export var scope: Scope = Scope.OWNED


## Initial population happens here, not on the first `_on_core_moved`. The core's
## opening placement — spawn, or scene-export deserialization — never passes
## through `move_core`, so an event-only aura would sit empty until the entity
## first moved. This is the ordering that broke the previous attempt at #39.
func _on_granted(ctx: EffectContext) -> void:
	recompute(ctx)


func _on_node_allocated(ctx: EffectContext, _node: SkillNode, _forced: bool) -> void:
	recompute(ctx)


func _on_node_deallocated(ctx: EffectContext, _node: SkillNode, _forced: bool) -> void:
	recompute(ctx)


func _on_core_moved(ctx: EffectContext, _from: SkillNode, _to: SkillNode) -> void:
	recompute(ctx)


## Drop every applied modifier and re-derive from the current world.
##
## Full rebuild rather than an incremental diff: an owned subgraph is tens of
## nodes, `revoke_all` also purges rows whose node was freed by a cascade, and a
## rebuild can't drift out of sync with the buffed set the way a diff can. It runs
## on allocation events, never per frame.
func recompute(ctx: EffectContext) -> void:
	ctx.revoke_all()
	if modifiers.is_empty():
		return
	var source := ctx.core_location
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
		for m in modifiers:
			if m != null:
				ctx.grant_scaled(m, s, node)


func get_description() -> String:
	if not description.is_empty():
		return description
	var body := describe_modifiers(modifiers)
	if reach == null:
		return "%s to every node in your constellation" % body
	return body


func _mirror(ctx: EffectContext) -> GraphMirror:
	if scope == Scope.GLOBAL:
		var g := ctx.graph
		return g.navigator if g != null else null
	return ctx.navigator


## Reach selects the set; metric measures it. When they disagree, the metric wins
## for the values and reach only decides membership.
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


## Domain for the normalizing scales. The reach bound when there is one, else the
## widest distance actually observed.
func _bound(dists: Dictionary[SkillNode, float]) -> float:
	if reach != null and metric == null:
		var r := reach.max_reach()
		if r > 0.0:
			return r
	return DistanceMetric.max_of(dists)
