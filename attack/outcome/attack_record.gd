class_name AttackRecord
extends RefCounted

## The wire form of an attack: a POST-APPLY record of what each landing
## actually did, captured on the host as it applies its own [AttackOutcome]
## (#511, `docs/domain/multiplayer-sync-model.md`).
##
## [b]Post-apply, not resolve-time.[/b] This is the direction the owner settled
## on 2026-08-21:
##
## > *"recording all events as they happen, including mitigation (effective
## > dmg), exactly when and where it would happen if played by the host (who
## > can actually tell), we would instead need the client to reconstruct the
## > effects of the attack"*
##
## A client cannot re-derive a combat number: mitigation is read node-locally
## at land time, an earlier beat's cascade can change what a later beat lands
## on, and a target may sit under fog the client knows nothing about. So the
## host runs its natural logic — [method AttackPlan.resolve] then
## [OutcomeApplier], every mode's land-time gate live against the real world —
## and what crosses is the resulting record. A peer never calls `land_on` on a
## mode-specific hit, never re-runs a gate, and never computes a number; it
## replays the recorded deltas through the SAME [OutcomeApplier] loop, on the
## same [BeatClock], so arrival ordering and the forced-dealloc cascade come
## out of the existing machinery rather than a second implementation of it.
##
## [b]Encoding is parallel arrays of scalars, not ~100 dictionaries.[/b] Two
## reasons, and the first is correctness:
##   1. A [PropagationEvent]'s `hits` are SHARED REFERENCES into
##      [member AttackOutcome.hits], never copies. The timeline therefore
##      carries INDICES into the flat hit list, and [method rebuild] restores
##      the aliasing rather than building independent copies per event.
##   2. Volume. `trail_blazer.tres` authorises `max_hops = 20` and
##      `reverberator.tres` `max_visits_per_node = 6`, so one cast can produce
##      ~100 landings.
##
## [b]What does not cross, and why[/b] (traced against master, not guessed):
##   * `HitInstance.source` — a [Variant] whose one real reader
##     ([ArrowVolleyCoordinator]) immediately dereferences `.attacker`, which
##     #507 already promoted to a typed base-class field. The wire carries
##     `attacker` as an `entity_id`; `source` is resolve-local residue.
##   * `AttackOutcome.cancellations` — written by `spell_resolver.gd`, read
##     only by tests. Cancel VFX rides the timeline's `Verb.CANCEL`.
##   * `AttackOutcome.thinned_nodes` — read only by [AiCombatScorer], which is
##     host-side scoring and never runs on a peer.
##
## [b]Known asymmetry, deliberate:[/b] a landing that mitigated to EXACTLY
## zero mutates nothing, so its replay is a no-op and the peer does not
## re-announce it on [signal Events.skill_node_damaged]. The world matches; a
## "0" floater does not appear on the peer. Widening the replay to force that
## announcement would mean a second implementation of
## [method SkillNode.take_damage], which is the parallel-mirrors trap.

## Wire keys. Short because ~100 landings pay for every character, and
## namespaced by prefix so the flat hit arrays and the timeline arrays cannot
## be confused for one another.
const KEY_SEED := "seed"
const KEY_AP := "ap"
const KEY_MANA := "mana"
const KEY_HIT_KIND := "h_kind"
const KEY_HIT_AMOUNT := "h_amt"
const KEY_HIT_TARGET := "h_tgt"
const KEY_HIT_ORIGIN := "h_org"
const KEY_HIT_ATTACKER := "h_atk"
const KEY_HIT_ARRIVAL := "h_at"
const KEY_HIT_FLAGS := "h_flags"
const KEY_HIT_CRIT_TIER := "h_crit"
const KEY_EVENT_BEAT := "e_beat"
const KEY_EVENT_VERB := "e_verb"
const KEY_EVENT_ORIGIN := "e_org"
const KEY_EVENT_TARGET := "e_tgt"
const KEY_EVENT_PRED := "e_pred"
const KEY_EVENT_HITS := "e_hits"

## [constant KEY_HIT_FLAGS] bits.
const FLAG_GATED := 1
const FLAG_CRIT := 2


## Snapshot [param outcome] AFTER the host has applied it — every field this
## reads ([member HitInstance.effective_amount], the post-reclassification
## [member HitInstance.kind], #503's [member HitInstance.gated]) is filled in
## at land time, so calling this before [OutcomeApplier] has run records a
## volley of zeroes rather than an error.
##
## Amounts encode as float64, not float32: the peer's HP must land on exactly
## the host's number, and the acceptance test compares node HP directly.
static func capture(outcome: AttackOutcome, graph: Graph) -> Dictionary:
	var kinds := PackedByteArray()
	var amounts := PackedFloat64Array()
	var targets := PackedInt32Array()
	var origins := PackedInt32Array()
	var attackers := PackedInt32Array()
	var arrivals := PackedFloat64Array()
	var flags := PackedByteArray()
	var crit_tiers := PackedInt32Array()
	# Index of each hit in the flat list, so the timeline can reference it.
	# Identity-keyed, because two landings on one node in one beat are
	# genuinely distinct hits with equal field values.
	var index_of: Dictionary = {}
	for i in outcome.hits.size():
		var hit := outcome.hits[i]
		index_of[hit] = i
		kinds.append(int(hit.kind))
		amounts.append(hit.effective_amount)
		targets.append(_id_of(hit.target, graph))
		origins.append(_id_of(hit.origin, graph))
		attackers.append(hit.attacker.entity_id if hit.attacker != null else 0)
		arrivals.append(hit.arrival_time)
		var f := 0
		if hit.gated:
			f |= FLAG_GATED
		if hit.is_crit:
			f |= FLAG_CRIT
		flags.append(f)
		crit_tiers.append(hit.crit_tier)
	var beats := PackedInt32Array()
	var verbs := PackedByteArray()
	var event_origins := PackedInt32Array()
	var event_targets := PackedInt32Array()
	var preds := PackedInt32Array()
	var event_hits: Array = []
	for event in outcome.timeline:
		beats.append(event.beat)
		verbs.append(int(event.verb))
		event_origins.append(_id_of(event.origin, graph))
		event_targets.append(_id_of(event.target, graph))
		preds.append(_id_of(event.predecessor, graph))
		var refs := PackedInt32Array()
		for hit in event.hits:
			# A hit the event references but the flat list does not hold would
			# rebuild as a dangling index; drop it loudly rather than encode a
			# -1 the far side has to interpret.
			if index_of.has(hit):
				refs.append(index_of[hit])
			else:
				push_warning("AttackRecord: timeline hit is not in outcome.hits; dropped")
		event_hits.append(refs)
	return {
		KEY_SEED: outcome.resolve_seed,
		KEY_AP: outcome.ap_cost,
		KEY_MANA: outcome.mana_cost,
		KEY_HIT_KIND: kinds,
		KEY_HIT_AMOUNT: amounts,
		KEY_HIT_TARGET: targets,
		KEY_HIT_ORIGIN: origins,
		KEY_HIT_ATTACKER: attackers,
		KEY_HIT_ARRIVAL: arrivals,
		KEY_HIT_FLAGS: flags,
		KEY_HIT_CRIT_TIER: crit_tiers,
		KEY_EVENT_BEAT: beats,
		KEY_EVENT_VERB: verbs,
		KEY_EVENT_ORIGIN: event_origins,
		KEY_EVENT_TARGET: event_targets,
		KEY_EVENT_PRED: preds,
		KEY_EVENT_HITS: event_hits,
	}


## Rebuild a replayable [AttackOutcome] from [param d].
##
## The hits that come back are PLAIN [DamageInstance] / [HealInstance] — never
## the mode-specific subclasses. That is the whole point: [BladeDamageInstance]
## and [RangedHitInstance] exist to re-check a gate and re-read live offense at
## land time, and doing either on a peer is the re-simulation the sync model
## forbids. A recorded damage lands as [constant DamageInstance.Type.TRUE] so
## [Mitigation] passes the number through untouched (it was already mitigated
## on the host), and `crit_multiplier` comes back as 1.0 so [method
## CritRoll.apply] is a no-op on a number that already includes the crit.
## [member HitInstance.is_crit] and `crit_tier` still ride along, because the
## VFX layer reads them for emphasis.
static func rebuild(d: Dictionary, graph: Graph) -> AttackOutcome:
	var outcome := AttackOutcome.new()
	if d.is_empty():
		return outcome
	outcome.resolve_seed = int(d.get(KEY_SEED, 0))
	outcome.ap_cost = int(d.get(KEY_AP, 0))
	outcome.mana_cost = int(d.get(KEY_MANA, 0))
	var kinds: PackedByteArray = d.get(KEY_HIT_KIND, PackedByteArray())
	var amounts: PackedFloat64Array = d.get(KEY_HIT_AMOUNT, PackedFloat64Array())
	var targets: PackedInt32Array = d.get(KEY_HIT_TARGET, PackedInt32Array())
	var origins: PackedInt32Array = d.get(KEY_HIT_ORIGIN, PackedInt32Array())
	var attackers: PackedInt32Array = d.get(KEY_HIT_ATTACKER, PackedInt32Array())
	var arrivals: PackedFloat64Array = d.get(KEY_HIT_ARRIVAL, PackedFloat64Array())
	var flags: PackedByteArray = d.get(KEY_HIT_FLAGS, PackedByteArray())
	var crit_tiers: PackedInt32Array = d.get(KEY_HIT_CRIT_TIER, PackedInt32Array())
	for i in kinds.size():
		var gated := (flags[i] & FLAG_GATED) != 0
		var amount: float = 0.0 if gated else amounts[i]
		var hit: HitInstance
		if kinds[i] == int(HitInstance.Kind.HEAL):
			hit = HealInstance.new()
		else:
			var di := DamageInstance.new()
			# Already mitigated on the host. TRUE is the one path
			# `Mitigation.apply` returns `raw.amount` from unchanged — the
			# alternative is re-applying armour to a post-armour number.
			di.type = DamageInstance.Type.TRUE
			hit = di
		hit.amount = amount
		# Carried even when the replay lands nothing (gated, or mitigated to
		# zero on the host), so a VFX reader sees the host's number rather
		# than an empty one.
		hit.effective_amount = amounts[i]
		hit.crit_multiplier = 1.0
		hit.is_crit = (flags[i] & FLAG_CRIT) != 0
		hit.crit_tier = crit_tiers[i]
		hit.gated = gated
		hit.arrival_time = arrivals[i]
		hit.target = _node_of(targets[i], graph)
		hit.origin = _node_of(origins[i], graph)
		hit.attacker = graph.get_by_entity_id(attackers[i]) if graph != null else null
		outcome.hits.append(hit)
	var beats: PackedInt32Array = d.get(KEY_EVENT_BEAT, PackedInt32Array())
	var verbs: PackedByteArray = d.get(KEY_EVENT_VERB, PackedByteArray())
	var event_origins: PackedInt32Array = d.get(KEY_EVENT_ORIGIN, PackedInt32Array())
	var event_targets: PackedInt32Array = d.get(KEY_EVENT_TARGET, PackedInt32Array())
	var preds: PackedInt32Array = d.get(KEY_EVENT_PRED, PackedInt32Array())
	var event_hits: Array = d.get(KEY_EVENT_HITS, [])
	for i in beats.size():
		var event := PropagationEvent.new()
		event.beat = beats[i]
		event.verb = verbs[i] as PropagationEvent.Verb
		event.origin = _node_of(event_origins[i], graph)
		event.target = _node_of(event_targets[i], graph)
		event.predecessor = _node_of(preds[i], graph)
		var refs: PackedInt32Array = event_hits[i] if i < event_hits.size() else PackedInt32Array()
		for index in refs:
			if index >= 0 and index < outcome.hits.size():
				# The SAME object, not a copy — [PropagationEvent]'s contract.
				event.hits.append(outcome.hits[index])
		outcome.timeline.append(event)
	return outcome


## Node -> wire id. Always through [method Graph.get_stable_id], never
## `node.stable_id`: node ids mint LAZILY, so a container-added or
## hand-authored node reads 0 until something forces a topology rebuild
## (`.claude/rules/multiplayer-sync.md`).
static func _id_of(node: SkillNode, graph: Graph) -> int:
	if node == null or graph == null or not is_instance_valid(node):
		return 0
	return graph.get_stable_id(node)


static func _node_of(id: int, graph: Graph) -> SkillNode:
	if id == 0 or graph == null:
		return null
	return graph.get_by_stable_id(id)
