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
	seed_state.damage = impact_damage(spell, source)
	seed_state.seed_damage = seed_state.damage
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
		# After the reducer runs (or short-circuits), stamp the convergence count
		# onto the resolved state so the crit condition reading
		# `state.incident_count` sees the right number regardless of which path
		# was taken (real reducer returning a fresh merged CastSpell would
		# otherwise default to 1; the null "first-wins" short-circuit returns
		# incidents[0] raw). See #352.
		var merged: Array[CastSpell] = []
		for node in groups:
			var incidents: Array[CastSpell] = []
			for inc in (groups[node] as Array):
				incidents.append(inc)
			var resolved: CastSpell = _apply_reducer(config.reducer, incidents, node, ctx)
			if resolved == null:
				_record_cancel(outcome, node, ctx.wave_index, incidents)
				continue
			resolved.incident_count = incidents.size()
			merged.append(resolved)

		# 3. Apply effects, emit a timeline event per landing, bump visit counter.
		for state in merged:
			# `hits`/`heals` produced by this landing's effects belong to this
			# event. Today only DamageEffect and HealingEffect append, each at
			# most once per landing — so the first new entry in either list is
			# the event's damage/heal (null if the landing was zero-damage /
			# utility, which still gets an event so it animates).
			var pre := outcome.hits.size()
			var pre_heals := outcome.heals.size()
			for eff in spell.on_hit_effects:
				if eff != null:
					eff.apply(state, outcome)
			# Parity invariant: the headless path applies ALL of `hits`, but the
			# VFX path applies only the first hit per landing (`ev.damage` below).
			# They agree only while a landing appends ≤1 hit. Trip loudly if a
			# future two-damage effect breaks that — teach the coordinator to
			# apply every hit before shipping it.
			assert(outcome.hits.size() - pre <= 1,
					"landing appended >1 hit; VFX applies only the first")
			var crit_tier: int = 0
			if outcome.hits.size() > pre:
				crit_tier = _resolve_crit(spell, state, outcome.hits[pre], ctx)
			var ev := PropagationEvent.new()
			ev.beat = state.hop_index
			ev.predecessor = state.predecessor
			ev.origin = state.predecessor if state.predecessor != null else state.source
			ev.target = state.current_node
			ev.verb = _verb_for(state)
			ev.crit_tier = crit_tier
			if outcome.hits.size() > pre:
				ev.damage = outcome.hits[pre]
			if outcome.heals.size() > pre_heals:
				ev.heal = outcome.heals[pre_heals]
			outcome.timeline.append(ev)
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


## The impact hit: [code]spell_damage × SpellDef.power[/code] (D-32). **The one
## home for this expression** — UI that shows a spell's damage calls this, it
## does not re-multiply (three copies of it had already drifted apart).
##
## Where the [code]spell_damage[/code] term comes from, in order:
##   1. [param source] — the node the spell is cast FROM — via
##      [method SkillNode.get_local_value], which merges the node board with its
##      [b]owner's[/b] board. Reading the target instead would let the defender
##      buff the spell landing on them; mirrors [RangedDamageFormula]'s
##      [code]firing_node.get_local_value(&"ranged_damage")[/code]. Evaluated
##      ONCE, at cast: a per-hop re-read would compound INT (INT² by hop 2).
##   2. [param board] — the caster's own board, for previews that have no
##      cast-from node yet ([SpellTooltip], [CombatCardMagic]). Misses
##      node-local addons by construction; that's the price of previewing
##      before a source node is picked.
##   3. Neither — the stat's own default (1.0), so the row shows the raw
##      [member SpellDef.power] rather than a zero.
static func impact_damage(spell: SpellDef, source: SkillNode, board: StatBoard = null) -> float:
	if spell == null:
		return 0.0
	if source != null:
		return float(source.get_local_value(&"spell_damage")) * spell.power
	if board != null:
		var stat: Stat = board.get_stat(&"spell_damage")
		if stat != null:
			return float(stat.get_value()) * spell.power
	var def: StatDef = StatRegistry.get_def(&"spell_damage")
	var fallback: float = def.default_value if def != null else 1.0
	return fallback * spell.power


## Evaluates both crit paths for one landing and applies the crit to [param hit]
## when either (or both) fire. Returns [member PropagationEvent.crit_tier]:
## 0 = normal hit, 1 = one path crit, 2 = both paths fired.
## Stat path: rolls [code]crit_chance[/code] from the caster's board.
## Condition path: evaluates every [member SpellDef.crit_conditions] as OR.
static func _resolve_crit(
		spell: SpellDef,
		state: CastSpell,
		hit: DamageInstance,
		ctx: PropagationContext) -> int:
	if hit == null or hit.amount <= 0.0:
		return 0
	var tier: int = 0

	# --- Stat path ---
	var board: StatBoard = ctx.caster.stat_board if ctx.caster != null else null
	if board != null:
		var cc_stat: Stat = board.get_stat(&"crit_chance")
		var cc_val: float = cc_stat.get_value() if cc_stat != null else 0.0
		if cc_val > 0.0:
			# Derived crit RNG — seeded from the cast's RNG without consuming
			# its stream, so the propagation walk reproduces and crits
			# reproduce (#213).
			if ctx.rng_for_crits().randf() < cc_val:
				tier += 1

	# --- Condition path ---
	for cond in spell.crit_conditions:
		if cond != null and cond.evaluate(state, state.current_node, null):
			tier += 1
			# One condition passing is enough to count the condition path;
			# additional conditions don't stack the tier further.
			break

	if tier > 0:
		var cm_val: float = _crit_multiplier(board, 2.0)
		hit.amount *= cm_val
		hit.is_crit = true
		hit.crit_multiplier = cm_val
	return tier


## Reads the [code]crit_multiplier[/code] from the caster's stat board, falling
## back to [param fallback] when the board or stat is missing.
static func _crit_multiplier(board: StatBoard, fallback: float = 2.0) -> float:
	if board == null:
		return fallback
	var cm_stat: Stat = board.get_stat(&"crit_multiplier")
	if cm_stat == null:
		return fallback
	return cm_stat.get_value()


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


## Stamps the movement verb from the landed state — never from geometry (a
## self-loop's origin == target, so positions can't tell them apart).
static func _verb_for(state: CastSpell) -> PropagationEvent.Verb:
	if state.predecessor == null:
		return PropagationEvent.Verb.JUMP           # a — the seed
	if state.current_node == state.predecessor:
		return PropagationEvent.Verb.SELF_LOOP      # e — returned via self-loop
	return PropagationEvent.Verb.EDGE               # b — stepped across an edge


static func _record_cancel(
		outcome: AttackOutcome, node: SkillNode, wave: int,
		incidents: Array[CastSpell]) -> void:
	var rec := SpellCancellation.new()
	rec.node = node
	rec.wave_index = wave
	rec.incident_count = incidents.size()
	outcome.cancellations.append(rec)
	# Fold the fizzle into the timeline as a CANCEL event (damage null) so the
	# coordinator can dissipate on the right beat — `cancellations` above stays
	# as the replay projection.
	var first: CastSpell = incidents[0]
	var cancel_ev := PropagationEvent.new()
	cancel_ev.beat = wave
	cancel_ev.verb = PropagationEvent.Verb.CANCEL
	cancel_ev.predecessor = first.predecessor
	cancel_ev.origin = first.predecessor if first.predecessor != null else first.source
	cancel_ev.target = node
	outcome.timeline.append(cancel_ev)
