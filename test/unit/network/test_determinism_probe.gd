extends GutTest

## #529's probe. The load-bearing thing here is the PARTITION — which fields of
## an [AttackRecord] a peer is expected to be able to re-derive and which it is
## not. Get that wrong in either direction and the number the owner picks a sync
## model with is meaningless: too wide and it reports 100% divergence for
## structural reasons, too narrow and a real desync passes clean.
##
## [method DeterminismProbe.diverging_fields] is static and pure precisely so
## this can be pinned with two dictionaries instead of two worlds and a live
## attack — the end-to-end path (record captured on a host, compared on a
## mirror) is already covered by `test_attack_record_replay.gd`.

const _GRAPH_SCENE := preload("res://graph/graph.tscn")


## A minimal record with every array of length 2, so a mutation to any one of
## them is detectable and the parallel-array slicing stays consistent.
func _record() -> Dictionary:
	return {
		AttackRecord.KEY_SEED: 12345,
		AttackRecord.KEY_AP: 2,
		AttackRecord.KEY_MANA: 7,
		AttackRecord.KEY_HIT_KIND: PackedByteArray([0, 0]),
		AttackRecord.KEY_HIT_AMOUNT: PackedFloat64Array([11.5, 3.25]),
		AttackRecord.KEY_HIT_TARGET: PackedInt32Array([4, 9]),
		AttackRecord.KEY_HIT_ORIGIN: PackedInt32Array([1, 1]),
		AttackRecord.KEY_HIT_ATTACKER: PackedInt32Array([2, 2]),
		AttackRecord.KEY_HIT_ARRIVAL: PackedFloat64Array([0.0, 0.4]),
		AttackRecord.KEY_HIT_FLAGS: PackedByteArray([AttackRecord.FLAG_CRIT, 0]),
		AttackRecord.KEY_HIT_CRIT_TIER: PackedInt32Array([1, 0]),
		AttackRecord.KEY_HIT_HP_BEFORE: PackedFloat64Array([20.0, 8.0]),
		AttackRecord.KEY_HIT_HP_AFTER: PackedFloat64Array([8.5, 4.75]),
		AttackRecord.KEY_HIT_HP_MAX: PackedFloat64Array([20.0, 8.0]),
		AttackRecord.KEY_DEALLOC_COUNT: PackedInt32Array([0, 1]),
		AttackRecord.KEY_DEALLOC_NODE: PackedInt32Array([9]),
		AttackRecord.KEY_DEALLOC_LEVEL: PackedInt32Array([3]),
		AttackRecord.KEY_DEALLOC_WOUND: PackedInt32Array([1]),
		AttackRecord.KEY_DEALLOC_CHIP: PackedFloat64Array([2.0]),
		AttackRecord.KEY_DEALLOC_LABEL_COUNT: PackedInt32Array([0]),
		AttackRecord.KEY_DEALLOC_LABEL: PackedStringArray(),
		AttackRecord.KEY_EVENT_BEAT: PackedInt32Array([0, 1]),
		AttackRecord.KEY_EVENT_VERB: PackedByteArray([0, 0]),
		AttackRecord.KEY_EVENT_ORIGIN: PackedInt32Array([1, 4]),
		AttackRecord.KEY_EVENT_TARGET: PackedInt32Array([4, 9]),
		AttackRecord.KEY_EVENT_PRED: PackedInt32Array([0, 1]),
		AttackRecord.KEY_EVENT_HITS: [PackedInt32Array([0]), PackedInt32Array([1])],
	}


func test_an_identical_record_diverges_on_nothing() -> void:
	assert_eq(DeterminismProbe.diverging_fields(_record(), _record()), [] as Array[String])


## The whole reason the probe is not "diff the record": [AttackRecord]'s own
## contract is that a peer CANNOT re-derive these — mitigation is read
## node-locally at land time, an earlier beat's cascade changes what a later
## beat lands on, and a fogged target may not be held at all. Counting them
## would report divergence that the sync model expects and the number would say
## nothing about determinism.
func test_land_time_arithmetic_is_not_counted_as_divergence() -> void:
	var theirs := _record()
	theirs[AttackRecord.KEY_HIT_AMOUNT] = PackedFloat64Array([99.0, 0.0])
	theirs[AttackRecord.KEY_HIT_KIND] = PackedByteArray([1, 1])
	theirs[AttackRecord.KEY_HIT_HP_BEFORE] = PackedFloat64Array([1.0, 1.0])
	theirs[AttackRecord.KEY_HIT_HP_AFTER] = PackedFloat64Array([0.0, 0.0])
	theirs[AttackRecord.KEY_HIT_HP_MAX] = PackedFloat64Array([1.0, 1.0])
	theirs[AttackRecord.KEY_DEALLOC_COUNT] = PackedInt32Array([2, 2])
	theirs[AttackRecord.KEY_DEALLOC_NODE] = PackedInt32Array([1, 2, 3, 4])
	assert_eq(DeterminismProbe.diverging_fields(_record(), theirs), [] as Array[String],
			"land-time fields must not be compared")


## #503's gate is decided at land time and shares its byte with the crit bit,
## so the raw flags field is not comparable — only the crit bit within it is.
func test_the_gated_flag_is_masked_off_but_the_crit_flag_is_not() -> void:
	var gated := _record()
	gated[AttackRecord.KEY_HIT_FLAGS] = PackedByteArray(
			[AttackRecord.FLAG_CRIT | AttackRecord.FLAG_GATED, AttackRecord.FLAG_GATED])
	assert_eq(DeterminismProbe.diverging_fields(_record(), gated), [] as Array[String],
			"FLAG_GATED is land-time and must be masked out")

	var uncritted := _record()
	uncritted[AttackRecord.KEY_HIT_FLAGS] = PackedByteArray([0, 0])
	assert_eq(DeterminismProbe.diverging_fields(_record(), uncritted),
			["h_crit_flag"] as Array[String],
			"a crit decided differently IS a determinism failure — it is a seeded roll")


## The hit SET and its ORDER are exactly what #530's stable hitscan sort exists
## to make reproducible, so this is the divergence the probe is built to catch.
func test_a_different_hit_set_is_reported_by_field() -> void:
	var theirs := _record()
	theirs[AttackRecord.KEY_HIT_TARGET] = PackedInt32Array([9, 4])
	assert_eq(DeterminismProbe.diverging_fields(_record(), theirs),
			[AttackRecord.KEY_HIT_TARGET] as Array[String])


func test_a_different_seed_or_cost_is_reported() -> void:
	var theirs := _record()
	theirs[AttackRecord.KEY_SEED] = 999
	theirs[AttackRecord.KEY_AP] = 4
	assert_eq(DeterminismProbe.diverging_fields(_record(), theirs),
			[AttackRecord.KEY_SEED, AttackRecord.KEY_AP] as Array[String])


## The propagation timeline is a resolve product — a peer that walked a
## different set of edges has diverged even if every landing happened to match.
func test_a_different_timeline_is_reported() -> void:
	var theirs := _record()
	theirs[AttackRecord.KEY_EVENT_TARGET] = PackedInt32Array([4, 12])
	theirs[AttackRecord.KEY_EVENT_HITS] = [PackedInt32Array([0]), PackedInt32Array([0, 1])]
	assert_eq(DeterminismProbe.diverging_fields(_record(), theirs),
			[AttackRecord.KEY_EVENT_TARGET, AttackRecord.KEY_EVENT_HITS] as Array[String])


func _probe(enabled: bool) -> DeterminismProbe:
	var probe := DeterminismProbe.new()
	probe.enabled = enabled
	add_child_autofree(probe)
	return probe


func test_a_disabled_probe_tallies_nothing() -> void:
	var probe := _probe(false)
	probe.observe_world(AllocateCommand.new(1, 2), false)
	probe.observe_skipped(AllocateCommand.new(1, 2))
	assert_string_contains(probe.report(), "never enabled")
	assert_eq(probe.world_tally(AllocateCommand.TAG),
			{"agreed": 0, "diverged": 0, "skipped": 0, "exempt": 0},
			"an off probe must not accumulate — that is what makes it free")


## The denominator is the finding. `CommandLink` deliberately skips the
## fingerprint compare while its queue is non-empty or a newer command has
## superseded it, so a probe that only counted verdicts would hand the owner
## "0 diverged" while a third of the traffic was never looked at.
func test_skipped_commands_are_counted_not_dropped() -> void:
	var probe := _probe(true)
	probe.observe_world(AllocateCommand.new(1, 2), true)
	probe.observe_world(AllocateCommand.new(1, 3), false)
	probe.observe_skipped(AllocateCommand.new(1, 4))
	probe.observe_skipped(AllocateCommand.new(1, 5))
	assert_eq(probe.world_tally(AllocateCommand.TAG),
			{"agreed": 1, "diverged": 1, "skipped": 2, "exempt": 0})
	assert_string_contains(probe.report(), "(of 4 received)",
			"the report must state how many commands it actually looked at")


## `.claude/rules/multiplayer-sync.md` carves host-only rolls out explicitly, so
## a loot round that the peer could never have reproduced is the model working,
## not a mismatch. Its own column keeps a real failure from being buried.
func test_loot_is_tallied_as_exempt_rather_than_diverged() -> void:
	var probe := _probe(true)
	probe.observe_world(LootRoundCommand.new(1, 2), false)
	assert_eq(probe.world_tally(LootRoundCommand.TAG),
			{"agreed": 0, "diverged": 0, "skipped": 0, "exempt": 1},
			"a loot round the peer could never reproduce is exempt, not diverged")


## Only [LaunchAttackCommand] carries both the inputs and the host's result, so
## it is the only verb the RESOLVE question can even be asked of. Everything
## else is intent-only and the world column is the whole answer.
func test_only_attacks_reach_the_resolve_column() -> void:
	var probe := _probe(true)
	probe.observe_before_apply(AllocateCommand.new(1, 2))
	probe.observe_before_apply(EndTurnCommand.new(1))
	assert_string_contains(probe.report(), "nothing was re-resolvable")


## An attack whose plan cannot be rebuilt here is `unavailable`, which is a
## third outcome — neither agreement nor divergence. Reporting it as either
## would be a lie in one direction or the other.
func test_an_unrebuildable_plan_is_unavailable_not_diverged() -> void:
	var graph: Graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	var probe := _probe(true)
	probe.graph = graph
	var command := LaunchAttackCommand.new(1, {"mode": BattleSystem.AttackMode.NONE}, 42)
	command.record = _record()
	probe.observe_before_apply(command)
	assert_eq(probe.resolve_tally(LaunchAttackCommand.TAG),
			{"agreed": 0, "diverged": 0, "unavailable": 1, "landings": 0})
	assert_false(probe.report().contains("fields that disagreed"),
			"a plan that never rebuilt has no fields to disagree about")
