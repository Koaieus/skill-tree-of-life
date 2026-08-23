extends GutTest

## #539 — the regression surface behind the Outcome playground tab.
##
## A committed [OutcomeFixture] holds one recorded [LaunchAttackCommand] — plan
## + record + seed, the exact wire payload. This replays it into a freshly built
## world by **submitting it to a local [CommandApplier] with no [CommandLink]
## attached**, which is byte-for-byte the peer path, and asserts the resulting
## [method WorldFingerprint.compute].
##
## Without this the tab is a toy: it would prove a replay looks right on the day
## someone watches it, and nothing on any other day.
##
## [b]Regenerating the fixture.[/b] A deliberate change to
## `scenes/dev/outcome_playground_world.gd` (or to what an attack does) moves
## the recorded numbers, and the fixture is regenerated rather than hand-edited:
##
## [codeblock]
##   REGEN_OUTCOME_FIXTURE=1 mise run test:one -- \
##       res://test/unit/attack/test_outcome_fixture_replay.gd
## [/codeblock]
##
## That path captures a LIVE attack in this same headless context and rewrites
## the `.tres` — the same artifact the tab's Save button writes, so the two can
## never drift into two formats. Review the diff before committing it: a
## regenerated golden that nobody looked at bakes in whatever broke.

const _WORLD := preload("res://scenes/dev/outcome_playground_world.gd")
const _SANDBOX_WORLD := preload("res://scenes/dev/sandbox_world.gd")

## The one committed fixture: Spark kills `d_gate`, whose loss islands the limb
## — a three-layer forced-dealloc cascade on the replay path.
const FIXTURE_PATH := "res://test/fixtures/outcome/spark_cascade.tres"

const REGEN_ENV := "REGEN_OUTCOME_FIXTURE"

## Ran the capture already this run — the regen path rewrites one file, and two
## tests asking for it must not produce two different recordings.
var _regenerated: bool = false


## One playground world plus the real systems, composed through the SAME
## [SandboxWorld] scaffold the tab uses. Composition does not move the
## fingerprint (it folds graph state only), but a test that composed its own
## systems would stop being evidence about the tab.
func _build() -> Dictionary:
	var root := Node.new()
	add_child_autofree(root)
	var world = _WORLD.new()
	var graph: Graph = world.build(root)
	var systems = _SANDBOX_WORLD.new()
	systems.name = "SandboxWorld"
	root.add_child(systems)
	# `commands` for the applier the replay submits to, `turn_manager` because
	# `build_launch_command` refuses outright without a `current_entity`. No
	# `attack_vfx`: the tab mounts one to DRAW the cast, and #474's whole point
	# is that the applied world is identical whether or not it is there.
	systems.build(graph, {commands = true, turn_manager = true})
	await get_tree().process_frame
	# Land the whole outcome on one line. The end state is identical either way
	# (#474) — this test measures the record, never the beat clock.
	systems.battle_system.instant_mutation = true
	_arm(world, systems)
	return {
		"world": world, "graph": graph, "systems": systems,
		"battle": systems.battle_system, "applier": systems.command_applier,
	}


## Back to the canonical pre-state. Muted, because the strips inside `arm` are
## genuine `force_deallocate` calls and would otherwise shatter the whole board
## every time — the same mute the tab wraps its Reset in.
func _arm(world: Variant, systems: Variant) -> void:
	systems.allocation_vfx.muted = true
	world.arm(systems.allocation_system, systems.turn_manager)
	systems.allocation_vfx.muted = false


## Submit through the applier and wait for the queue to go idle. This is the
## unit of replay: one command, one applier, no link.
func _submit_and_settle(applier: CommandApplier, command: Command) -> void:
	applier.submit(command)
	while applier.is_applying:
		await applier.applying_changed


## Capture a live attack and rewrite the committed fixture. Only ever called
## when [constant REGEN_ENV] is set, or when the file is missing outright.
func _regenerate() -> void:
	var ctx: Dictionary = await _build()
	var battle: BattleSystem = ctx.battle
	(ctx.world as Variant).arm_magic(battle)
	var before := WorldFingerprint.compute(ctx.graph)
	var command := battle.build_launch_command()
	assert_not_null(command, "the playground world must produce a launchable cast")
	if command == null:
		return
	# The AUTHORITY half — resolve, apply, stamp the record. That stamped
	# command is the artifact; everything below replays it.
	await _submit_and_settle(ctx.applier, command)
	assert_false(command.record.is_empty(),
			"the authority must stamp the record it produced onto the command")
	var fixture := OutcomeFixture.capture(command, before,
			WorldFingerprint.compute(ctx.graph),
			"Spark cast from a_leaf onto d_gate: the kill islands the limb, so the "
			+ "forced-dealloc cascade replays as three BFS layers. Regenerate with "
			+ "%s=1 on test_outcome_fixture_replay.gd." % REGEN_ENV)
	DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path(FIXTURE_PATH.get_base_dir()))
	assert_eq(ResourceSaver.save(fixture, FIXTURE_PATH), OK,
			"the fixture must be writable")
	gut.p("regenerated outcome fixture → %s" % FIXTURE_PATH)


## The committed fixture. Regenerated ONLY when [constant REGEN_ENV] is set —
## never as a fallback for a missing file. A test that captured its own golden
## when it could not find one would pass on every machine forever while
## asserting nothing, which is precisely the toy this file exists to not be.
func _fixture() -> OutcomeFixture:
	if OS.get_environment(REGEN_ENV) != "" and not _regenerated:
		_regenerated = true
		await _regenerate()
	# `CACHE_MODE_IGNORE`: the regen above just overwrote the file, and a cached
	# copy from before it would replay the previous recording.
	return ResourceLoader.load(FIXTURE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) \
			as OutcomeFixture


# ── The builder's own contract ──────────────────────────────────────────────

func test_the_world_builder_mints_the_same_ids_every_time() -> void:
	# The assumption the whole fixture design rests on. A record names nodes by
	# `stable_id` and its attacker by `entity_id`; both mint from per-Graph
	# counters walking container child order, so "the same code twice" has to
	# mean "the same integers twice" — or a fixture is only replayable in the
	# process that captured it.
	var a: Dictionary = await _build()
	var b: Dictionary = await _build()
	for key in (a.world as Variant).nodes:
		assert_eq((b.graph as Graph).get_stable_id((b.world as Variant).nodes[key]),
				(a.graph as Graph).get_stable_id((a.world as Variant).nodes[key]),
				"node '%s' must mint the same stable_id in both builds" % key)
	assert_eq((b.world as Variant).attacker.entity_id,
			(a.world as Variant).attacker.entity_id,
			"…and so must the attacker's entity_id, which the command carries")
	assert_eq(WorldFingerprint.compute(b.graph), WorldFingerprint.compute(a.graph),
			"two armed builds are the same world (a %s / b %s)" % [
			WorldFingerprint.describe(a.graph), WorldFingerprint.describe(b.graph)])


# ── The fixture ─────────────────────────────────────────────────────────────

func test_a_committed_fixture_replays_to_its_recorded_fingerprint() -> void:
	var fixture: OutcomeFixture = await _fixture()
	assert_not_null(fixture, "the committed fixture must load")
	if fixture == null:
		return
	# Over the wire, not straight out of the resource — `var_to_bytes` is what a
	# transport actually does, and it is the step that would reject a payload
	# holding a live Object.
	var command := fixture.to_command_over_the_wire()
	assert_not_null(command, "…and rebuild through CommandCodec's tag dispatch")
	if command == null:
		return
	assert_false(command.record.is_empty(),
			"a fixture is a RECORDED outcome — an empty record would replay as an initiate")

	var ctx: Dictionary = await _build()
	var before := WorldFingerprint.compute(ctx.graph)
	assert_eq(before, fixture.world_fingerprint_at_capture,
			"the world this fixture was captured against has drifted — regenerate it "
			+ "(%s=1); see this file's docstring" % REGEN_ENV)

	await _submit_and_settle(ctx.applier, command)

	var after := WorldFingerprint.compute(ctx.graph)
	assert_ne(after, before,
			"the replay must actually change the world, or the assertion below is vacuous")
	assert_eq(after, fixture.expected_fingerprint,
			"replayed world must match the recording (got %s)"
			% WorldFingerprint.describe(ctx.graph))


func test_the_replay_needs_no_link_and_no_live_plan() -> void:
	# The proof this is a peer path and not a host path in disguise: nothing
	# armed a plan on this BattleSystem, and no CommandLink exists anywhere. A
	# replay that quietly re-resolved would have refused outright ("initiate
	# with no live plan") instead of landing anything.
	var fixture: OutcomeFixture = await _fixture()
	var ctx: Dictionary = await _build()
	assert_null((ctx.battle as BattleSystem).attack_plan,
			"no plan is armed before the replay")
	await _submit_and_settle(ctx.applier, fixture.to_command_over_the_wire())
	assert_null((ctx.world as Variant).nodes["d_gate"].owned_by,
			"the recorded kill landed: the gate is nobody's")


func test_the_replayed_cascade_keeps_its_bfs_layers() -> void:
	# Acceptance 3. `cascade_started` carries the dealloc set BFS'd into layers
	# and [AllocationVFX] staggers its shatter spawn off exactly that — so a
	# replay that flattened the layers would drop three nodes to dead on one
	# frame with no death animation, the symptom #534 names.
	#
	# The expected shape is read off the builder's topology, not off the
	# fixture: killing `d_gate` islands `d_limb1` then `d_limb2`, one hop at a
	# time, while `d_core` survives. An independent oracle, so a regenerated
	# golden cannot quietly bake a flattened cascade in.
	var fixture: OutcomeFixture = await _fixture()
	var ctx: Dictionary = await _build()
	var seen: Array = []
	(ctx.battle as BattleSystem).cascade_started.connect(
			func(layers: Array, _defender: Entity) -> void: seen.append(layers))

	await _submit_and_settle(ctx.applier, fixture.to_command_over_the_wire())

	assert_eq(seen.size(), 1, "one landing killed one node, so one cascade")
	if seen.is_empty():
		return
	var layers: Array = seen[0]
	var sizes: Array[int] = []
	var flat: Array = []
	for layer in layers:
		sizes.append((layer as Array).size())
		flat.append_array(layer as Array)
	assert_eq(sizes, [1, 1, 1] as Array[int],
			"the cascade must arrive as three BFS layers, not one flat set")
	var world: Variant = ctx.world
	assert_eq(flat, [world.nodes["d_gate"], world.nodes["d_limb1"], world.nodes["d_limb2"]],
			"…in impact-outward order")
	assert_eq(world.nodes["d_core"].owned_by, world.defender,
			"the defender's core is not islanded from itself, so it survives")
