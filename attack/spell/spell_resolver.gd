class_name SpellResolver
extends RefCounted

## Pure resolution: produces an [AttackOutcome] for a [SpellDef] seeded at
## [param target] from [param source] (cast-from node) by [param caster],
## using [param graph] for topology queries.
##
## The driver is a single queue loop — generic, knows no spell-specific
## logic. Per-spell behaviour comes from the SpellDef's [SpellPropagation]
## and [OnHitEffect]s. Side-effect free w.r.t. world state: damage application
## is deferred to the VFX layer (each [DamageInstance] carries .amount; the
## coordinator applies it on projectile arrival), so this method is safe to
## call as a preview from AI / tooltip code too.


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
	var prop := spell.propagation
	var initial := CastSpell.new()
	initial.seed_node = target
	initial.current_node = target
	initial.predecessor = null
	initial.source = source
	initial.damage = spell.base_damage * prop.seed_damage_fraction
	initial.hops_remaining = prop.max_hops
	initial.hop_index = 0
	initial.visited = [target]
	initial.caster = caster
	initial.graph = graph
	initial.rng = rng
	# BFS queue — pop_front + append yields strictly hop-monotonic order,
	# which is what the VFX layer wants for staggering.
	var queue: Array[CastSpell] = [initial]
	while not queue.is_empty():
		var state: CastSpell = queue.pop_front()
		for eff in spell.on_hit_effects:
			if eff != null:
				eff.apply(state, outcome)
		if state.hops_remaining > 0:
			queue.append_array(prop.next_hops(state))
	return outcome
