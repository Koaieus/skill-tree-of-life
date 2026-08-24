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
## [b]Corrected by #518: the cascade's machinery is shared, its INPUT is not
## re-derived.[/b] This doc used to claim the cascade came out of the existing
## machinery full stop, and that was true of the machinery and false of the
## input — a peer walked the defender's navigator to work out which nodes
## islanded. Under the deferred filtered-delta model a fogged client may not
## hold those nodes at all, so the walk is not merely redundant, it is wrong.
## The record now carries the deallocation set per hit and the peer applies it
## through the same [method EntityCombat.apply_cascade] the host used. One
## implementation, authoritative input — and the one place
## `.claude/rules/multiplayer-sync.md`'s "a peer re-runs no gate, it replays a
## recorded result" was not literally true is now literally true.
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
## Per-hit HP bar numbers (#518). Distinct from [constant KEY_HIT_AMOUNT],
## which is the FLOATER's post-mitigation number and is allowed to differ on an
## overkill — see [member HitInstance.hp_before].
const KEY_HIT_HP_BEFORE := "h_hp0"
const KEY_HIT_HP_AFTER := "h_hp1"
const KEY_HIT_HP_MAX := "h_hpm"
## The blade vertex pop this landing caused, as the spiked defender's node id —
## 0 for the overwhelming majority of hits (#536). One int per hit rather than a
## flattened side list, because a landing pops at most one vertex.
## See [member HitInstance.popped_vertex] for why a cue is on the wire at all.
const KEY_HIT_POP := "h_pop"
## Forced deallocations, flattened across ALL hits (#518) — one entry per
## cascaded node, plus [constant KEY_DEALLOC_COUNT] giving how many belong to
## each hit, in hit order. Same parallel-scalars discipline as the hit arrays:
## a spell can produce ~100 landings and a wide cascade under each.
const KEY_DEALLOC_COUNT := "d_n"
const KEY_DEALLOC_NODE := "d_node"
const KEY_DEALLOC_LEVEL := "d_lvl"
const KEY_DEALLOC_WOUND := "d_wnd"
const KEY_DEALLOC_CHIP := "d_chip"
## Presentation half of a [DeallocEntry] — the modifier names a client may
## toast as lost. Sliced by [constant KEY_DEALLOC_COUNT] like the rest, but
## with its OWN flat run: an entry can grant several modifiers or none, so the
## per-entry count lives inline in [constant KEY_DEALLOC_LABEL_COUNT].
## A peer that ignores both still ends in the identical world.
const KEY_DEALLOC_LABEL_COUNT := "d_lblc"
const KEY_DEALLOC_LABEL := "d_lbl"
const KEY_EVENT_BEAT := "e_beat"
const KEY_EVENT_VERB := "e_verb"
const KEY_EVENT_ORIGIN := "e_org"
const KEY_EVENT_TARGET := "e_tgt"
const KEY_EVENT_PRED := "e_pred"
## Ragged predecessor set (#542) — the same [constant KEY_DEALLOC_COUNT] /
## [constant KEY_DEALLOC_NODE] shape, flattened across ALL events:
## [constant KEY_EVENT_PRED_COUNT] gives how many predecessors converged on
## each event, in event order; [constant KEY_EVENT_PRED_ALL] is the flat run
## those counts slice back apart. [constant KEY_EVENT_PRED] above stays the
## single canonical predecessor — the VFX-origin reader that already existed
## keeps working unchanged.
const KEY_EVENT_PRED_COUNT := "e_predc"
const KEY_EVENT_PRED_ALL := "e_preda"
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
	var hp_before := PackedFloat64Array()
	var hp_after := PackedFloat64Array()
	var hp_max := PackedFloat64Array()
	var pops := PackedInt32Array()
	# Flattened across all hits; `dealloc_counts` slices it back apart.
	var dealloc_counts := PackedInt32Array()
	var dealloc_nodes := PackedInt32Array()
	var dealloc_levels := PackedInt32Array()
	var dealloc_wounds := PackedInt32Array()
	var dealloc_chips := PackedFloat64Array()
	var dealloc_label_counts := PackedInt32Array()
	var dealloc_labels := PackedStringArray()
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
		hp_before.append(hit.hp_before)
		hp_after.append(hit.hp_after)
		hp_max.append(hit.hp_max)
		pops.append(_id_of(hit.popped_vertex, graph))
		dealloc_counts.append(hit.deallocations.size())
		for e in hit.deallocations:
			# The id, never the reference (`.claude/rules/multiplayer-sync.md`).
			# `_id_of` forces the topology rebuild that mints a lazy stable_id,
			# so a node that was never asked a topology question still encodes
			# as itself rather than as 0.
			dealloc_nodes.append(_id_of(e.node, graph))
			dealloc_levels.append(e.allocation_level)
			dealloc_wounds.append(e.wound)
			dealloc_chips.append(e.chip)
			dealloc_label_counts.append(e.revoked_labels.size())
			dealloc_labels.append_array(e.revoked_labels)
	var beats := PackedInt32Array()
	var verbs := PackedByteArray()
	var event_origins := PackedInt32Array()
	var event_targets := PackedInt32Array()
	var preds := PackedInt32Array()
	# Flattened across all events; `pred_counts` slices it back apart —
	# same discipline as the dealloc arrays above (#542).
	var pred_counts := PackedInt32Array()
	var pred_all := PackedInt32Array()
	var event_hits: Array = []
	for event in outcome.timeline:
		beats.append(event.beat)
		verbs.append(int(event.verb))
		event_origins.append(_id_of(event.origin, graph))
		event_targets.append(_id_of(event.target, graph))
		preds.append(_id_of(event.predecessor, graph))
		pred_counts.append(event.predecessors.size())
		for pred in event.predecessors:
			pred_all.append(_id_of(pred, graph))
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
		KEY_HIT_HP_BEFORE: hp_before,
		KEY_HIT_HP_AFTER: hp_after,
		KEY_HIT_HP_MAX: hp_max,
		KEY_HIT_POP: pops,
		KEY_DEALLOC_COUNT: dealloc_counts,
		KEY_DEALLOC_NODE: dealloc_nodes,
		KEY_DEALLOC_LEVEL: dealloc_levels,
		KEY_DEALLOC_WOUND: dealloc_wounds,
		KEY_DEALLOC_CHIP: dealloc_chips,
		KEY_DEALLOC_LABEL_COUNT: dealloc_label_counts,
		KEY_DEALLOC_LABEL: dealloc_labels,
		KEY_EVENT_BEAT: beats,
		KEY_EVENT_VERB: verbs,
		KEY_EVENT_ORIGIN: event_origins,
		KEY_EVENT_TARGET: event_targets,
		KEY_EVENT_PRED: preds,
		KEY_EVENT_PRED_COUNT: pred_counts,
		KEY_EVENT_PRED_ALL: pred_all,
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
	var hp_before: PackedFloat64Array = d.get(KEY_HIT_HP_BEFORE, PackedFloat64Array())
	var hp_after: PackedFloat64Array = d.get(KEY_HIT_HP_AFTER, PackedFloat64Array())
	var hp_max: PackedFloat64Array = d.get(KEY_HIT_HP_MAX, PackedFloat64Array())
	var pops: PackedInt32Array = d.get(KEY_HIT_POP, PackedInt32Array())
	var dealloc_counts: PackedInt32Array = d.get(KEY_DEALLOC_COUNT, PackedInt32Array())
	var dealloc_nodes: PackedInt32Array = d.get(KEY_DEALLOC_NODE, PackedInt32Array())
	var dealloc_levels: PackedInt32Array = d.get(KEY_DEALLOC_LEVEL, PackedInt32Array())
	var dealloc_wounds: PackedInt32Array = d.get(KEY_DEALLOC_WOUND, PackedInt32Array())
	var dealloc_chips: PackedFloat64Array = d.get(KEY_DEALLOC_CHIP, PackedFloat64Array())
	var dealloc_label_counts: PackedInt32Array = d.get(KEY_DEALLOC_LABEL_COUNT, PackedInt32Array())
	var dealloc_labels: PackedStringArray = d.get(KEY_DEALLOC_LABEL, PackedStringArray())
	# Second running offset: labels are a flat run over ENTRIES, not over hits,
	# so it advances independently of `dealloc_at`.
	var label_at := 0
	# Running offset into the flattened dealloc arrays, advanced by each hit's
	# own count. The counts array is what slices one flat run back into per-hit
	# groups; without it the entries would all belong to hit 0.
	var dealloc_at := 0
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
		if i < hp_before.size():
			hit.hp_before = hp_before[i]
			hit.hp_after = hp_after[i]
			hit.hp_max = hp_max[i]
		if i < pops.size():
			# 0 means "popped nothing", which `_node_of` already answers as null.
			hit.popped_vertex = _node_of(pops[i], graph)
		# The cascade this landing caused, RECORDED. A peer applies exactly this
		# set instead of walking the defender's navigator for one — under the
		# filtered-delta model it may not hold the nodes that walk would visit,
		# and re-deriving is the one place `.claude/rules/multiplayer-sync.md`'s
		# "a peer replays a recorded result" was not literally true (#518).
		if i < dealloc_counts.size():
			var count := dealloc_counts[i]
			var entries: Array[DeallocEntry] = []
			for k in count:
				var at := dealloc_at + k
				var entry := DeallocEntry.new()
				entry.node_id = dealloc_nodes[at]
				entry.node = _node_of(entry.node_id, graph)
				entry.allocation_level = dealloc_levels[at]
				entry.wound = dealloc_wounds[at]
				entry.chip = dealloc_chips[at]
				if at < dealloc_label_counts.size():
					var label_count := dealloc_label_counts[at]
					entry.revoked_labels = dealloc_labels.slice(label_at, label_at + label_count)
					label_at += label_count
				entries.append(entry)
			hit.deallocations = entries
			dealloc_at += count
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
	var pred_counts: PackedInt32Array = d.get(KEY_EVENT_PRED_COUNT, PackedInt32Array())
	var pred_all: PackedInt32Array = d.get(KEY_EVENT_PRED_ALL, PackedInt32Array())
	var event_hits: Array = d.get(KEY_EVENT_HITS, [])
	# Running offset into the flattened predecessor array, same shape as
	# `dealloc_at` above — advanced by each event's own count.
	var pred_at := 0
	for i in beats.size():
		var event := PropagationEvent.new()
		event.beat = beats[i]
		event.verb = verbs[i] as PropagationEvent.Verb
		event.origin = _node_of(event_origins[i], graph)
		event.target = _node_of(event_targets[i], graph)
		event.predecessor = _node_of(preds[i], graph)
		if i < pred_counts.size():
			var count := pred_counts[i]
			var set: Array[SkillNode] = []
			for k in count:
				set.append(_node_of(pred_all[pred_at + k], graph))
			event.predecessors = set
			pred_at += count
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
