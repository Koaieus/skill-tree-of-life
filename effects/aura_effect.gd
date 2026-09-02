@tool
class_name AuraEffect
extends Effect

## A buff (or debuff) radiating from a source node to nodes around it,
## re-evaluated whenever the world moves under it. The source is the carrier
## node for a node-granted aura (keystone/addon), falling back to the entity's
## core for an entity-wide one (core class) — see [method recompute]'s origin rule.
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


## Allocation/deallocation route through [method _topology_changed] rather
## than a blind [method recompute] — that's the #626 fix. A core move still
## goes straight to a full [method recompute]: for an entity-wide aura the
## SOURCE itself just changed (old core's cache entry is simply orphaned, a new
## one populated at the new source), and that's rare enough not to need its own
## fast path.
func _on_node_allocated(ctx: EffectContext, node: SkillNode, _forced: bool) -> void:
	_topology_changed(ctx, node)


func _on_node_deallocated(ctx: EffectContext, node: SkillNode, _forced: bool) -> void:
	_topology_changed(ctx, node)


func _on_core_moved(ctx: EffectContext, _from: SkillNode, _to: SkillNode) -> void:
	recompute(ctx)


## Drop every applied modifier and re-derive from the current world.
##
## Full rebuild rather than an incremental diff: an owned subgraph is tens of
## nodes, `revoke_all` also purges rows whose node was freed by a cascade, and a
## rebuild can't drift out of sync with the buffed set the way a diff can. It runs
## on allocation events, never per frame.
##
## [b]Batched per node board (#627).[/b] A rebuild revokes the OLD grant on a
## node then re-grants the NEW one — the same stat written twice — and
## unbatched that is two immediate [signal Stat.value_changed] emissions where
## one would do. [method _open_batch] / [method _close_batches] bracket every
## board this call touches (old targets AND new — a batch opened before
## [method EffectContext.revoke_all] below covers the revoke half too) so each
## stat that actually moved settles once. Values are unaffected:
## [method Stat.get_value] recomputes from bins per call, so batching defers
## notification only, never value.
##
## [b]Widened to the whole dispatch (#647).[/b] When a hook dispatch is running,
## [method EffectContext.hold_batch] takes each board over for its duration, so
## the entity's two auras collapse into ONE settle per stat instead of one each.
## Outside a dispatch (`_on_granted`, a direct call) this is unchanged #627
## behaviour: the local `batched` list is opened and closed here.
func recompute(ctx: EffectContext) -> void:
	var batched: Array[StatBoard] = []
	var seen: Dictionary[StatBoard, bool] = {}
	# Old targets first: their boards must already be batching before
	# `revoke_all` touches them, or the revoke's own emission escapes the batch.
	for node in ctx.instance.node_targets():
		_open_batch(ctx, node, batched, seen)
	ctx.revoke_all()
	if modifiers.is_empty():
		_close_batches(batched)
		return
	# Origin rule: a node-carried aura (keystone/addon) radiates from its own
	# node; an entity-wide aura (core class) falls back to the core. No new
	# knob — resolved once here, see docs/design/status-tags.md.
	var source := ctx.source_node if ctx.source_node != null else ctx.core_location
	var mirror := _mirror(ctx)
	if source == null or mirror == null:
		_close_batches(batched)
		return

	var dists := _distances(source, mirror)
	var bound := _bound(dists)
	for node in dists:
		if not is_instance_valid(node):
			continue
		var s: float = 1.0 if distance_scale == null else distance_scale.scale(dists[node], bound)
		if is_zero_approx(s):
			continue
		_open_batch(ctx, node, batched, seen)
		for m in modifiers:
			if m != null:
				ctx.grant_scaled(m, s, node)
	_close_batches(batched)


## Opens (once) the batch on [param node]'s board and records it in [param
## batched] / [param seen], so [method _close_batches] closes every board this
## [method recompute] call touched. A no-op if the board hasn't materialized
## yet (nothing to batch — the caller's own grant/revoke lazily creates and
## touches it unbatched, same as before this issue) or is already open.
func _open_batch(ctx: EffectContext, node: SkillNode, batched: Array[StatBoard], seen: Dictionary[StatBoard, bool]) -> void:
	var board := ctx.board_for(node)
	if board == null or seen.has(board):
		return
	seen[board] = true
	# #647: inside a hook dispatch the ENTITY holds the batch open for the whole
	# dispatch, so the second aura's recompute joins the first's batch instead of
	# settling the same stat again. It closes it too — this call must not record
	# the board in `batched`, or [method _close_batches] would close it early and
	# leave the ledger's own drain unmatched.
	if ctx.hold_batch(board):
		return
	batched.append(board)
	board.begin_batch()


## The guaranteed close for every board [method _open_batch] opened this
## [method recompute] call. Called from EVERY exit path above, including the
## early returns, so an unmatched `begin_batch` never lingers —
## [method StatBoard.begin_batch]'s own docstring: an unmatched call "silently
## swallows every subsequent notification on this board", forever.
func _close_batches(batched: Array[StatBoard]) -> void:
	for b in batched:
		b.end_batch()


## The alloc/dealloc entry point (#626). `metric == null` keeps the OLD,
## unconditional full-rebuild behaviour untouched — that path (reach's own raw
## distances, no [DistanceMetric] involved) is outside this issue's file list.
## With a metric set, three branches, cheapest first:
##
## 1. [param changed_node] can't be in reach at all → no-op (acceptance 5).
## 2. A [method DistanceScale.uses_bound] scale normalizes by the widest
##    distance in the set, so even a metric that says "nothing else moved" can
##    still shift everyone's SCALE when membership changes the bound.
##    Correctness over cleverness here: fall back to a full [method recompute]
##    rather than trying to detect whether the bound actually moved
##    (acceptance 1b).
## 3. Otherwise, delegate to whichever of [method _apply_hop_diff] /
##    [method _apply_membership_update] matches
##    [method DistanceMetric.dirties_on_membership_change].
func _topology_changed(ctx: EffectContext, changed_node: SkillNode) -> void:
	if modifiers.is_empty():
		return
	if not is_instance_valid(changed_node):
		return
	var source := ctx.source_node if ctx.source_node != null else ctx.core_location
	var mirror := _mirror(ctx)
	if source == null or mirror == null:
		return
	if metric == null:
		recompute(ctx)
		return
	if not _reach_could_include(changed_node, source, mirror):
		return
	if distance_scale != null and distance_scale.uses_bound():
		recompute(ctx)
		return
	if metric.dirties_on_membership_change():
		_apply_hop_diff(ctx, source, mirror)
	else:
		_apply_membership_update(ctx, source, mirror, changed_node)


## Cheap pre-test (acceptance 5): can [param node] possibly matter to this
## aura at all? `null` [member reach] floods the whole scope, so anything
## already the graph's problem to have mirrored is in play — no filtering to
## do (the downstream membership/diff logic is what actually excludes an
## unreachable node either way; this is purely a short-circuit).
##
## Only [EuclideanRangeFinder] gets a real O(1) short-circuit here, via
## [method RangeFinder.in_range] with a null attacker (unscaled, matching
## [method _distances]'s own [code]reach.gather(source, mirror)[/code] call —
## auras never inherit a caster's `spell_range`). [HopRangeFinder.in_range] is
## NOT safe to call the same way: it hardwires the GLOBAL navigator rather
## than whatever mirror an owned-scope aura measures over, AND early-returns
## false whenever `attacker == null` — so `in_range(null, ...)` would silently
## reject every node, always. There is no cheap single-candidate hop query
## against an arbitrary mirror to fall back to (`.claude/rules/graph.md`'s
## `gather()`-not-`in_range()`-in-a-loop rule is about the reverse shape, but
## the underlying reason — `in_range` isn't mirror-generic — is the same one
## that bites here), so a bounded hop reach skips the short-circuit and lets
## the downstream membership/diff logic do the filtering instead.
func _reach_could_include(node: SkillNode, source: SkillNode, mirror: GraphMirror) -> bool:
	if reach == null or not reach is EuclideanRangeFinder:
		return true
	return reach.in_range(null, source, node)


## The Euclidean-shaped path: [param changed_node] is the only thing that could
## possibly need touching, because [method DistanceMetric.dirties_on_membership_change]
## being false is a promise that no OTHER node's distance moved. One O(1)-ish
## metric read, one grant or revoke — every other already-applied node's
## handle is left exactly as it was (acceptance 1).
func _apply_membership_update(ctx: EffectContext, source: SkillNode, mirror: GraphMirror, changed_node: SkillNode) -> void:
	for h in ctx.handles_for(changed_node):
		ctx.revoke(h)
	if not is_instance_valid(changed_node):
		return
	var still_selected: bool
	if reach == null:
		still_selected = mirror.vertex_id(changed_node) >= 0
	else:
		# O(N) gather, not a hand-rolled single-node owned-mirror query:
		# RangeFinder exposes no such primitive, and it isn't ours to add one
		# to. Only paid by a bounded `reach` — Serpent/Ninja (reach == null)
		# never do (#626 report).
		still_selected = reach.gather(source, mirror).has(changed_node)
	if not still_selected:
		return
	var one := metric.distances(source, [changed_node], mirror)
	if not one.has(changed_node):
		return
	# Bound-independent by construction (only reached when
	# [method DistanceScale.uses_bound] said no) — the scale ignores whatever we
	# pass here, so -1.0 is safe.
	var s: float = 1.0 if distance_scale == null else distance_scale.scale(one[changed_node], -1.0)
	if is_zero_approx(s):
		return
	for m in modifiers:
		if m != null:
			ctx.grant_scaled(m, s, changed_node)


## The hop-shaped path: pull the shared, generation-cached raw map (walked at
## most once for every hop-metric aura sharing this [param source] this
## topology change — [AuraDistanceCache], acceptance 3), diff it against what
## was cached a moment ago, and touch only what moved.
##
## "Touched" is the union of what this aura currently has granted
## ([method EffectInstance.node_targets], not the cache — a bounded [member
## reach] means the cache's full map is a superset) and what the fresh walk
## says is in range now. Absent from the new map = revoked, not skipped
## (acceptance 6) — [HopMetric] already drops unreachable nodes from its
## result, so "missing" and "unreachable" are the same thing here.
func _apply_hop_diff(ctx: EffectContext, source: SkillNode, mirror: GraphMirror) -> void:
	var old_granted := ctx.instance.node_targets()
	var old_raw := AuraDistanceCache.peek(mirror, source)
	var new_dists := _distances(source, mirror)
	var touched: Dictionary[SkillNode, bool] = {}
	for node in old_granted:
		touched[node] = true
	for node in new_dists:
		touched[node] = true
	var bound := _bound(new_dists)
	for node in touched:
		if not is_instance_valid(node):
			continue
		var now_in := new_dists.has(node)
		var was_granted: bool = old_granted.has(node)
		if was_granted and now_in and old_raw.has(node) and is_equal_approx(float(old_raw[node]), new_dists[node]):
			continue  # unchanged: leave the existing handle alone
		if was_granted:
			for h in ctx.handles_for(node):
				ctx.revoke(h)
		if not now_in:
			continue
		var s: float = 1.0 if distance_scale == null else distance_scale.scale(new_dists[node], bound)
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
