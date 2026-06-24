class_name SpellResolver
extends RefCounted

## Pure resolution: produces an [AttackOutcome] for a [SpellDef] seeded at
## [param target] from [param source] (cast-from node) by [param caster],
## using [param graph] for topology queries.
##
## Wave-based BFS: each iteration processes a whole frontier at once so the
## [IncidentReducer] can collapse simultaneous arrivals at the same node
## before any [OnHitEffect] fires. This is what makes self-loops + diamond
## convergence a first-class mechanic (see Resonator).
##
## Side-effect free w.r.t. world state — damage application is deferred to
## the VFX layer (each [DamageInstance] carries .amount; the coordinator
## applies it on projectile arrival). Safe as a preview from AI / tooltip
## code.


static func resolve(
		spell: SpellDef,
		target: SkillNode,
		source: SkillNode,
		caster: Entity,
		graph: Graph,
		rng: RandomNumberGenerator = null) -> AttackOutcome:
	var outcome := AttackOutcome.new()
	if spell == null or spell.propagation == null or target == null or graph == null:
		return outcome
	var config: PropagationConfig = spell.propagation

	var ctx := PropagationContext.new()
	ctx.graph = graph
	ctx.caster = caster
	ctx.seed_node = target
	ctx.rng = rng

	var seed_state := CastSpell.new()
	seed_state.seed_node = target
	seed_state.current_node = target
	seed_state.predecessor = null
	seed_state.source = source
	seed_state.damage = spell.base_damage * config.seed_damage_fraction
	seed_state.hops_remaining = config.max_hops
	seed_state.hop_index = 0
	seed_state.visited = [target]
	seed_state.caster = caster
	seed_state.graph = graph
	seed_state.rng = rng

	var wave: Array[CastSpell] = [seed_state]
	while not wave.is_empty():
		# 1. Group incidents by target node.
		var groups: Dictionary = {}  ## SkillNode -> Array[CastSpell]
		for inc in wave:
			var bucket: Array = groups.get(inc.current_node, [])
			bucket.append(inc)
			groups[inc.current_node] = bucket

		# 2. Reduce per node; CANCEL → telemetry + drop the node entirely.
		var merged: Array[CastSpell] = []
		for node in groups:
			var incidents: Array[CastSpell] = []
			for inc in (groups[node] as Array):
				incidents.append(inc)
			var resolved: CastSpell = _apply_reducer(config.reducer, incidents, node, ctx)
			if resolved == null:
				_record_cancel(outcome, node, ctx.wave_index, incidents.size())
				continue
			merged.append(resolved)

		# 3. Apply effects, bump global visit counter.
		for state in merged:
			for eff in spell.on_hit_effects:
				if eff != null:
					eff.apply(state, outcome)
			ctx.bump_visit(state.current_node)

		# 4. Expand next wave through filter + step.
		var next_wave: Array[CastSpell] = []
		for state in merged:
			if state.hops_remaining <= 0 or config.step == null:
				continue
			var candidates: Array[SkillNode] = []
			for nb in graph.get_neighbours(state.current_node):
				if config.filter == null or config.filter.allows(state.current_node, nb, state, ctx):
					candidates.append(nb)
			# Always enforce max_visits_per_node, even if filter is null —
			# without it, the resolver would loop forever on connected graphs.
			var capped: Array[SkillNode] = []
			for nb in candidates:
				if ctx.visit_count(nb) < config.max_visits_per_node:
					capped.append(nb)
			next_wave.append_array(config.step.step(state.current_node, state, capped, config, ctx))
		ctx.wave_index += 1
		wave = next_wave
	return outcome


## Reducer is optional: null defaults to "first-wins" without instantiating
## a FirstReducer for every spell that doesn't care.
static func _apply_reducer(
		reducer: IncidentReducer,
		incidents: Array[CastSpell],
		node: SkillNode,
		ctx: PropagationContext) -> CastSpell:
	if reducer == null:
		return incidents[0]
	return reducer.reduce(incidents, node, ctx)


static func _record_cancel(outcome: AttackOutcome, node: SkillNode, wave: int, count: int) -> void:
	var rec := SpellCancellation.new()
	rec.node = node
	rec.wave_index = wave
	rec.incident_count = count
	outcome.cancellations.append(rec)
	# Global signal — VFX hooks subscribe once, no need to scan the list.
	# Guard for headless / playground calls where /root/Events may not exist.
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		var tree: SceneTree = ml
		var ev: Node = tree.root.get_node_or_null("/root/Events")
		if ev != null:
			ev.spell_incident_cancelled.emit(rec)
