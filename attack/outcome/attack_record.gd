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
##   * `AttackOutcome.popped_nodes` — read only by [AiCombatScorer], which is
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
## Which arithmetic turns [constant KEY_HIT_STRUCT] into seconds — one per
## outcome, because an outcome is one mode. See [enum ScheduleEntry.Cadence].
const KEY_CADENCE := "cad"
## `resource_path` of the [PresentationTempo] the host compiled against, or ""
## for the shared default (#543 D3a). The SHAPE is authored content both peers
## already have on disk, so shipping the path — not the numbers — is what lets
## a peer reproduce the spell's identity while still folding in its OWN rate.
const KEY_TEMPO := "tempo"
const KEY_HIT_KIND := "h_kind"
const KEY_HIT_AMOUNT := "h_amt"
const KEY_HIT_TARGET := "h_tgt"
const KEY_HIT_ORIGIN := "h_org"
const KEY_HIT_ATTACKER := "h_atk"
## The landing's STRUCTURAL key (#543 D4) — a hop ordinal for magic, normalized
## position in the volley's distance span for ranged, normalized swing position
## for melee. [b]Seconds never cross the wire.[/b] Each peer runs
## [method OutcomeSchedule.compile] over this plus [constant KEY_CADENCE] and
## its own [member GameSettings.combat_time_scale], so two machines may play
## combat at different speeds and still land the identical sequence — safe only
## because ordering keys off [member HitInstance.schedule_index] and never off
## a float (#543 D2).
##
## [b]The win is semantic, not wire bytes:[/b] melee's structural parameter is
## genuinely [BladeSim] output a peer replays rather than re-runs, so this is
## still one float per hit, exactly the size the old `h_at` was.
const KEY_HIT_STRUCT := "h_key"
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
## [member StatusInstance.def]'s `resource_path`, "" for every non-STATUS hit
## (#878). Same pattern as [constant KEY_TEMPO]/`_tempo_path` — the def is
## authored content both peers already have on disk, so shipping the path
## (never a live reference) is what lets a peer's [method rebuild] reproduce
## which status landed. [member StatusInstance.power] itself needs no new
## array: [constant KEY_HIT_AMOUNT] already carries every hit's
## `effective_amount`, and [method StatusInstance.land_on] writes `power`
## there at land time, so a status rides that array for free.
const KEY_HIT_STATUS_DEF := "h_sdef"
## [member StatusInstance.host_kind] per hit (#996) — `0` (NODE) for every
## non-STATUS hit. The landed host is a resolved fact like `power_resolved`:
## a peer lands on the shipped host, never re-derives it from node HP.
const KEY_HIT_STATUS_HOST := "h_shost"
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
## Per-event render context the resolver computes and used to discard
## (#543 D6): the 0-based nth-strike-on-this-node index Reverberator reads, and
## a flag for the landings the walk ENDED at (Trail Blazer's junction slam).
## Structure, not seconds — a peer's visual must read the same values the
## host's did or the two pictures tell different stories.
const KEY_EVENT_VISIT := "e_visit"
const KEY_EVENT_TERMINAL := "e_term"
const KEY_EVENT_HITS := "e_hits"

## [constant KEY_HIT_FLAGS] bits.
const FLAG_GATED := 1
const FLAG_CRIT := 2



## The wire form as COLUMNS (#1000): one typed packed array per hit / dealloc /
## event field, declared once in [method wire_fields] and walked by
## [WireFields] in both directions, so a key can no longer be written on one
## side and read differently on the other. [method capture] fills an instance
## and hands it to [method WireFields.to_dict]; [method rebuild] decodes one
## and unpacks it. The columns ARE the encoding the class note argues for —
## a record instance is a transient the two static entry points share, never
## something a caller holds.
var resolve_seed: int = 0
var ap_cost: int = 0
var mana_cost: int = 0
var cadence: int = 0
var tempo: String = ""
var kinds := PackedByteArray()
var amounts := PackedFloat64Array()
var targets := PackedInt32Array()
var origins := PackedInt32Array()
var attackers := PackedInt32Array()
var structural := PackedFloat64Array()
var flags := PackedByteArray()
var crit_tiers := PackedInt32Array()
var hp_before := PackedFloat64Array()
var hp_after := PackedFloat64Array()
var hp_max := PackedFloat64Array()
var pops := PackedInt32Array()
var status_defs := PackedStringArray()
var status_hosts := PackedInt32Array()
## Flattened across all hits; `dealloc_counts` slices the run back apart.
var dealloc_counts := PackedInt32Array()
var dealloc_nodes := PackedInt32Array()
var dealloc_levels := PackedInt32Array()
var dealloc_wounds := PackedInt32Array()
var dealloc_chips := PackedFloat64Array()
var dealloc_label_counts := PackedInt32Array()
var dealloc_labels := PackedStringArray()
var beats := PackedInt32Array()
var verbs := PackedByteArray()
var event_origins := PackedInt32Array()
var event_targets := PackedInt32Array()
var preds := PackedInt32Array()
## Flattened across all events; `pred_counts` slices the run back apart —
## same discipline as the dealloc columns (#542).
var pred_counts := PackedInt32Array()
var pred_all := PackedInt32Array()
var visits := PackedInt32Array()
var terminals := PackedByteArray()
## Per event, the INDICES into [member kinds] & co. of the hits it carries.
var event_hits: Array[PackedInt32Array] = []


static func wire_fields() -> Array[WireFields.Field]:
	return [
		WireFields.Field.new(&"resolve_seed", TYPE_INT).as_key(KEY_SEED),
		WireFields.Field.new(&"ap_cost", TYPE_INT).as_key(KEY_AP),
		WireFields.Field.new(&"mana_cost", TYPE_INT).as_key(KEY_MANA),
		WireFields.Field.new(&"cadence", TYPE_INT).as_key(KEY_CADENCE),
		WireFields.Field.new(&"tempo", TYPE_STRING).as_key(KEY_TEMPO),
		WireFields.Field.new(&"kinds", TYPE_PACKED_BYTE_ARRAY).as_key(KEY_HIT_KIND),
		WireFields.Field.new(&"amounts", TYPE_PACKED_FLOAT64_ARRAY).as_key(KEY_HIT_AMOUNT),
		WireFields.Field.new(&"targets", TYPE_PACKED_INT32_ARRAY).as_key(KEY_HIT_TARGET),
		WireFields.Field.new(&"origins", TYPE_PACKED_INT32_ARRAY).as_key(KEY_HIT_ORIGIN),
		WireFields.Field.new(&"attackers", TYPE_PACKED_INT32_ARRAY).as_key(KEY_HIT_ATTACKER),
		WireFields.Field.new(&"structural", TYPE_PACKED_FLOAT64_ARRAY).as_key(KEY_HIT_STRUCT),
		WireFields.Field.new(&"flags", TYPE_PACKED_BYTE_ARRAY).as_key(KEY_HIT_FLAGS),
		WireFields.Field.new(&"crit_tiers", TYPE_PACKED_INT32_ARRAY).as_key(KEY_HIT_CRIT_TIER),
		WireFields.Field.new(&"hp_before", TYPE_PACKED_FLOAT64_ARRAY).as_key(KEY_HIT_HP_BEFORE),
		WireFields.Field.new(&"hp_after", TYPE_PACKED_FLOAT64_ARRAY).as_key(KEY_HIT_HP_AFTER),
		WireFields.Field.new(&"hp_max", TYPE_PACKED_FLOAT64_ARRAY).as_key(KEY_HIT_HP_MAX),
		WireFields.Field.new(&"pops", TYPE_PACKED_INT32_ARRAY).as_key(KEY_HIT_POP),
		WireFields.Field.new(&"status_defs", TYPE_PACKED_STRING_ARRAY).as_key(KEY_HIT_STATUS_DEF),
		WireFields.Field.new(&"status_hosts", TYPE_PACKED_INT32_ARRAY).as_key(KEY_HIT_STATUS_HOST),
		WireFields.Field.new(&"dealloc_counts", TYPE_PACKED_INT32_ARRAY).as_key(KEY_DEALLOC_COUNT),
		WireFields.Field.new(&"dealloc_nodes", TYPE_PACKED_INT32_ARRAY).as_key(KEY_DEALLOC_NODE),
		WireFields.Field.new(&"dealloc_levels", TYPE_PACKED_INT32_ARRAY).as_key(KEY_DEALLOC_LEVEL),
		WireFields.Field.new(&"dealloc_wounds", TYPE_PACKED_INT32_ARRAY).as_key(KEY_DEALLOC_WOUND),
		WireFields.Field.new(&"dealloc_chips", TYPE_PACKED_FLOAT64_ARRAY).as_key(KEY_DEALLOC_CHIP),
		WireFields.Field.new(&"dealloc_label_counts", TYPE_PACKED_INT32_ARRAY).as_key(KEY_DEALLOC_LABEL_COUNT),
		WireFields.Field.new(&"dealloc_labels", TYPE_PACKED_STRING_ARRAY).as_key(KEY_DEALLOC_LABEL),
		WireFields.Field.new(&"beats", TYPE_PACKED_INT32_ARRAY).as_key(KEY_EVENT_BEAT),
		WireFields.Field.new(&"verbs", TYPE_PACKED_BYTE_ARRAY).as_key(KEY_EVENT_VERB),
		WireFields.Field.new(&"event_origins", TYPE_PACKED_INT32_ARRAY).as_key(KEY_EVENT_ORIGIN),
		WireFields.Field.new(&"event_targets", TYPE_PACKED_INT32_ARRAY).as_key(KEY_EVENT_TARGET),
		WireFields.Field.new(&"preds", TYPE_PACKED_INT32_ARRAY).as_key(KEY_EVENT_PRED),
		WireFields.Field.new(&"pred_counts", TYPE_PACKED_INT32_ARRAY).as_key(KEY_EVENT_PRED_COUNT),
		WireFields.Field.new(&"pred_all", TYPE_PACKED_INT32_ARRAY).as_key(KEY_EVENT_PRED_ALL),
		WireFields.Field.new(&"visits", TYPE_PACKED_INT32_ARRAY).as_key(KEY_EVENT_VISIT),
		WireFields.Field.new(&"terminals", TYPE_PACKED_BYTE_ARRAY).as_key(KEY_EVENT_TERMINAL),
		WireFields.Field.new(&"event_hits", TYPE_ARRAY).of(TYPE_PACKED_INT32_ARRAY).as_key(KEY_EVENT_HITS),
	]


## Snapshot [param outcome] AFTER the host has applied it — every field this
## reads ([member HitInstance.effective_amount], the post-reclassification
## [member HitInstance.kind], #503's [member HitInstance.gated]) is filled in
## at land time, so calling this before [OutcomeApplier] has run records a
## volley of zeroes rather than an error.
##
## Amounts encode as float64, not float32: the peer's HP must land on exactly
## the host's number, and the acceptance test compares node HP directly.
static func capture(outcome: AttackOutcome, graph: Graph) -> Dictionary:
	var r := AttackRecord.new()
	r.resolve_seed = outcome.resolve_seed
	r.ap_cost = outcome.ap_cost
	r.mana_cost = outcome.mana_cost
	r.cadence = int(outcome.cadence)
	r.tempo = _tempo_path(outcome)
	# Index of each hit in the flat list, so the timeline can reference it.
	# Identity-keyed, because two landings on one node in one beat are
	# genuinely distinct hits with equal field values.
	var index_of: Dictionary = {}
	for i in outcome.hits.size():
		var hit := outcome.hits[i]
		index_of[hit] = i
		r.kinds.append(int(hit.kind))
		r.amounts.append(hit.effective_amount)
		r.targets.append(_id_of(hit.target, graph))
		r.origins.append(_id_of(hit.origin, graph))
		r.attackers.append(hit.attacker.entity_id if hit.attacker != null else 0)
		r.structural.append(hit.structural_key)
		var f := 0
		if hit.gated:
			f |= FLAG_GATED
		if hit.is_crit:
			f |= FLAG_CRIT
		r.flags.append(f)
		r.crit_tiers.append(hit.crit_tier)
		r.hp_before.append(hit.hp_before)
		r.hp_after.append(hit.hp_after)
		r.hp_max.append(hit.hp_max)
		r.pops.append(_id_of(hit.popped_vertex, graph))
		var status_hit := hit as StatusInstance
		r.status_defs.append(status_hit.def.resource_path if status_hit != null and status_hit.def != null else "")
		r.status_hosts.append(int(status_hit.host_kind) if status_hit != null else 0)
		r.dealloc_counts.append(hit.deallocations.size())
		for e in hit.deallocations:
			# The id, never the reference (`.claude/rules/multiplayer-sync.md`).
			# `_id_of` forces the topology rebuild that mints a lazy stable_id,
			# so a node that was never asked a topology question still encodes
			# as itself rather than as 0.
			r.dealloc_nodes.append(_id_of(e.node, graph))
			r.dealloc_levels.append(e.allocation_level)
			r.dealloc_wounds.append(e.wound)
			r.dealloc_chips.append(e.chip)
			r.dealloc_label_counts.append(e.revoked_labels.size())
			r.dealloc_labels.append_array(e.revoked_labels)
	for event in outcome.timeline:
		r.beats.append(event.beat)
		r.visits.append(event.visit_index)
		r.terminals.append(1 if event.is_terminal else 0)
		r.verbs.append(int(event.verb))
		r.event_origins.append(_id_of(event.origin, graph))
		r.event_targets.append(_id_of(event.target, graph))
		r.preds.append(_id_of(event.predecessor, graph))
		r.pred_counts.append(event.predecessors.size())
		for pred in event.predecessors:
			r.pred_all.append(_id_of(pred, graph))
		var refs := PackedInt32Array()
		for hit in event.hits:
			# A hit the event references but the flat list does not hold would
			# rebuild as a dangling index; drop it loudly rather than encode a
			# -1 the far side has to interpret.
			if index_of.has(hit):
				refs.append(index_of[hit])
			else:
				push_warning("AttackRecord: timeline hit is not in outcome.hits; dropped")
		r.event_hits.append(refs)
	return WireFields.to_dict(r)


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
## [param rate] is THIS MACHINE'S presentation rate for the actor whose attack
## this is — the multiplier [method OutcomeSchedule.compile] folds into every
## arrival time. Negative (the default) means "read the ambient
## [member GameSettings.combat_time_scale]", which is what every caller outside
## [method BattleSystem.apply_launch_command] wants. It is a parameter rather
## than an ambient read because the rate is a per-actor, per-machine decision
## (#819) and a record is pure data with no opinion about seats — see
## [method OutcomeSchedule.actor_rate], the one place that composes it.
static func rebuild(d: Dictionary, graph: Graph, rate: float = -1.0) -> AttackOutcome:
	var outcome := AttackOutcome.new()
	if d.is_empty():
		return outcome
	var r := WireFields.from_dict(AttackRecord, d) as AttackRecord
	outcome.resolve_seed = r.resolve_seed
	outcome.ap_cost = r.ap_cost
	outcome.mana_cost = r.mana_cost
	outcome.cadence = r.cadence as ScheduleEntry.Cadence
	# Second running offset: labels are a flat run over ENTRIES, not over hits,
	# so it advances independently of `dealloc_at`.
	var label_at := 0
	# Running offset into the flattened dealloc arrays, advanced by each hit's
	# own count. The counts array is what slices one flat run back into per-hit
	# groups; without it the entries would all belong to hit 0.
	var dealloc_at := 0
	for i in r.kinds.size():
		var gated := (r.flags[i] & FLAG_GATED) != 0
		var amount: float = 0.0 if gated else r.amounts[i]
		var hit: HitInstance
		if r.kinds[i] == int(HitInstance.Kind.HEAL):
			hit = HealInstance.new()
		elif r.kinds[i] == int(HitInstance.Kind.STATUS):
			var si := StatusInstance.new()
			var def_path: String = r.status_defs[i] if i < r.status_defs.size() else ""
			if not def_path.is_empty():
				if ResourceLoader.exists(def_path):
					si.def = load(def_path) as StatusDef
				else:
					push_warning("AttackRecord: status def %s not found on this machine" % def_path)
			# The authority's own `land_on` already folded potency and
			# resistance into this number (#963); the peer lands it flat.
			si.power = amount
			si.power_resolved = true
			# The landed host is a resolved fact too (#996): the peer lands on
			# the shipped host, never re-derives it from its own node HP.
			if i < r.status_hosts.size():
				si.host_kind = r.status_hosts[i] as StatusInstance.HostKind
			hit = si
		else:
			var di := DamageInstance.new()
			# Already mitigated on the host. TRUE is the one path
			# `Mitigation.apply` returns `raw.amount` from unchanged — the
			# alternative is re-applying armour to a post-armour number.
			di.type = DamageInstance.Type.TRUE
			hit = di
		# `basis` stays at its FLAT default on purpose: the authority's own
		# `land_on` already resolved a PERCENT_MAX coefficient into this number
		# (HitInstance.resolve_amount), and a peer must land it, not re-scale it.
		hit.amount = amount
		# Carried even when the replay lands nothing (gated, or mitigated to
		# zero on the host), so a VFX reader sees the host's number rather
		# than an empty one.
		hit.effective_amount = r.amounts[i]
		hit.crit_multiplier = 1.0
		hit.is_crit = (r.flags[i] & FLAG_CRIT) != 0
		hit.crit_tier = r.crit_tiers[i]
		if i < r.hp_before.size():
			hit.hp_before = r.hp_before[i]
			hit.hp_after = r.hp_after[i]
			hit.hp_max = r.hp_max[i]
		if i < r.pops.size():
			# 0 means "popped nothing", which `_node_of` already answers as null.
			hit.popped_vertex = _node_of(r.pops[i], graph)
		# The cascade this landing caused, RECORDED. A peer applies exactly this
		# set instead of walking the defender's navigator for one — under the
		# filtered-delta model it may not hold the nodes that walk would visit,
		# and re-deriving is the one place `.claude/rules/multiplayer-sync.md`'s
		# "a peer replays a recorded result" was not literally true (#518).
		if i < r.dealloc_counts.size():
			var count := r.dealloc_counts[i]
			var entries: Array[DeallocEntry] = []
			for k in count:
				var at := dealloc_at + k
				var entry := DeallocEntry.new()
				entry.node_id = r.dealloc_nodes[at]
				entry.node = _node_of(entry.node_id, graph)
				entry.allocation_level = r.dealloc_levels[at]
				entry.wound = r.dealloc_wounds[at]
				entry.chip = r.dealloc_chips[at]
				if at < r.dealloc_label_counts.size():
					var label_count := r.dealloc_label_counts[at]
					entry.revoked_labels = r.dealloc_labels.slice(label_at, label_at + label_count)
					label_at += label_count
				entries.append(entry)
			hit.deallocations = entries
			dealloc_at += count
		hit.gated = gated
		hit.structural_key = r.structural[i]
		hit.target = _node_of(r.targets[i], graph)
		hit.origin = _node_of(r.origins[i], graph)
		hit.attacker = graph.get_by_entity_id(r.attackers[i]) if graph != null else null
		outcome.hits.append(hit)
	# Running offset into the flattened predecessor array, same shape as
	# `dealloc_at` above — advanced by each event's own count.
	var pred_at := 0
	for i in r.beats.size():
		var event := PropagationEvent.new()
		event.beat = r.beats[i]
		event.visit_index = r.visits[i] if i < r.visits.size() else 0
		event.is_terminal = i < r.terminals.size() and r.terminals[i] != 0
		event.verb = r.verbs[i] as PropagationEvent.Verb
		event.origin = _node_of(r.event_origins[i], graph)
		event.target = _node_of(r.event_targets[i], graph)
		event.predecessor = _node_of(r.preds[i], graph)
		if i < r.pred_counts.size():
			var count := r.pred_counts[i]
			var set: Array[SkillNode] = []
			for k in count:
				set.append(_node_of(r.pred_all[pred_at + k], graph))
			event.predecessors = set
			pred_at += count
		var refs: PackedInt32Array = r.event_hits[i] if i < r.event_hits.size() else PackedInt32Array()
		for index in refs:
			if index >= 0 and index < outcome.hits.size():
				# The SAME object, not a copy — [PropagationEvent]'s contract.
				event.hits.append(outcome.hits[index])
		outcome.timeline.append(event)
	# Seconds are minted HERE, on the peer, from the structure that just
	# crossed plus this machine's own rate (#543 D4) — never decoded, because
	# they were never encoded. One compile, so the applier's wait and the VFX
	# layer read the same schedule object rather than two agreeing copies.
	outcome.schedule = OutcomeSchedule.compile(outcome, _tempo_of(r.tempo), rate)
	return outcome


## The [PresentationTempo] a schedule was compiled against, as a path — "" when
## it is the shared default or when nothing compiled one, which is the same
## thing to the far side ([method OutcomeSchedule.compile] falls back to
## [method PresentationTempo.shared_default] on null).
static func _tempo_path(outcome: AttackOutcome) -> String:
	if outcome.schedule == null or outcome.schedule.tempo == null:
		return ""
	var path: String = outcome.schedule.tempo.resource_path
	return "" if path == PresentationTempo.DEFAULT_PATH else path


## Inverse of [method _tempo_path]. A path the peer cannot resolve (a build
## skew, a renamed `.tres`) degrades to the shared default rather than to no
## presentation at all — a spell that plays on the wrong CADENCE is a cosmetic
## bug; one that does not play is a lost turn.
static func _tempo_of(path: String) -> PresentationTempo:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as PresentationTempo


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
