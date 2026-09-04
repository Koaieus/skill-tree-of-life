class_name MagicAttackPlan
extends AttackPlan

## [b]Pick the spell first, then click a target (#728).[/b] The equipped spell's
## reach is unioned across every owned node that may cast it, so the player
## left-clicks a target directly and the casting source is auto-picked for
## them; right-click clears the pick. There is no source-selection step any
## more — see [member source] for why choosing one was never really a choice,
## and docs/design/click_grammar.md for the grammar this collapsed.
## The active spell comes from
## [BattleSystem.selected_spell] when the plan is constructed by the system;
## hand-instantiated plans (tests, AI scoring) can assign [member spell]
## directly. Falls back to the bundled default if nothing is selected so the
## plan is never silently unarmed.

const _FALLBACK_SPELL: SpellDef = preload("res://attack/spell/defs/spark.tres")

## The cast-from node. No longer clicked — [method _on_node_left_clicked]
## stamps it from [method SpellTargetUnion.source_for] the moment a target is
## picked, and [method validate] still requires it (a cast has to leave from
## somewhere, and the launch command ships its stable id).
##
## Auto-picking is honest rather than lazy: `spell_damage` IS node-local, so
## the union hands back the strongest caster that reaches each target. The
## measured spread (Ninja +40%, Serpent ~flat) sat under the bar the owner set
## for earning a player-facing source affordance, so the choice is made
## silently here; the heatmap that would expose it is filed separately.
var source: SkillNode = null
var spell: SpellDef = null
var target: SkillNode = null

## The viewing seat's fog, for caller-side vision filtering — set by
## [BattleSystem], null on the AI's probe plans (they carry their own recon).
##
## Vision is applied HERE and not inside [SpellTargetUnion] on purpose: under
## [SeatPolicy] couch handover the acting entity is not the viewing seat, so a
## union that baked one viewer's fog in would be wrong for the other caller.
var viewer_vision: VisionSystem = null

## Valid-target set for the current (source, spell) pair, membership-only
## (#385 perf) — a VIEW onto [member _union] rather than its own walk, so there
## is one implementation behind both the pre-source union painting and this
## source-scoped question. It costs one dictionary copy.
##
## [b]Who still asks the source-scoped question, post-#745.[/b] Not the AI any
## more — [method AiController._gather_magic_candidates] reads
## [member SpellTargetUnion.per_source] directly. What remains is the committed
## player pick: once a target is clicked, [member source] is stamped and both
## [method get_node_role] and [method get_range_visual] narrow to that one
## caster's reach, because that is the cast about to happen.
var _cached_valid_targets: Dictionary[SkillNode, bool] = {}
var _target_cache_dirty: bool = true

## The pick-spell-first target union (#728), lazily built.
##
## [b]It gets its OWN dirty flag, deliberately.[/b] [member _target_cache_dirty]
## rides [signal state_changed], which fires on every TARGET mutation — hovering
## from one node to the next. Reusing it here would blow the union away on
## mouse movement, the exact opposite of what it is for. The union depends only
## on (spell, ownership, turn), so [method set_spell] invalidates it and
## [BattleSystem] calls [method invalidate_union] on allocation and turn change.
var _union: SpellTargetUnion = null
var _union_dirty: bool = true

## The candidate the player is currently hovering, distinct from the
## committed [member target] — pushed in by [method PlayerInputController]'s
## hover channel (#679). Drives the aim-time propagation preview below
## whenever no target is committed yet; once [member target] is set the
## preview locks onto it instead (see [method _preview_target]).
var _hover_target: SkillNode = null

## #679 aim-time preview — the predicted [method SpellResolver.resolve] walk
## for the current preview target (see [method _preview_target]), rebuilt
## lazily off [signal state_changed] like [member _cached_valid_targets]
## above. Resolved against a THROWAWAY shadow world ([method SpellResolver.resolve],
## never [method resolve_against]) so a hover can never mutate HP, ownership
## or mana on the real board.
##
## Cost per rebuild (not per repaint — only on a preview-target CHANGE):
## one [method SpellResolver.resolve] walk (bounded by the spell's own hop
## count / visit cap, same cost a real cast pays) plus one O(edges) pass
## building [member _edge_lookup]'s adjacency map so each hop's edge is an
## O(1) lookup rather than an O(edges) scan — O(hops) that way instead of
## O(hops × edges), which matters for Trail Blazer's now-unbounded string walk.
var _preview_dirty: bool = true
var _preview_hit_nodes: Dictionary[SkillNode, bool] = {}
var _preview_edges: Array[Edge] = []


func _init() -> void:
	mode = BattleSystem.AttackMode.MAGIC
	spell = _FALLBACK_SPELL
	state_changed.connect(_invalidate_target_cache)


## Wire form: the base fields plus source/target ids and the spell's
## [member SpellDef.id]. The `_cached_*` target set is a repaint optimisation
## rebuilt on demand from (source, spell) — never wire state.
func to_dict(graph: Graph) -> Dictionary:
	var d := super(graph)
	d["source"] = graph.get_stable_id(source) if graph != null and source != null else 0
	d["target"] = graph.get_stable_id(target) if graph != null and target != null else 0
	d["spell"] = spell.id if spell != null else &""
	return d


static func from_dict(d: Dictionary, graph: Graph) -> MagicAttackPlan:
	var plan := MagicAttackPlan.new()
	plan._read_base(d, graph)
	# Assigned directly, not through set_spell(): that method clears a target
	# the new spell would reject, and rebuilding a plan must reproduce what the
	# authority sent rather than re-adjudicate it. Order still matters — the
	# spell lands before the target so no re-adjudication can run against a
	# stale one.
	plan.spell = SpellCatalog.by_id(StringName(d.get("spell", &"")))
	plan.source = graph.get_by_stable_id(int(d.get("source", 0))) if graph != null else null
	plan.target = graph.get_by_stable_id(int(d.get("target", 0))) if graph != null else null
	return plan


## Right-click clears the pick. Gated on [member target], not [member source]:
## post-#728 a null source IS the resting state (nothing is committed until a
## target is clicked), so the old `source == null` guard would have made
## right-click a permanent no-op.
func pop() -> bool:
	if target == null:
		return false
	reset()
	return true


func _on_node_left_clicked(node: SkillNode) -> void:
	if attacker == null or node == null:
		return
	if spell == null or spell.targeting == null:
		return
	# One click, not two (#728): the clicked node IS the target, and its caster
	# is looked up from the union rather than picked by a prior click. A click
	# on anything the union can't reach is dropped silently — the drawn reach
	# already explains why, exactly as a ranged attack with nothing in range
	# does. The old self-targeting "never mind" fallthrough went with the
	# source step it belonged to.
	var picked := union().source_for(node)
	if picked == null:
		return
	if target == node and source == picked:
		return
	source = picked
	target = node
	state_changed.emit()


func reset() -> void:
	if source == null and target == null:
		return
	source = null
	target = null
	state_changed.emit()


func get_node_role(node: SkillNode) -> HighlightRole:
	if node == null:
		return HighlightRole.NONE
	if source != null and node == source:
		return HighlightRole.ORIGIN
	if target != null and node == target:
		return HighlightRole.HOSTILE_TARGET
	if _preview_hit_set().has(node):
		return HighlightRole.PROPAGATION
	if spell != null and spell.targeting != null and _is_seen(node):
		# Before a source is stamped this paints the UNION — every node any
		# eligible caster can reach. Once one IS stamped the set narrows to
		# that caster's own reach, matching what [method get_range_visual]
		# draws: a committed pick shows the cast about to happen, not every
		# cast that was available a click ago. (Pre-#745 this branch also
		# served [AiController], which probed one owned node at a time; it now
		# enumerates the union itself and never asks a plan for a role.)
		var in_range := _valid_targets().has(node) if source != null \
				else union().can_target(node)
		if in_range:
			return HighlightRole.IN_RANGE
	# LAST, and only while nothing is committed: an owned node can be BOTH an
	# eligible caster and a legal target ([NodeTargeting] documents
	# `healing_beam.tres` as `Any` on purpose), and one node gets one ring — so
	# the target role has to win or a heal loses its click affordance. Once a
	# target IS picked the whole set collapses to the stamped source's gold
	# ORIGIN above, the same narrowing [method get_range_visual] does.
	#
	# Why paint it at all: the union's reach and its targets were both visible
	# after #728, but the CASTERS the reach is measured from were not — so a
	# spell with `min_degree = 2` silently reaches one hop less toward the enemy
	# than an identical-range spell with 1, because the frontier node is a
	# degree-1 leaf of your own territory and cannot cast it. That asymmetry is
	# real and authored; this only makes it legible.
	#
	# No [method _is_seen] gate, unlike the IN_RANGE branch above: an eligible
	# caster is by construction a node [member attacker] OWNS, and an entity
	# cannot be fogged from its own territory. The [SeatPolicy] mismatch
	# [member viewer_vision] warns about does not reach here either — a plan is
	# only ever armed for an entity this machine is playing.
	if source == null and spell != null and union().is_source(node):
		return HighlightRole.CASTER
	return HighlightRole.NONE


## The viewer's fog, applied caller-side (see [member viewer_vision]). No
## vision system bound — the AI's probe plans, tests, the spell playground —
## means no fog, which is the pre-#728 behaviour those callers already had.
##
## Highlights need this explicitly because they are painted by an overlay that
## draws every graph node; click targeting is separately physics-gated by
## [code]input_pickable[/code], so a fogged node cannot be clicked either way.
func _is_seen(node: SkillNode) -> bool:
	return viewer_vision == null or viewer_vision.is_visible(node)


## Push the currently-hovered candidate in from PlayerInputController's hover
## channel. A no-op re-hover (same node, incl. two nulls) skips the
## state_changed emit so mouse jitter over an already-hovered node doesn't
## force a repaint or a preview rebuild.
func set_hover_target(node: SkillNode) -> void:
	if _hover_target == node:
		return
	_hover_target = node
	state_changed.emit()


func validate() -> Array[String]:
	var errors: Array[String] = []
	if spell == null:
		errors.append(&'No Spell selected')
	else:
		errors.append_array(spell.validate(self))
	if source == null:
		errors.append(&'No source selected')
	elif spell != null and attacker != null \
			and not _source_meets_min_degree(spell, source):
		errors.append(&'Source node degree too low for spell')
	if target == null:
		errors.append(&'No target selected')
	return errors


func _source_meets_min_degree(spell_def: SpellDef, src: SkillNode) -> bool:
	if attacker.spellbook != null:
		return attacker.spellbook.is_castable(spell_def, src, attacker)
	# No spellbook? Fall back to a direct navigator check — keeps the gate
	# functional for tests / scripted setups that skip the book entirely.
	if attacker.navigator == null:
		return false
	return attacker.navigator.get_degree(src) >= spell_def.min_degree


func get_available_spells() -> Array[SpellDef]:
	return [spell] if spell != null else []


## #728: with no source pre-picked, "reach" is the UNION of every eligible
## caster's reach — a ring per caster for a euclidean spell, the merged BFS
## frontier for a hop spell. Drawing it is what makes an empty target union
## read as ordinary futility ("I can see where I reach, nothing hostile is in
## it") rather than as an unexplained blank, which is why the owner ruled it a
## requirement rather than a nicety and dropped the second denial toast.
##
## Once a target IS committed the visual narrows to the auto-picked caster's
## own reach: that is the cast about to happen, and showing the whole union
## alongside it would be noise. Both paths read [member SpellTargetUnion.per_source]
## — the sets the target union was already built from — so neither re-traverses.
func get_range_visual() -> RangeVisual:
	var visual: RangeVisual = null
	if spell != null and spell.targeting != null:
		var finder: RangeFinder = spell.targeting.range_finder
		if finder != null:
			if source != null:
				visual = finder.get_visual(attacker, source)
			else:
				visual = finder.get_union_visual(attacker, union())
	# #679: fold the aim-time propagation preview's traversed edges in on top
	# of the spell's own reach visual — same [RangeVisual], PROPAGATION-tagged
	# entries, so [EdgeHighlightOverlay] paints both with no overlay change.
	var preview_edges := _preview_edge_list()
	if not preview_edges.is_empty():
		if visual == null:
			visual = RangeVisual.new()
		for e in preview_edges:
			visual.edges.append(RangeVisual.EdgeEntry.new(e, 0, 0, HighlightRole.PROPAGATION))
	return visual


## Membership view onto the current (source, spell) valid-target set, rebuilt
## on first access after invalidation (#385). See [member _cached_valid_targets].
func _valid_targets() -> Dictionary[SkillNode, bool]:
	if _target_cache_dirty:
		_rebuild_target_cache()
	return _cached_valid_targets


func _invalidate_target_cache() -> void:
	_target_cache_dirty = true
	_preview_dirty = true


## The lazily-built [SpellTargetUnion] for the equipped spell (#728). Never
## null — an unarmed or unownable plan gets an empty union, so callers ask it
## questions rather than null-checking it.
func union() -> SpellTargetUnion:
	if _union_dirty or _union == null:
		_rebuild_union()
	return _union


## Drop the cached union. Called by [BattleSystem] on allocation and turn
## change — the two things that move the eligible-source set without touching
## plan state — and by [method set_spell]. NOT wired to [signal state_changed]:
## see [member _union].
func invalidate_union() -> void:
	_union_dirty = true
	_target_cache_dirty = true
	_preview_dirty = true


func _rebuild_union() -> void:
	_union_dirty = false
	# The attacker's own EntityNavigator mirrors the OWNED subgraph but knows the
	# whole Graph it mirrors — which is what the union needs, and the only handle
	# available before a source is picked (`_graph_of` walks up from a node).
	var graph: Graph = attacker.navigator.graph if attacker != null and attacker.navigator != null else null
	_union = SpellTargetUnion.build(spell, attacker, graph, self)


## A LOOKUP into [member _union], not a second walk (#728). The union already
## holds every eligible caster's legal-target set, keyed by source, and it built
## them the cheap way — candidates from the range finder first, then the
## ownership predicate over only those, never one whole-graph
## [code]_filter_skill_nodes[/code] sweep per source. So the source-scoped view
## costs one dictionary copy and shares the union's cache.
##
## (#385's soundness argument still underwrites the union itself: [AStarSkillTree]
## flat-costs every edge, so `gather`'s hop count and `in_range`'s AStar-path
## length agree exactly.)
func _rebuild_target_cache() -> void:
	_target_cache_dirty = false
	_cached_valid_targets = {}
	if source == null:
		return
	# Through union(), not around it: reading _union_dirty directly meant an
	# allocation with a target already committed left the flag set, so every
	# repaint rebuilt a throwaway single-source union and the eligible-source
	# set never refreshed.
	if union().per_source.has(source):
		_cached_valid_targets = union().targets_from(source)
		return
	# A source that is stamped but absent from the union. Post-#745 the
	# gameplay path that produced one every probe is gone (the AI enumerates
	# the union itself), and what is left is an INELIGIBLE stamped source: the
	# caster dropped below the spell's min_degree between the click and this
	# repaint (a forced dealloc shaving its degree), or a test / scripted setup
	# assigned one directly. Answering for that one source rather than
	# returning empty keeps the narrowed highlight coherent for the frame
	# before the pick is re-adjudicated. Same code, and exactly the cost the
	# pre-#728 single-source gather paid.
	#
	# TODO: remove if the eligibility race turns out to be unreachable. #745
	# took away the one caller that hit this every frame, and no production
	# path now stamps a source the union would not list — what is left is the
	# race above plus tests that assign `source` directly. To settle it, make
	# this branch push_error() and play a run: if it never fires, this branch
	# goes AND [method SpellTargetUnion.build_for] stops needing to be a
	# separate entry point (its only other caller is [method
	# SpellTargetUnion.build], which would absorb it).
	var single: Array[SkillNode] = [source]
	_cached_valid_targets = SpellTargetUnion.build_for(
			spell, attacker, _graph_of(source), single, self).targets_from(source)


## The node the aim-time preview should resolve against right now: the
## COMMITTED [member target] once one is picked, else the live-hovered
## candidate (#679) -- but only while it's an actual valid target, so
## hovering scenery or an out-of-range node previews nothing.
func _preview_target() -> SkillNode:
	if target != null:
		return target
	if _hover_target == null:
		return null
	# The UNION, not the source-scoped set: while aiming, no source is stamped
	# yet, so the source-scoped set is empty and every hover would preview
	# nothing.
	if not union().can_target(_hover_target):
		return null
	return _hover_target


## Lazily (re)built #679 preview node set -- see [member _preview_dirty].
func _preview_hit_set() -> Dictionary[SkillNode, bool]:
	if _preview_dirty:
		_rebuild_preview()
	return _preview_hit_nodes


## Lazily (re)built #679 preview edge list -- see [member _preview_dirty].
func _preview_edge_list() -> Array[Edge]:
	if _preview_dirty:
		_rebuild_preview()
	return _preview_edges


## Runs [method SpellResolver.resolve] -- the shadow-world, side-effect-free
## entry point (#679's owner decision: no second propagation walk) -- against
## [method _preview_target], then reads its [member AttackOutcome.timeline]
## for the nodes the walk landed on and the edges it stepped across. The seed
## landing ([constant PropagationEvent.Verb.JUMP]) has no predecessor edge --
## it lands on the target by casting, not by stepping -- so only EDGE / SELF_LOOP
## events contribute an edge.
func _rebuild_preview() -> void:
	_preview_dirty = false
	_preview_hit_nodes.clear()
	_preview_edges.clear()
	var preview_target := _preview_target()
	if preview_target == null or spell == null or attacker == null:
		return
	# Pre-commit there is no stamped source, so preview against the caster the
	# union WOULD pick — which is the cast the player is about to make. Resolving
	# from some other node would ghost the wrong damage numbers, since
	# `spell_damage` is node-local.
	var caster := source if source != null else union().source_for(preview_target)
	if caster == null:
		return
	var graph := _graph_of(caster)
	if graph == null:
		return
	var outcome := SpellResolver.resolve(spell, preview_target, caster, attacker, graph)
	if outcome.timeline.is_empty():
		return
	var lookup := _edge_lookup(graph)
	for event in outcome.timeline:
		if event.target != null:
			_preview_hit_nodes[event.target] = true
		if event.verb == PropagationEvent.Verb.JUMP or event.predecessor == null:
			continue
		var from_map: Dictionary = lookup.get(event.predecessor, {})
		var edge: Edge = from_map.get(event.target)
		if edge != null:
			_preview_edges.append(edge)


## One O(edges) pass building predecessor->target->Edge lookup, so
## [method _rebuild_preview] resolves each hop's edge in O(1) instead of
## rescanning [method Graph.get_edges] per hop -- O(edges + hops) total
## rather than O(edges * hops), which is what keeps Trail Blazer's now-
## unbounded string walk cheap at the [code]first_level[/code] (800-node) scale.
func _edge_lookup(graph: Graph) -> Dictionary[SkillNode, Dictionary]:
	var lookup: Dictionary[SkillNode, Dictionary] = {}
	for e in graph.get_edges():
		if e == null or e.from == null or e.to == null:
			continue
		_index_edge_pair(lookup, e.from, e.to, e)
		if e.from != e.to:
			_index_edge_pair(lookup, e.to, e.from, e)
	return lookup


func _index_edge_pair(lookup: Dictionary[SkillNode, Dictionary], a: SkillNode, b: SkillNode, e: Edge) -> void:
	if not lookup.has(a):
		lookup[a] = {}
	(lookup[a] as Dictionary)[b] = e


## SkillNodes live under Graph/SkillNodes; walk parents to find it.
func _graph_of(node: SkillNode) -> Graph:
	var n: Node = node
	while n != null and not (n is Graph):
		n = n.get_parent()
	return n as Graph


func resolve_against(world: CombatWorld) -> AttackOutcome:
	if spell == null or source == null or target == null:
		return AttackOutcome.new()
	var graph := _graph_of(source)
	if graph == null:
		return AttackOutcome.new()
	# Before this, the live cast path resolved with rng == null and
	# PropagationContext randomize()d its crit stream — a real cast was not
	# reproducible even on one machine.
	#
	# Magic is the only mode that arms an RNG TODAY, which is a gap in the
	# other two rather than a property of magic: melee and ranged are meant
	# to roll `crit_chance` the same way and currently do not roll at all
	# (crit is implemented solely in SpellResolver). Magic's own deviation is
	# only the EXTRA guaranteed-crit path — SpellDef.crit_conditions, e.g.
	# Leafblower critting on a degree-1 leaf — layered on top of the same
	# universal stat roll.
	#
	# When crits reach melee and ranged they must draw from `seeded_rng()`
	# like this, NOT from the global RNG, or they reintroduce the exact hole
	# this line closes. See AttackPlan.resolve_seed.
	var outcome := SpellResolver.resolve_against(
		spell, target, source, attacker, graph, world, seeded_rng())
	outcome.mana_cost = spell.mana_cost
	outcome.resolve_seed = resolve_seed
	return outcome


## Swap the equipped spell mid-plan. Post-#728 the pick is re-adjudicated
## against the NEW spell's union rather than against the old spell's source:
## a target the new spell can still reach keeps its place and gets re-stamped
## with whichever caster is best for it now (which is rarely the same node),
## and a target it can't reach clears both fields. Anything else would leave a
## source the new spell may not even be castable from.
func set_spell(new_spell: SpellDef) -> void:
	if spell == new_spell:
		return
	spell = new_spell
	invalidate_union()
	if target != null:
		var picked := union().source_for(target)
		if picked == null:
			source = null
			target = null
		else:
			source = picked
	state_changed.emit()
