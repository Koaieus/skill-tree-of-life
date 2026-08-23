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
##   2. [b]WORLD[/b] — after applying, do the two worlds agree? That is
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
## [b]Land-time — NOT compared.[/b] [constant AttackRecord.KEY_HIT_AMOUNT]
## (post-[Mitigation] effective damage), [constant AttackRecord.KEY_HIT_KIND]
## (reclassified to HEAL on a `min_damage_taken` underflow), the HP-bar
## numbers, the forced-dealloc sets, and the [constant
## AttackRecord.FLAG_GATED] bit. [AttackRecord]'s class note is explicit that a
## client CANNOT re-derive these — mitigation is read node-locally at land
## time, an earlier beat's cascade changes what a later beat lands on, and a
## fogged target may not be held at all. Diffing them would report 100%
## divergence for structural reasons and the number would mean nothing.
##
## [b]So a clean RESOLVE column does not say "lockstep needs no record".[/b] It
## says the hit SET, ORDER and TIMELINE are reproducible, which is precisely
## the half #530 was a prerequisite for. Read the report's own footer, which
## says this too — the owner is making a model decision off it.
const RESOLVE_KEYS: Array[String] = [
	AttackRecord.KEY_SEED,
	AttackRecord.KEY_AP,
	AttackRecord.KEY_MANA,
	AttackRecord.KEY_HIT_TARGET,
	AttackRecord.KEY_HIT_ORIGIN,
	AttackRecord.KEY_HIT_ATTACKER,
	AttackRecord.KEY_HIT_ARRIVAL,
	AttackRecord.KEY_HIT_CRIT_TIER,
	AttackRecord.KEY_EVENT_BEAT,
	AttackRecord.KEY_EVENT_VERB,
	AttackRecord.KEY_EVENT_ORIGIN,
	AttackRecord.KEY_EVENT_TARGET,
	AttackRecord.KEY_EVENT_PRED,
	AttackRecord.KEY_EVENT_HITS,
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
## Which record fields have ever disagreed, and how often — the bisection hint
## the issue asks for, since "WHICH command diverged" is the known-painful part
## of lockstep debugging. field -> count.
var _resolve_fields: Dictionary = {}
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
	if not world_settled:
		_bump(_resolve, attack.type_tag(), "deferred")
	if attack.record.is_empty():
		# An INITIATE, not a replay — there is no host result to compare
		# against. Cannot happen on today's one-directional link, but the
		# intent channel (#463) will make it possible.
		_bump(_resolve, attack.type_tag(), "unavailable")
		return
	var diverging := _compare_resolve(attack)
	if diverging.is_empty():
		_bump(_resolve, attack.type_tag(), "agreed")
		# Counted alongside the verdict, because "5 attacks, 0 diverged" is
		# VACUOUS if all five resolved to zero landings — two empty arrays match
		# trivially and the row would read clean while proving nothing. The
		# landings number is what makes the column an actual measurement.
		_add(_resolve, attack.type_tag(), "landings",
				maxi(0, _length_of(attack.record.get(AttackRecord.KEY_HIT_TARGET))))
		return
	if diverging.size() == 1 and diverging[0] == UNRESOLVABLE:
		_bump(_resolve, attack.type_tag(), "unavailable")
		_note("probe: launch_attack NOT RE-RESOLVABLE here (plan did not rebuild)")
		return
	_bump(_resolve, attack.type_tag(), "diverged")
	for field in diverging:
		_resolve_fields[field] = int(_resolve_fields.get(field, 0)) + 1
	_note("probe: ✗ launch_attack RESOLVE diverged on %s" % ", ".join(diverging))


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
	if not _divergences.is_empty():
		lines.append("    first divergences:")
		for line in _divergences:
			lines.append("      %s" % line)

	lines.append("")
	lines.append("  SCOPE — the RESOLVE column covers the seed, the AP/mana costs,")
	lines.append("  and per landing its target/origin/attacker/arrival/crit tier plus the")
	lines.append("  whole propagation timeline. It deliberately does NOT cover land-time")
	lines.append("  arithmetic (effective damage, HP numbers, the reclassified hit kind,")
	lines.append("  the gated bit, forced deallocations) — AttackRecord's own contract is")
	lines.append("  that a peer cannot re-derive those. `skipped` is a command CommandLink")
	lines.append("  chose not to compare (queue non-empty / superseded), not a pass.")
	lines.append("  `landings re-derived` is the RESOLVE column's real size — an attack")
	lines.append("  that resolved to nothing agrees trivially and proves nothing.")
	lines.append("  `deferred` re-resolved while an earlier command was still draining, so")
	lines.append("  it agreed against a world that had not settled — weaker evidence, not none.")
	lines.append("─────────────────────────────────────────────────")
	return "\n".join(lines)


## Re-resolve [param command] locally and return the record fields that came
## out different. Empty means agreement; `["<unresolvable>"]` means the peer
## could not even rebuild the plan, which is a distinct outcome from disagreeing
## about one.
func _compare_resolve(command: LaunchAttackCommand) -> Array[String]:
	if graph == null:
		return [UNRESOLVABLE] as Array[String]
	var plan := AttackPlanCodec.from_dict(command.plan, graph)
	if plan == null:
		return [UNRESOLVABLE] as Array[String]
	# Stamped BEFORE resolving, mirroring `BattleSystem._compute_record` —
	# the seed is an INPUT to the resolution, and skipping this makes every
	# crit tier disagree trivially.
	plan.resolve_seed = command.resolve_seed
	var outcome := plan.resolve()
	if outcome == null:
		return [UNRESOLVABLE] as Array[String]
	# Re-encoded through the SAME capture the host used rather than a hand-
	# rolled comparison of live objects: one implementation of "what a record
	# is", never a second. The land-time fields are no longer zeroes here —
	# since #536 a resolve lands in its shadow world, so this probe now holds
	# very nearly the host's whole record. They stay out of RESOLVE_KEYS anyway:
	# the question this asks is what a peer could have DERIVED, and a shadow
	# built from a fogged peer's partial world is not evidence about that.
	var mine := AttackRecord.capture(outcome, graph)
	var diverging := diverging_fields(mine, command.record)
	if not diverging.is_empty():
		_record_divergence(command, mine, command.record, diverging)
	return diverging


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


## Exact equality, on purpose — "close enough" is not a determinism answer.
## Godot compares `Packed*Array` and nested `Array` elementwise, so this is a
## deep compare for every shape [method AttackRecord.capture] produces.
static func _same(a: Variant, b: Variant) -> bool:
	if a == null or b == null:
		return a == null and b == null
	return a == b


## The `FLAG_CRIT` bit of every hit, with `FLAG_GATED` masked off.
static func _crit_bits(flags: Variant) -> PackedByteArray:
	var out := PackedByteArray()
	if flags is PackedByteArray:
		for f in (flags as PackedByteArray):
			out.append(f & AttackRecord.FLAG_CRIT)
	return out


## One human-readable line per divergence, naming WHICH landing count and
## which fields — the bisection hint, since a bare "attacks diverge" sends you
## back to a debugger with nothing.
func _record_divergence(command: LaunchAttackCommand, mine: Dictionary,
		theirs: Dictionary, fields: Array[String]) -> void:
	if _divergences.size() >= MAX_RECORDED_DIVERGENCES:
		return
	var my_hits: int = _length_of(mine.get(AttackRecord.KEY_HIT_TARGET))
	var their_hits: int = _length_of(theirs.get(AttackRecord.KEY_HIT_TARGET))
	_divergences.append("seed %d, mode %s: %d hits here vs %d there — %s"
			% [command.resolve_seed, command.plan.get("mode", "?"),
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
