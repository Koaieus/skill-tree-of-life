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
## [b]This walk MUTATES the world it is handed, and never the real one[/b]
## (#536, closing #498 step 3). Each wave is LANDED — through
## [method OutcomeApplier.land_one], the same landing every other path uses —
## between "reduce incidents" and "expand next wave", so wave N+1's
## [PropagationFilter] selects against a world in which wave N's kills have
## already happened. That is the whole point: the filters that decide where a
## spell goes next ([OwnerFilter], and [ExpressionFilter] via
## `to_owned_by_caster` / `to_unallocated`) read ownership, and a spell used to
## be able to propagate back into a node this same cast had just killed.
##
## Closing it by landing, rather than by a resolve-local "who died" ledger, is
## deliberate: a ledger is a second implementation of death, it cannot see
## [Mitigation] or a forced-dealloc cascade, and a gate that disagrees with the
## real applier is the exact drift docs/domain/attack-timeline.md exists to
## prevent. See #501.
##
## [b]So [param world] must be a shadow, and callers get one by default.[/b]
## Owner call 2026-08-23 — [i]"shadow always"[/i]. [method resolve] mints a
## throwaway [method CombatWorld.shadow] and frees it, which is what the dozen
## preview callers (SpellTooltip, the spell playground, the balance harness, the
## AI's magic candidates) want: they ask what a spell WOULD do and the real
## world is untouched, with no real/preview flag anywhere in the chain. The
## authority's launch path resolves against a shadow too and then replays its
## own record on the live world exactly as a peer does, which is what leaves
## [OutcomeApplier] the sole mutator of the real world — see
## [method BattleSystem.apply_launch_command].
##
## The VFX layer stays a pure observer that replays what already landed (#474) —
## the coordinator does NOT apply damage on projectile arrival, whatever an
## older docstring said.


## [b]The wave interval and the bolt lead-in used to live here as constants,
## and they are gone[/b] (#543 D3).
##
## They were stamped straight into [member HitInstance.arrival_time] below,
## duplicated as `@export`s on [MagicBounceCoordinator], and deliberately not
## wired together — with a documented "retune either and re-check both" tax,
## because a static [method resolve] has no VFX instance to read. Both now live
## once, on [PresentationTempo] ([member PresentationTempo.beat_interval] /
## [member PresentationTempo.beat_lead_in]), and only
## [method OutcomeSchedule.compile] turns them into seconds. This walk records
## the hop ordinal and nothing else.
##
## The lead-in itself survives, and must: magic used to land wave N at
## `N * interval`, i.e. it omitted the bolt's flight, so the mutation clock ran
## a whole flight ahead of the picture. See [member PresentationTempo.beat_lead_in].


## [method resolve_against] on a throwaway shadow — the preview/tooltip/AI
## spelling, and the reason ~40 call sites did not have to learn about worlds.
## Twin of [method AttackPlan.resolve]; see it for why freeing the shadow before
## returning is safe.
static func resolve(
		spell: SpellDef,
		target: SkillNode,
		source: SkillNode,
		caster: Entity,
		graph: Graph,
		rng: RandomNumberGenerator = null) -> AttackOutcome:
	var world := CombatWorld.shadow()
	var outcome := resolve_against(spell, target, source, caster, graph, world, rng)
	world.free_shadow()
	return outcome


static func resolve_against(
		spell: SpellDef,
		target: SkillNode,
		source: SkillNode,
		caster: Entity,
		graph: Graph,
		world: CombatWorld,
		rng: RandomNumberGenerator = null) -> AttackOutcome:
	var outcome := AttackOutcome.new()
	outcome.cadence = ScheduleEntry.Cadence.BEAT
	if spell == null or spell.propagation == null or target == null or graph == null:
		return outcome
	var config: PropagationConfig = spell.propagation

	var ctx := PropagationContext.new()
	ctx.graph = graph
	ctx.caster = caster
	ctx.seed_node = target
	ctx.rng = rng
	# The half of the gating fix the wave loop cannot do on its own: landing a
	# wave changes the world, and this is what makes the next wave's filter
	# READ that world instead of the untouched real nodes.
	ctx.world = world

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

	# Hoisted: ONE crit stream serves the whole cast, consumed wave by wave
	# below. See the decide/land block for why the roll moved out of the old
	# single `decide_all` at the end.
	var crit_rng := ctx.rng_for_crits()
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
		# node -> every predecessor its converging incidents arrived from, in
		# incident order (#542). The reducer folds N incidents into one merged
		# CastSpell with a single CHOSEN predecessor (see
		# IncidentReducer._merge_payload_defaults); this is the only place the
		# full set still exists, so it's captured here and handed to the
		# PropagationEvent this landing emits in step 3 below.
		var predecessor_sets: Dictionary = {}  ## SkillNode -> Array[SkillNode]
		# node -> the damage share each of those arcs was minted with (#704),
		# gathered in the SAME loop off the SAME `incidents` so the two arrays
		# are aligned by construction rather than by a downstream assertion.
		# The share cannot be recovered after the fact: the reducer sums the
		# incidents and the crit multiplies again below.
		var share_sets: Dictionary = {}  ## SkillNode -> PackedFloat32Array
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
			var preds: Array[SkillNode] = []
			var shares := PackedFloat32Array()
			for inc in incidents:
				preds.append(inc.predecessor)
				shares.append(inc.arrival_share)
			predecessor_sets[node] = preds
			share_sets[node] = shares

		# 3. Apply effects, emit a timeline event per landing, bump visit counter.
		var wave_first := outcome.hits.size()
		# state -> the event it emitted, so step 4 can stamp `is_terminal` on
		# the landings the walk actually ENDED at (#543 D6) rather than leaving
		# a VFX reader to re-derive the stopping condition. Identity-keyed: two
		# landings in one wave are distinct CastSpell objects.
		var event_of: Dictionary = {}
		for state in merged:
			# Every `HitInstance` this landing's effects append belongs to this
			# event (#381: was two parallel lists with a ≤1-per-landing parity
			# assert between the headless and VFX paths — dead since #474 made
			# VFX a pure observer of an outcome BattleSystem already applied in
			# full; see the #381 plan). Each new hit rolls its own crit.
			var pre := outcome.hits.size()
			for eff in spell.on_hit_effects:
				if eff != null:
					eff.apply(state, outcome)
			var ev := PropagationEvent.new()
			ev.beat = state.hop_index
			ev.predecessor = state.predecessor
			# Guaranteed present: `merged` and `predecessor_sets` are populated
			# together, keyed by the same node, in the loop above.
			ev.predecessors = predecessor_sets[state.current_node]
			# Same guarantee, same loop: one share per predecessor, in order.
			ev.incident_shares = share_sets[state.current_node]
			ev.turn_sign = state.turn_sign
			ev.origin = state.predecessor if state.predecessor != null else state.source
			ev.target = state.current_node
			ev.verb = _verb_for(state)
			# BEFORE `bump_visit` below, so the nth strike on a node reports
			# n-1: 0, 1, 2 for a Reverberator-shaped cast (#543 D6). The count
			# already existed on the context and was dropped on the floor.
			ev.visit_index = ctx.visit_count(state.current_node)
			for i in range(pre, outcome.hits.size()):
				var hit: HitInstance = outcome.hits[i]
				# The caster is stamped HERE rather than inside each
				# OnHitEffect: every effect that appends a hit needs it (the
				# shared crit roll reads its board), and one place that cannot
				# be forgotten beats N places that can.
				hit.attacker = ctx.caster
				_stamp_crit_conditions(spell, state, hit)
				# Magic's structural parameter is purely ORDINAL — which wave
				# this landing belongs to, nothing more. The compiler turns it
				# into seconds; this walk never names one (#543).
				hit.structural_key = float(state.hop_index)
				ev.hits.append(hit)
			outcome.timeline.append(ev)
			event_of[state] = ev
			ctx.bump_visit(state.current_node)

		# 3b. Settle this wave's crits, then LAND it — before step 4's filter
		# asks the world anything (#536). This is the whole gating fix: a
		# filter reading `ownership_bit` on the next line now sees a node this
		# wave killed as dead.
		#
		# Two passes, not one interleaved pass, so the crit stream is consumed
		# exactly as the old single `CritRoll.decide_all` at the end of the walk
		# consumed it: that call iterated `in_arrival_order`, which for magic is
		# the hop ordinal ascending with an index-stable tiebreak — i.e. wave by
		# wave, append order within a wave, which is exactly this. #543 made
		# that key structural rather than a float, which leaves this identity
		# TRUE BY CONSTRUCTION instead of true by an arithmetic argument about
		# a uniform offset. The draw sequence is bit-identical; only its position
		# relative to the landings moved, and it had to, because
		# `CritRoll.apply` multiplies at land time and cannot multiply by a
		# decision that has not been made yet.
		for i in range(wave_first, outcome.hits.size()):
			CritRoll.decide(outcome.hits[i], crit_rng)
		for i in range(wave_first, outcome.hits.size()):
			OutcomeApplier.land_one(outcome.hits[i], world)

		# 4. Expand next wave through filter + step.
		var next_wave: Array[CastSpell] = []
		for state in merged:
			if state.hops_remaining <= 0 or config.step == null:
				_mark_terminal(event_of, state)
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
			var stepped: Array[CastSpell] = config.step.step(
					state.current_node, state, capped, config, ctx)
			# "Ended by terminal rule" includes a step that CHOSE to stop —
			# TrailBlazerStep sets `hops_remaining = 0` at a junction, and its
			# slam is exactly this entry. Emitting nothing is the same ending.
			if stepped.is_empty():
				_mark_terminal(event_of, state)
			next_wave.append_array(stepped)
		ctx.wave_index += 1
		wave = next_wave

	# Structure is complete; seconds are assigned exactly once, here, from the
	# spell's authored shape. The walk above landed each wave through
	# `land_one`, which never waits — the beat clock is [method OutcomeApplier.apply]'s
	# concern on the replay pass, and this is what gives it something to wait on.
	outcome.schedule = OutcomeSchedule.compile(outcome, spell.tempo)
	return outcome


## Stamp [member PropagationEvent.is_terminal] on the event a state emitted.
## A state whose reducer merged it away emitted no event and is silently
## skipped — the merged survivor carries the landing, and it is the one that
## either continues or ends.
static func _mark_terminal(event_of: Dictionary, state: CastSpell) -> void:
	var ev: PropagationEvent = event_of.get(state, null)
	if ev != null:
		ev.is_terminal = true


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


## Magic's OWN crit path, and the only one that is mode-specific (#507): the
## [member SpellDef.crit_conditions] OR, evaluated per landing. It has to live
## here because a condition reads [CastSpell] propagation state — predecessor,
## incident_count, the node just landed on — which exists nowhere else.
##
## Stamps a starting [member HitInstance.crit_tier] of 1 when any condition
## fires. The UNIVERSAL stat roll is then layered on top by
## [method CritRoll.decide_all] once the whole cast has resolved, which is what
## makes tier 2 ("both paths fired") mean the same thing it always did while
## leaving exactly one implementation of the stat roll for all three modes.
##
## [param hit] is a [HitInstance], not a [DamageInstance] specifically (#381) —
## heals crit too, since a heal landing at the base-class level has no way to
## opt out.
static func _stamp_crit_conditions(
		spell: SpellDef,
		state: CastSpell,
		hit: HitInstance) -> void:
	if hit == null or hit.amount <= 0.0:
		return
	for cond in spell.crit_conditions:
		if cond != null and cond.evaluate(state, state.current_node, null):
			hit.crit_tier += 1
			# One condition passing is enough to count the condition path;
			# additional conditions don't stack the tier further.
			return


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
	var preds: Array[SkillNode] = []
	var shares := PackedFloat32Array()
	for inc in incidents:
		preds.append(inc.predecessor)
		shares.append(inc.arrival_share)
	cancel_ev.predecessors = preds
	cancel_ev.incident_shares = shares
	cancel_ev.turn_sign = first.turn_sign
	cancel_ev.origin = first.predecessor if first.predecessor != null else first.source
	cancel_ev.target = node
	outcome.timeline.append(cancel_ev)
