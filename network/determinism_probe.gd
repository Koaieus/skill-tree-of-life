@tool
class_name DeterminismProbe
extends Node

## #529: measure whether a peer could have DERIVED what the host sent it,
## instead of arguing about it. This class produces a NUMBER, not a feature —
## the input to the owner's choice between #463's confirm-down model and
## lockstep + snapshot recovery.
##
## [b]It mutates nothing and changes nothing about what the client applies.[/b]
## [CommandLink] still submits the host's version through the same
## [CommandApplier]; this only watches, tallies, and prints. It is
## [member enabled]-gated and OFF by default, so a normal run pays one branch
## per command.
##
## [b]Two independent questions, tallied separately.[/b]
##
##   1. [b]RESOLVE[/b] — could this peer have derived the host's result from
##      the same inputs? Only [LaunchAttackCommand] can even be asked: it is
##      the one verb whose result rides the wire (an [AttackRecord]) alongside
##      the inputs that produced it (the plan + [member
##      LaunchAttackCommand.resolve_seed]). Every other verb carries intent
##      only, so "re-resolving" it is just applying it, and question 2 is the
##      whole answer.
##   2. [b]LAND[/b] — could this peer have derived the host's LAND-TIME
##      arithmetic: the post-mitigation numbers, the HP bars, the reclassified
##      hit kind, the gated bit, and the forced-dealloc cascades? This column
##      was added 2026-08-24 and it is the one the model decision actually
##      turns on — see [constant LAND_KEYS].
##   3. [b]WORLD[/b] — after applying, do the two worlds agree? That is
##      [method WorldFingerprint.compute], which [CommandLink] already
##      compares; the probe only attributes each verdict to the command type
##      that produced it, because "3 mismatches out of 412, all launch_attack"
##      is the useful output and a single boolean is not.
##
## [b]The denominator is reported, not assumed.[/b] [method
## CommandLink._on_remote_command] deliberately SKIPS the fingerprint compare
## while the queue is non-empty or a newer command has superseded it (a
## spurious ✗ poisons the only diagnostic the harness has). Those commands are
## tallied as `skipped`, not silently dropped from the count — a clean
## "0 diverged" read is worthless if a third of the commands were never
## compared, and that ratio is itself a finding.
##
## See `docs/domain/determinism-probe.md`.

## What half of a landing a peer could plausibly re-derive, and what it could
## not. Straight off [method AttackRecord.capture]'s own field notes, traced
## rather than guessed:
##
## [b]Resolve-stage — compared.[/b] The seed, the costs, and per landing its
## target / origin / attacker / arrival time / crit tier, plus the whole
## propagation timeline (beats, verbs, edges, and which hits each event
## carries). These are what [method AttackPlan.resolve] returns, and #530's
## stable hitscan sort is what makes the melee half of it reproducible at all —
## without that commit these numbers would be noise.
##
## [b]Land-time — compared SEPARATELY, in its own column.[/b] [constant
## AttackRecord.KEY_HIT_AMOUNT]
## (post-[Mitigation] effective damage), [constant AttackRecord.KEY_HIT_KIND]
## (reclassified to HEAL on a `min_damage_taken` underflow), the HP-bar
## numbers, the forced-dealloc sets, and the [constant
## AttackRecord.FLAG_GATED] bit. [AttackRecord]'s class note says a client
## CANNOT re-derive these, and under a FOGGED peer that is true by construction
## — mitigation is read node-locally at land time and a fogged target may not
## be held at all. But no fog exists today: every peer holds the full world, so
## the question "could it have derived them" is answerable, and #536 made the
## answer available for free (a resolve lands in its own shadow world, so this
## probe already holds very nearly the host's whole record).
##
## [b]So a clean RESOLVE column does not say "lockstep needs no record".[/b] It
## says the hit SET, ORDER and TIMELINE are reproducible, which is precisely
## the half #530 was a prerequisite for — and it is the half the confirmed
## record was never needed for. The LAND column is the half lockstep would
## stand or fall on, which is why it stopped being skipped.
const RESOLVE_KEYS: Array[String] = [
	AttackRecord.KEY_SEED,
	AttackRecord.KEY_AP,
	AttackRecord.KEY_MANA,
	AttackRecord.KEY_HIT_TARGET,
	AttackRecord.KEY_HIT_ORIGIN,
	AttackRecord.KEY_HIT_ATTACKER,
	# #543: the STRUCTURAL key and its cadence, not the seconds they compile
	# into. Seconds left the wire because tempo is a per-peer setting — which
	# is exactly why they could never have been measured here as agreement.
	AttackRecord.KEY_HIT_STRUCT,
	AttackRecord.KEY_CADENCE,
	AttackRecord.KEY_TEMPO,
	AttackRecord.KEY_HIT_CRIT_TIER,
	AttackRecord.KEY_EVENT_BEAT,
	AttackRecord.KEY_EVENT_VISIT,
	AttackRecord.KEY_EVENT_TERMINAL,
	AttackRecord.KEY_EVENT_VERB,
	AttackRecord.KEY_EVENT_ORIGIN,
	AttackRecord.KEY_EVENT_TARGET,
	AttackRecord.KEY_EVENT_PRED,
	AttackRecord.KEY_EVENT_HITS,
]

## The land-time half of a record: what a peer computes only by reading its own
## world at the moment each landing arrives. Every key [method
## AttackRecord.capture] writes that is NOT in [constant RESOLVE_KEYS], plus the
## [constant AttackRecord.FLAG_GATED] bit, which shares a byte with the crit bit
## and is split off in [method diverging_land_fields].
##
## [b]This column means something ONLY while every peer holds the full
## world.[/b] It is a measurement of re-derivability, not a licence: under the
## deferred fog-filtered model the inputs are withheld on purpose, so a clean
## LAND column today says nothing about a fogged tomorrow. Read it as "lockstep
## COULD carry these", never as "the record is unnecessary".
const LAND_KEYS: Array[String] = [
	AttackRecord.KEY_HIT_KIND,
	AttackRecord.KEY_HIT_AMOUNT,
	AttackRecord.KEY_HIT_HP_BEFORE,
	AttackRecord.KEY_HIT_HP_AFTER,
	AttackRecord.KEY_HIT_HP_MAX,
	AttackRecord.KEY_HIT_POP,
	AttackRecord.KEY_DEALLOC_COUNT,
	AttackRecord.KEY_DEALLOC_NODE,
	AttackRecord.KEY_DEALLOC_LEVEL,
	AttackRecord.KEY_DEALLOC_WOUND,
	AttackRecord.KEY_DEALLOC_CHIP,
	AttackRecord.KEY_DEALLOC_LABEL_COUNT,
	AttackRecord.KEY_DEALLOC_LABEL,
]

## Verbs whose result is a HOST-ONLY ROLL by design, so a peer disagreeing
## about it is not a determinism failure — it is the model working.
## `.claude/rules/multiplayer-sync.md` carves loot out explicitly ("host-only
## rolls (loot) are exempt"), and [LootRoundCommand] carries what was granted
## BY VALUE for exactly that reason. Tallied in its own column so a real
## mismatch is never buried under an expected one.
const EXEMPT_TAGS: Array[StringName] = [LootRoundCommand.TAG]

## Sentinel for "this peer could not even rebuild the plan" — a THIRD outcome,
## not a divergence. Reporting it as one would blame the model for a harness
## gap; reporting it as agreement would hide a peer that cannot participate in
## lockstep at all.
const UNRESOLVABLE := "<unresolvable>"

## A tally line was appended — the harness prints these; nothing depends on
## their text.
signal logged(line: String)

## Off by default, on purpose (#529): the probe re-resolves a whole attack per
## received command, which is real work no normal run should pay for. The
## harness flips it from `--probe`.
@export var enabled: bool = false

## Needed to rebuild a received [AttackPlan] and to re-encode the outcome it
## resolves to. The same graph [CommandLink] holds; wired by the scene.
@export var graph: Graph

## tag -> {"agreed": int, "diverged": int, "skipped": int, "exempt": int}
var _world: Dictionary = {}
## tag -> {"agreed": int, "diverged": int, "unavailable": int}
var _resolve: Dictionary = {}
## Same shape as [member _resolve], for the land-time half. Kept a SEPARATE
## book rather than extra buckets on the same row so the RESOLVE numbers stay
## exactly the quantity #529 already reported twice — a column that changed
## meaning between runs is not a measurement.
var _land: Dictionary = {}
## Which record fields have ever disagreed, and how often — the bisection hint
## the issue asks for, since "WHICH command diverged" is the known-painful part
## of lockstep debugging. field -> count.
var _resolve_fields: Dictionary = {}
## The same bisection hint for the land-time half. field -> count.
var _land_fields: Dictionary = {}
## One line per divergence, capped so a pathological run cannot eat memory.
var _divergences: Array[String] = []

const MAX_RECORDED_DIVERGENCES := 64


## Re-derive [param command]'s result locally and compare it against the one
## the host recorded. Call this BEFORE the command is applied — the host
## resolved against the pre-command world, so a probe that runs after the
## mutation is comparing against the wrong state.
##
## Mutates nothing REAL: [method AttackPlan.resolve] lands its outcome in a
## throwaway shadow world (#536), the plan built here is local and never
## assigned to [member BattleSystem.attack_plan], and the outcome is encoded
## and thrown away.
## [param world_settled] is whether this peer's applier was IDLE when the
## command arrived. The WORLD compare has a guard for exactly this (a command
## that arrives mid-drain is tallied `skipped`, because the fingerprint would be
## read off an unsettled world); the RESOLVE compare cannot use that guard,
## because the whole point is to re-resolve BEFORE applying. So it is reported
## instead: a `deferred` agreement re-resolved against a world with another
## command still draining through it, and is weaker evidence than a settled one.
## Counting them separately is the difference between a claim the owner can
## weigh and one that overstates itself.
func observe_before_apply(command: Command, world_settled: bool = true) -> void:
	if not enabled or command == null:
		return
	var attack := command as LaunchAttackCommand
	if attack == null:
		return
	var tag := attack.type_tag()
	if not world_settled:
		_bump(_resolve, tag, "deferred")
	if attack.record.is_empty():
		# An INITIATE, not a replay — there is no host result to compare
		# against. Cannot happen on today's one-directional link, but the
		# intent channel (#463) will make it possible.
		_bump(_resolve, tag, "unavailable")
		_bump(_land, tag, "unavailable")
		return
	# ONE re-derivation, two questions asked of it. Resolving twice would double
	# the probe's cost and — worse — leave open the possibility that the two
	# columns were answered against different worlds.
	var mine := _rederive(attack)
	if mine.is_empty():
		_bump(_resolve, tag, "unavailable")
		_bump(_land, tag, "unavailable")
		_note("probe: launch_attack NOT RE-RESOLVABLE here (plan did not rebuild)")
		return
	var landings: int = maxi(0, _length_of(attack.record.get(AttackRecord.KEY_HIT_TARGET)))

	var diverging := diverging_fields(mine, attack.record)
	if diverging.is_empty():
		_bump(_resolve, tag, "agreed")
		# Counted alongside the verdict, because "5 attacks, 0 diverged" is
		# VACUOUS if all five resolved to zero landings — two empty arrays match
		# trivially and the row would read clean while proving nothing. The
		# landings number is what makes the column an actual measurement.
		_add(_resolve, tag, "landings", landings)
	else:
		_bump(_resolve, tag, "diverged")
		for field in diverging:
			_resolve_fields[field] = int(_resolve_fields.get(field, 0)) + 1
		_record_divergence("RESOLVE", attack, mine, attack.record, diverging)
		_note("probe: ✗ launch_attack RESOLVE diverged on %s" % ", ".join(diverging))

	# The land-time half is bucketed by SETTLEDNESS, not merely annotated with
	# it. Land-time arithmetic reads this peer's live world — mitigation off the
	# target node, HP off its pool — so a re-derivation taken while an earlier
	# command is still draining is being asked about a world that is not the one
	# the host resolved against. That verdict is not evidence in either
	# direction, and folding it into the same bucket would let expected noise
	# masquerade as the finding the owner is deciding on.
	var land_diverging := diverging_land_fields(mine, attack.record)
	if land_diverging.is_empty():
		_bump(_land, tag, "agreed" if world_settled else "soft_agreed")
		if world_settled:
			_add(_land, tag, "landings", landings)
		return
	_bump(_land, tag, "diverged" if world_settled else "soft_diverged")
	if not world_settled:
		return
	for field in land_diverging:
		_land_fields[field] = int(_land_fields.get(field, 0)) + 1
	_record_divergence("LAND", attack, mine, attack.record, land_diverging)
	_note("probe: ✗ launch_attack LAND diverged on %s" % ", ".join(land_diverging))


## [CommandLink]'s post-apply fingerprint verdict, attributed to the command
## that produced it.
func observe_world(command: Command, agrees: bool) -> void:
	if not enabled or command == null:
		return
	var tag := command.type_tag()
	if tag in EXEMPT_TAGS:
		_bump(_world, tag, "exempt")
		return
	_bump(_world, tag, "agreed" if agrees else "diverged")


## [CommandLink] chose not to compare this one — a command still in the queue,
## or superseded by a newer arrival. Counted so the denominator is honest.
func observe_skipped(command: Command) -> void:
	if not enabled or command == null:
		return
	_bump(_world, command.type_tag(), "skipped")


## One command type's world tally — `agreed` / `diverged` / `skipped` /
## `exempt`, all four always present. A copy, so a caller cannot bump the book
## by holding it. For tests and for anything that wants the numbers rather than
## the formatted table.
func world_tally(tag: StringName) -> Dictionary:
	var row: Dictionary = _world.get(tag, {})
	return {
		"agreed": int(row.get("agreed", 0)),
		"diverged": int(row.get("diverged", 0)),
		"skipped": int(row.get("skipped", 0)),
		"exempt": int(row.get("exempt", 0)),
	}


## One command type's resolve tally — `agreed` / `diverged` / `unavailable`,
## plus `landings`, the number of individual hits the agreements actually
## covered. Same copy-out contract as [method world_tally].
func resolve_tally(tag: StringName) -> Dictionary:
	var row: Dictionary = _resolve.get(tag, {})
	return {
		"agreed": int(row.get("agreed", 0)),
		"diverged": int(row.get("diverged", 0)),
		"unavailable": int(row.get("unavailable", 0)),
		"landings": int(row.get("landings", 0)),
		"deferred": int(row.get("deferred", 0)),
	}


## One command type's land-time tally. `agreed` / `diverged` are the SETTLED
## verdicts — the only ones that are evidence; `soft_*` are the same verdicts
## taken while an earlier command was still draining. Same copy-out contract as
## [method world_tally].
func land_tally(tag: StringName) -> Dictionary:
	var row: Dictionary = _land.get(tag, {})
	return {
		"agreed": int(row.get("agreed", 0)),
		"diverged": int(row.get("diverged", 0)),
		"soft_agreed": int(row.get("soft_agreed", 0)),
		"soft_diverged": int(row.get("soft_diverged", 0)),
		"unavailable": int(row.get("unavailable", 0)),
		"landings": int(row.get("landings", 0)),
	}


## The whole readout, ready to print. Per command type, because "3 mismatches
## out of 412, all launch_attack" is the answer and a single boolean is not.
func report() -> String:
	var lines: Array[String] = []
	lines.append("── determinism probe (#529) ─────────────────────")
	if not enabled:
		lines.append("  probe was never enabled — nothing measured.")
		return "\n".join(lines)

	lines.append("  WORLD — do the two worlds agree after applying?")
	lines.append("    %-22s %6s %8s %8s %7s" % ["command", "ok", "DIVERGED", "skipped", "exempt"])
	var world_totals := {"agreed": 0, "diverged": 0, "skipped": 0, "exempt": 0}
	for tag in _sorted_tags(_world):
		var row: Dictionary = _world[tag]
		lines.append("    %-22s %6d %8d %8d %7d" % [tag,
				int(row.get("agreed", 0)), int(row.get("diverged", 0)),
				int(row.get("skipped", 0)), int(row.get("exempt", 0))])
		for key in world_totals:
			world_totals[key] = int(world_totals[key]) + int(row.get(key, 0))
	var world_seen: int = int(world_totals["agreed"]) + int(world_totals["diverged"]) \
			+ int(world_totals["skipped"]) + int(world_totals["exempt"])
	lines.append("    %-22s %6d %8d %8d %7d   (of %d received)" % ["TOTAL",
			int(world_totals["agreed"]), int(world_totals["diverged"]),
			int(world_totals["skipped"]), int(world_totals["exempt"]), world_seen])

	lines.append("")
	lines.append("  RESOLVE — could this peer have DERIVED the host's result?")
	if _resolve.is_empty():
		lines.append("    no launch_attack crossed; nothing was re-resolvable.")
	else:
		lines.append("    %-22s %6s %8s %12s %19s %9s" % ["command", "ok", "DIVERGED",
				"unavailable", "landings re-derived", "deferred"])
		for tag in _sorted_tags(_resolve):
			var row: Dictionary = _resolve[tag]
			lines.append("    %-22s %6d %8d %12d %19d %9d" % [tag,
					int(row.get("agreed", 0)), int(row.get("diverged", 0)),
					int(row.get("unavailable", 0)), int(row.get("landings", 0)),
					int(row.get("deferred", 0))])
	if not _resolve_fields.is_empty():
		lines.append("    fields that disagreed:")
		var fields: Array = _resolve_fields.keys()
		fields.sort()
		for field in fields:
			lines.append("      %-10s ×%d" % [field, int(_resolve_fields[field])])
	lines.append("")
	lines.append("  LAND — could this peer have derived the host's LAND-TIME arithmetic?")
	lines.append("         (effective damage, HP bars, hit kind, gated bit, forced deallocs)")
	if _land.is_empty():
		lines.append("    no launch_attack crossed; nothing was re-resolvable.")
	else:
		lines.append("    %-22s %6s %8s %8s %8s %12s %9s" % ["command", "ok", "DIVERGED",
				"ok(uns)", "div(uns)", "unavailable", "landings"])
		for tag in _sorted_tags(_land):
			var row: Dictionary = _land[tag]
			lines.append("    %-22s %6d %8d %8d %8d %12d %9d" % [tag,
					int(row.get("agreed", 0)), int(row.get("diverged", 0)),
					int(row.get("soft_agreed", 0)), int(row.get("soft_diverged", 0)),
					int(row.get("unavailable", 0)), int(row.get("landings", 0))])
	if not _land_fields.is_empty():
		lines.append("    land-time fields that disagreed:")
		var land_fields: Array = _land_fields.keys()
		land_fields.sort()
		for field in land_fields:
			lines.append("      %-10s ×%d" % [field, int(_land_fields[field])])

	if not _divergences.is_empty():
		lines.append("")
		lines.append("    first divergences:")
		for line in _divergences:
			lines.append("      %s" % line)

	lines.append("")
	lines.append("  SCOPE — RESOLVE covers the seed, the AP/mana costs, and per landing its")
	lines.append("  target/origin/attacker/arrival/crit tier plus the whole propagation")
	lines.append("  timeline: everything the plan and the seed determine. LAND covers the")
	lines.append("  rest — what a peer computes by reading its OWN world as each landing")
	lines.append("  arrives. Together they are the whole AttackRecord.")
	lines.append("  LAND is answerable only because every peer holds the full world today.")
	lines.append("  A clean LAND column says lockstep COULD carry these; it does NOT say the")
	lines.append("  record is unnecessary — under fog-filtered state the inputs are withheld")
	lines.append("  on purpose and a peer cannot derive them by construction.")
	lines.append("  `ok(uns)` / `div(uns)` are verdicts taken while an earlier command was")
	lines.append("  still draining, i.e. against a world that had not settled. They are NOT")
	lines.append("  evidence in either direction and are bucketed apart for that reason.")
	lines.append("  `skipped` is a command CommandLink chose not to compare (queue")
	lines.append("  non-empty), not a pass. `landings` is a column's real size — an attack")
	lines.append("  that resolved to nothing agrees trivially and proves nothing.")
	lines.append("  `deferred` (RESOLVE) is that column's unsettled count, annotated rather")
	lines.append("  than bucketed: a plan+seed resolution does not read the live world.")
	lines.append("─────────────────────────────────────────────────")
	return "\n".join(lines)


## Re-resolve [param command] locally and return THIS peer's version of the
## record. An empty dictionary means the peer could not even rebuild the plan —
## a distinct outcome from disagreeing about one, and the caller reports it as
## `unavailable` rather than as a divergence.
##
## Returns the whole record, not a verdict, because two independent questions
## are asked of it ([constant RESOLVE_KEYS] and [constant LAND_KEYS]) and both
## must be answered against the SAME re-derivation.
func _rederive(command: LaunchAttackCommand) -> Dictionary:
	if graph == null:
		return {}
	var plan := AttackPlanCodec.from_dict(command.plan, graph)
	if plan == null:
		return {}
	# Stamped BEFORE resolving, mirroring `BattleSystem._compute_record` —
	# the seed is an INPUT to the resolution, and skipping this makes every
	# crit tier disagree trivially.
	plan.resolve_seed = command.resolve_seed
	var outcome := plan.resolve()
	if outcome == null:
		return {}
	# Re-encoded through the SAME capture the host used rather than a hand-
	# rolled comparison of live objects: one implementation of "what a record
	# is", never a second. Since #536 the resolve lands in its own shadow world,
	# so the land-time fields are real numbers here rather than zeroes — which
	# is what makes [constant LAND_KEYS] answerable at all.
	return AttackRecord.capture(outcome, graph)


## Which RESOLVE-stage fields of two records disagree. Pure and static, so the
## partition this whole issue rests on is testable without standing up an
## attack — and so the answer cannot quietly depend on probe state.
##
## Empty means "this peer could have derived the host's result", for the half
## of the record a peer is expected to be able to derive. See [constant
## RESOLVE_KEYS] for which half that is and why.
static func diverging_fields(mine: Dictionary, theirs: Dictionary) -> Array[String]:
	var diverging: Array[String] = []
	for key in RESOLVE_KEYS:
		if not _same(mine.get(key), theirs.get(key)):
			diverging.append(key)
	# The crit BIT only. `FLAG_GATED` shares this field and is decided at land
	# time (#503), so comparing the raw byte would report a divergence the
	# model expects.
	if _crit_bits(mine.get(AttackRecord.KEY_HIT_FLAGS)) \
			!= _crit_bits(theirs.get(AttackRecord.KEY_HIT_FLAGS)):
		diverging.append("h_crit_flag")
	return diverging


## Which LAND-time fields of two records disagree — the half a peer computes by
## reading its own world as each landing arrives, rather than from the plan and
## the seed. Static and pure for the same reason [method diverging_fields] is.
##
## Empty means "holding the same world, this peer would have computed the same
## damage, the same HP bars and the same cascades". That is the question
## lockstep stands on; it is NOT a claim that the record is redundant, because
## under fog the inputs are withheld by design. See [constant LAND_KEYS].
static func diverging_land_fields(mine: Dictionary, theirs: Dictionary) -> Array[String]:
	var diverging: Array[String] = []
	for key in LAND_KEYS:
		if not _same(mine.get(key), theirs.get(key)):
			diverging.append(key)
	# The gated BIT only — the crit bit shares this byte and is a seeded roll,
	# so it belongs to RESOLVE. Splitting the byte is why neither column can
	# just compare [constant AttackRecord.KEY_HIT_FLAGS] whole.
	if _bits(mine.get(AttackRecord.KEY_HIT_FLAGS), AttackRecord.FLAG_GATED) \
			!= _bits(theirs.get(AttackRecord.KEY_HIT_FLAGS), AttackRecord.FLAG_GATED):
		diverging.append("h_gated_flag")
	return diverging


## Exact equality, on purpose — "close enough" is not a determinism answer.
## Godot compares `Packed*Array` and nested `Array` elementwise, so this is a
## deep compare for every shape [method AttackRecord.capture] produces.
static func _same(a: Variant, b: Variant) -> bool:
	if a == null or b == null:
		return a == null and b == null
	return a == b


## The `FLAG_CRIT` bit of every hit, with `FLAG_GATED` masked off.
static func _crit_bits(flags: Variant) -> PackedByteArray:
	return _bits(flags, AttackRecord.FLAG_CRIT)


## One bit of every hit's flag byte, isolated. The two columns own different
## bits of the same field, so both mask through here rather than each carrying
## its own loop.
static func _bits(flags: Variant, mask: int) -> PackedByteArray:
	var out := PackedByteArray()
	if flags is PackedByteArray:
		for f in (flags as PackedByteArray):
			out.append(f & mask)
	return out


## One human-readable line per divergence, naming WHICH landing count and
## which fields — the bisection hint, since a bare "attacks diverge" sends you
## back to a debugger with nothing.
func _record_divergence(stage: String, command: LaunchAttackCommand, mine: Dictionary,
		theirs: Dictionary, fields: Array[String]) -> void:
	if _divergences.size() >= MAX_RECORDED_DIVERGENCES:
		return
	var my_hits: int = _length_of(mine.get(AttackRecord.KEY_HIT_TARGET))
	var their_hits: int = _length_of(theirs.get(AttackRecord.KEY_HIT_TARGET))
	_divergences.append("%s — seed %d, mode %s: %d hits here vs %d there — %s"
			% [stage, command.resolve_seed, command.plan.get("mode", "?"),
					my_hits, their_hits, ", ".join(fields)])


func _length_of(packed: Variant) -> int:
	if packed is PackedInt32Array:
		return (packed as PackedInt32Array).size()
	return -1


func _bump(book: Dictionary, tag: StringName, bucket: String) -> void:
	_add(book, tag, bucket, 1)


func _add(book: Dictionary, tag: StringName, bucket: String, amount: int) -> void:
	if not book.has(tag):
		book[tag] = {}
	var row: Dictionary = book[tag]
	row[bucket] = int(row.get(bucket, 0)) + amount


func _sorted_tags(book: Dictionary) -> Array:
	var tags: Array = book.keys()
	tags.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return tags


func _note(line: String) -> void:
	logged.emit(line)
