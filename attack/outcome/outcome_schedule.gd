class_name OutcomeSchedule
extends RefCounted

## The compiled presentation timeline of one [AttackOutcome] — and the pure
## compiler that produces it (#543).
##
## [b]The resolver emits structure; the compiler assigns seconds.[/b] That is
## the whole issue in one line. Every mode used to stamp its own presentation
## constants into [member HitInstance.arrival_time] during resolution
## ([SpellResolver]'s wave interval, [RangedDamageFormula]'s flight time,
## [BladeHitEvent]'s `t`), which made tempo a serialized fact rather than a
## tunable and put three copies of "when does this land" in three files. Now
## each mode records only its structural parameter and this runs
## `(AttackOutcome, PresentationTempo, rate) -> OutcomeSchedule` over it.
##
## [b]It is honestly a compiler, not a mapper.[/b] Melee's structural parameter
## is normalized swing position — genuinely [BladeSim] output, continuous time
## the resolver cannot not know — so the claim "the resolver knows no timing"
## would be false. What IS true, and is what this buys: no mode decides
## seconds.
##
## [b]Seconds never cross the wire[/b] (D4). [AttackRecord] carries the
## structural keys and the cadence; each peer compiles its own schedule against
## its own [member GameSettings.combat_time_scale]. That is only safe because
## of D2 — landing order and [CritRoll]'s seeded stream key off
## [member ScheduleEntry.index], never off a float — so a peer running combat
## at half speed lands the identical sequence with the identical numbers.
##
## [b]Pure.[/b] Instantiates no [Node], touches no [SceneTree], reads the world
## not at all. The one ambient read is the player's rate, and it is a defaulted
## parameter precisely so a test can pin it.

## Every moment in the attack, ascending by structure. [member ScheduleEntry.index]
## equals the array position.
var entries: Array[ScheduleEntry] = []

## The shape this was compiled against, kept so a coordinator can ask for the
## beat interval it must animate to instead of holding a duplicate export of
## its own.
var tempo: PresentationTempo = null

## The player-facing rate that was folded in, 1.0 = authored speed.
var rate: float = 1.0


## Compile [param outcome] into a schedule and stamp the result back onto its
## hits (see [method _write_back]).
##
## [param tempo] null falls back to [method PresentationTempo.shared_default].
## [param rate] negative means "read the player's setting"; pass an explicit
## value in tests so timing is not ambient.
##
## [b]Compiles from [member AttackOutcome.timeline] when it has one[/b] (D7).
## A [constant PropagationEvent.Verb.CANCEL] and a zero-damage utility landing
## both carry no [HitInstance] at all, so a hits-derived schedule would
## silently drop every cancel pop and no-op every pure-utility spell — the same
## reason [MagicBounceCoordinator] guards on `timeline.is_empty()` rather than
## on `hits`. Melee and ranged emit no timeline and compile from their hits,
## one entry per landing.
static func compile(outcome: AttackOutcome, tempo: PresentationTempo = null,
		rate: float = -1.0) -> OutcomeSchedule:
	var schedule := OutcomeSchedule.new()
	schedule.tempo = tempo if tempo != null else PresentationTempo.shared_default()
	schedule.rate = rate if rate >= 0.0 else ambient_rate()
	if outcome == null:
		return schedule
	var cadence: ScheduleEntry.Cadence = outcome.cadence
	var raw: Array[ScheduleEntry] = _entries_for(outcome)
	schedule.entries = _sorted(raw)
	schedule._assign(cadence)
	schedule._write_back()
	return schedule


## Total seconds the presentation occupies — the last arrival. What
## [CameraDirector] sizes its attack focus from, instead of hand-computing a
## `maxf` over every hit's cached time.
func duration() -> float:
	var last := 0.0
	for entry in entries:
		last = maxf(last, entry.arrive_at)
	return last


## Seconds between magic beats, rate included — the number a coordinator
## animates to. Reading it here rather than holding an `@export` is what
## deletes the old "retune either and re-check both" tax.
func beat_interval() -> float:
	var shape: PresentationTempo = tempo if tempo != null else PresentationTempo.shared_default()
	return maxf(0.001, shape.beat_interval * rate)


## Seconds a magic bolt is in the air, rate included. Clamped to
## [method beat_interval] for the same reason the compiler clamps it: a
## lead-in longer than the beat would have wave N+1 launch before wave N lands.
func lead_in() -> float:
	var shape: PresentationTempo = tempo if tempo != null else PresentationTempo.shared_default()
	return clampf(shape.beat_lead_in * rate, 0.0, beat_interval())


## The entry a given hit belongs to, or null. Linear — used by tests and by
## one-off lookups, never inside a landing loop (that is what
## [member HitInstance.schedule_index] caches).
func entry_for(hit: HitInstance) -> ScheduleEntry:
	if hit == null:
		return null
	if hit.schedule_index >= 0 and hit.schedule_index < entries.size():
		return entries[hit.schedule_index]
	for entry in entries:
		if entry.hits.has(hit):
			return entry
	return null


## The player's "fast combat" / slow-motion rate, or 1.0 wherever there is no
## live [code]Settings[/code] autoload (a `--script` run, a bare unit test).
## Static and defensive on purpose: the compiler must stay callable from a
## pure context.
static func ambient_rate() -> float:
	var loop := Engine.get_main_loop()
	var tree := loop as SceneTree
	if tree == null or tree.root == null:
		return 1.0
	var node: Node = tree.root.get_node_or_null(^"Settings")
	if node == null:
		return 1.0
	var settings: GameSettings = node.get(&"current") as GameSettings
	if settings == null:
		return 1.0
	return maxf(0.01, settings.combat_time_scale)


static func _entries_for(outcome: AttackOutcome) -> Array[ScheduleEntry]:
	var raw: Array[ScheduleEntry] = []
	if not outcome.timeline.is_empty():
		for event in outcome.timeline:
			var entry := ScheduleEntry.new()
			entry.structural_key = float(event.beat)
			entry.beat_index = event.beat
			entry.convergence_count = maxi(1, event.predecessors.size())
			entry.visit_index = event.visit_index
			entry.is_terminal = event.is_terminal
			entry.origin = event.origin
			entry.target = event.target
			# Shared references, never copies — PropagationEvent's contract.
			entry.hits = event.hits
			entry.event = event
			raw.append(entry)
		return raw
	for hit in outcome.hits:
		var entry := ScheduleEntry.new()
		entry.structural_key = hit.structural_key
		entry.origin = hit.origin
		entry.target = hit.target
		entry.hits = [hit] as Array[HitInstance]
		raw.append(entry)
	return raw


## Decorate-sort-undecorate on `(structural_key, original_index)` — the same
## discipline, and the same exact-float comparison, that
## [method OutcomeApplier.in_arrival_order] used to apply to seconds.
##
## Exact `!=`, deliberately, NOT [method is_equal_approx]: an approximate tie
## test is not transitive, which violates the strict weak ordering
## [method Array.sort_custom] requires. Every intended tie here is exact — a
## whole magic wave stamps one integer beat, two shots at equal distance
## produce the same lerp bit-for-bit.
static func _sorted(raw: Array[ScheduleEntry]) -> Array[ScheduleEntry]:
	var decorated: Array = []
	for i in raw.size():
		decorated.append([raw[i].structural_key, i, raw[i]])
	decorated.sort_custom(func(a: Array, b: Array) -> bool:
		if a[0] != b[0]:
			return a[0] < b[0]
		return a[1] < b[1])
	var out: Array[ScheduleEntry] = []
	for row in decorated:
		out.append(row[2])
	return out


## Structure -> seconds, plus the derived per-entry context D6 specifies.
func _assign(cadence: ScheduleEntry.Cadence) -> void:
	var shape: PresentationTempo = tempo if tempo != null else PresentationTempo.shared_default()
	var beat_span: float = maxf(0.001, shape.beat_interval)
	# Clamped rather than trusted: a lead-in longer than the beat would put
	# wave N+1's launch before wave N's impact, which is not a tuning choice,
	# it is a broken picture.
	var lead: float = clampf(shape.beat_lead_in, 0.0, beat_span)
	var beats: Dictionary = {}
	for entry in entries:
		beats[entry.beat_index] = true
	var beat_total: int = maxi(1, beats.size()) if cadence == ScheduleEntry.Cadence.BEAT \
			else maxi(1, entries.size())
	# The cast's largest landing, which is what every other one is reported as
	# a fraction of. Authored `amount`, not `effective_amount`: magnitude is a
	# visual's read on "how big is this blow within this cast", and mitigation
	# is the defender's story, told by the floater.
	var peak := 0.0
	for entry in entries:
		peak = maxf(peak, _entry_amount(entry))
	for i in entries.size():
		var entry := entries[i]
		entry.index = i
		if cadence != ScheduleEntry.Cadence.BEAT:
			entry.beat_index = i
		entry.beat_count = beat_total
		entry.magnitude = 0.0 if peak <= 0.0 else clampf(_entry_amount(entry) / peak, 0.0, 1.0)
		match cadence:
			ScheduleEntry.Cadence.BEAT:
				entry.arrive_at = lead + entry.structural_key * beat_span
				entry.launch_at = entry.arrive_at - lead
			ScheduleEntry.Cadence.RAMP:
				entry.launch_at = shape.volley_draw_time \
						+ entry.structural_key * shape.volley_stagger_span
				entry.arrive_at = entry.launch_at + shape.volley_flight_time
			ScheduleEntry.Cadence.SWING:
				entry.arrive_at = entry.structural_key * shape.swing_duration
				entry.launch_at = 0.0
			_:
				entry.arrive_at = entry.structural_key
				entry.launch_at = entry.arrive_at
		entry.launch_at *= rate
		entry.arrive_at *= rate
	# `is_terminal` for the modes with no walk to end: the last thing to land.
	if cadence != ScheduleEntry.Cadence.BEAT and not entries.is_empty():
		entries[entries.size() - 1].is_terminal = true


## [b]The compiler is the sole writer of [member HitInstance.arrival_time][/b]
## (D1) and of [member HitInstance.schedule_index] (D2). The field survived
## rather than being deleted because the alternative — a per-hit dictionary
## lookup inside the applier's landing loop and [CameraDirector]'s span walk —
## costs a hot-loop indirection for zero behavioural gain. What changed is not
## the field, it is WHO writes it.
func _write_back() -> void:
	for entry in entries:
		for hit in entry.hits:
			if hit == null:
				continue
			hit.schedule_index = entry.index
			hit.arrival_time = entry.arrive_at


static func _entry_amount(entry: ScheduleEntry) -> float:
	var total := 0.0
	for hit in entry.hits:
		if hit != null:
			total += absf(hit.amount)
	return total
