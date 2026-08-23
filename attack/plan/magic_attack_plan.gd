class_name MagicAttackPlan
extends AttackPlan

## Left-click an owned node to set the casting source (when unset), then
## left-click a valid target per the equipped spell's targeting. Right-click
## pops the source (and target with it) back to "no source yet" — see
## docs/design/click_grammar.md. The active spell comes from
## [BattleSystem.selected_spell] when the plan is constructed by the system;
## hand-instantiated plans (tests, AI scoring) can assign [member spell]
## directly. Falls back to the bundled default if nothing is selected so the
## plan is never silently unarmed.

const _FALLBACK_SPELL: SpellDef = preload("res://attack/spell/defs/spark.tres")

var source: SkillNode = null
var spell: SpellDef = null
var target: SkillNode = null

## Valid-target set for the current (source, spell) pair, membership-only
## (#385 perf). Rebuilt lazily off ONE [method RangeFinder.gather] traversal
## instead of the overlay re-deriving it with one [method Targeting.is_valid_target]
## — and thus one AStar query on [HopRangeFinder] — PER NODE PER REPAINT.
## Invalidated by [signal state_changed], which every source/spell/target
## mutation below already emits.
var _cached_valid_targets: Dictionary[SkillNode, bool] = {}
var _target_cache_dirty: bool = true


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
	# spell lands before the target so `_target_still_valid` is never consulted
	# against a stale one.
	plan.spell = SpellCatalog.by_id(StringName(d.get("spell", &"")))
	plan.source = graph.get_by_stable_id(int(d.get("source", 0))) if graph != null else null
	plan.target = graph.get_by_stable_id(int(d.get("target", 0))) if graph != null else null
	return plan


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
		source = node
		state_changed.emit()
		return
	if spell == null or spell.targeting == null:
		return
	if not spell.targeting.is_valid_target(self, source, node):
		# Self-targeting fallthrough: if the source itself isn't a legal
		# target for this spell (most attack spells), that's "never mind",
		# not a denial — pop instead of silently dropping the click. A heal
		# spell that allows self-targeting resolves normally above, no
		# special case needed. See docs/design/click_grammar.md.
		if node == source:
			pop()
		return
	if target == node:
		return
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
	if source != null and spell != null and spell.targeting != null:
		if _valid_targets().has(node):
			return HighlightRole.IN_RANGE
	return HighlightRole.NONE


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


func get_range_visual() -> RangeVisual:
	if source == null or spell == null or spell.targeting == null:
		return null
	var finder: RangeFinder = spell.targeting.range_finder
	if finder == null:
		return null
	return finder.get_visual(attacker, source)


func _target_still_valid() -> bool:
	if spell == null or spell.targeting == null or source == null:
		return false
	return spell.targeting.is_valid_target(self, source, target)


## Membership view onto the current (source, spell) valid-target set, rebuilt
## on first access after invalidation (#385). See [member _cached_valid_targets].
func _valid_targets() -> Dictionary[SkillNode, bool]:
	if _target_cache_dirty:
		_rebuild_target_cache()
	return _cached_valid_targets


func _invalidate_target_cache() -> void:
	_target_cache_dirty = true


## ONE traversal ([method RangeFinder.gather], BFS/linear-scan) over the global
## mirror, then a cheap per-candidate ownership-bit test — not one
## [method Targeting.is_valid_target] (and thus one AStar query on
## [HopRangeFinder]) per candidate. Sound ONLY because [AStarSkillTree] flat-costs
## every edge (see range_finder.gd's `gather` docstring) so `gather`'s hop count
## and `in_range`'s AStar-path length agree exactly — verified when #385 was
## filed, not re-derived here. A non-[NodeTargeting] targeting (none shipped
## today) falls back to the O(N) [method Targeting.valid_targets] walk.
func _rebuild_target_cache() -> void:
	_cached_valid_targets.clear()
	_target_cache_dirty = false
	if source == null or spell == null or spell.targeting == null:
		return
	var targeting := spell.targeting
	if not (targeting is NodeTargeting):
		for sn in targeting.valid_targets(self, source):
			_cached_valid_targets[sn] = true
		return
	var nt := targeting as NodeTargeting
	var finder: RangeFinder = nt.range_finder
	if finder == null:
		# Unlimited reach: every graph node is a range candidate.
		var full_graph := _graph_of(source)
		if full_graph == null:
			return
		for sn in full_graph.get_skill_nodes():
			if sn.ownership_bit(attacker) & nt.ownership_filter != 0:
				_cached_valid_targets[sn] = true
		return
	# Global reach (matches HopRangeFinder.in_range / EuclideanRangeFinder.in_range,
	# neither of which are scoped to owned territory) — the full-graph Navigator
	# mirror, not attacker.navigator (that's the owned-subgraph EntityNavigator).
	var graph := _graph_of(source)
	if graph == null or graph.navigator == null:
		return
	for candidate in finder.gather(source, graph.navigator, attacker):
		if candidate.ownership_bit(attacker) & nt.ownership_filter != 0:
			_cached_valid_targets[candidate] = true


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


## Swap the equipped spell mid-plan. Clears the target if the new spell's
## targeting would reject it, so the player can't accidentally cast with a
## stale pick. Emits [signal state_changed] so the UI re-paints.
func set_spell(new_spell: SpellDef) -> void:
	if spell == new_spell:
		return
	spell = new_spell
	if target != null and not _target_still_valid():
		target = null
	state_changed.emit()
