extends GutTest

## Determinism of attack resolution — the invariant the multiplayer sync model
## and the AI-preview slice both rest on.
##
## The claim under test: [b]a fully deterministic attack has a fully
## deterministic result[/b]. Same inputs, same starting world → the same
## [AttackOutcome], hit for hit, including crits and ordering. If that holds,
## a peer handed only the attack INTENT could replay the attack locally and
## land on a bit-identical end state; if it does not, the peer's world forks
## silently and permanently.
##
## See `docs/domain/multiplayer-sync-model.md` (host-authoritative,
## intent-up / confirmed-command-down) and `docs/domain/attack-timeline.md`
## (set frozen at resolve, all arithmetic live).
##
## [b]What this file can and cannot prove.[/b] It runs in one headless
## process, so it pins [i]reproducibility[/i] — the necessary condition —
## not cross-machine float or physics agreement. Reproducibility failing here
## is proof that intent-only replay is unsafe. Reproducibility passing here
## is not proof that it is safe.
##
## The known gaps are pinned as characterization tests rather than left as
## prose, so they stay visible and fail loudly the day they are closed. Each
## one names what to flip when its issue lands.

const H := preload("res://test/unit/spell/spell_test_helper.gd")


# ── Fingerprinting ───────────────────────────────────────────────────────────

## Every field of an [AttackOutcome] that a peer replaying the attack would
## have to agree on, flattened to comparable strings in emission order.
##
## Ordering is deliberately significant: two resolutions that produce the same
## SET of landings in a different ORDER are a divergence under
## `attack-timeline.md`, because the applier walks them in order and each
## landing's gate is re-read against the state the previous ones left behind.
##
## The target is keyed by [member SkillNode.stable_id] — the wire-legal
## identifier — falling back to node name for fixtures built outside a
## [Graph] that mints ids.
static func fingerprint(outcome: AttackOutcome) -> Array[String]:
	var out: Array[String] = []
	if outcome == null:
		return out
	for hit: HitInstance in outcome.hits:
		out.append("%s|%s|%.6f|%.6f|%s|%d|%.6f|%.6f|%s|%s" % [
			_id_of(hit.target),
			"HEAL" if hit.kind == HitInstance.Kind.HEAL else "DAMAGE",
			hit.amount,
			hit.effective_amount,
			str(hit.is_crit),
			hit.crit_tier,
			hit.crit_multiplier,
			hit.arrival_time,
			str(hit.gated),
			_id_of(hit.origin),
		])
	return out


static func _id_of(node: SkillNode) -> String:
	if node == null:
		return "<null>"
	var sid := str(node.stable_id)
	return sid if not sid.is_empty() and sid != "0" else str(node.name)


## A hub of enemy nodes: N0 is the attacker's, N1 is the seed, N2..N5 are the
## seed's hostile neighbours. Multiple valid next-hops is what makes a
## stochastic propagation step observable at all — without a real branch, a
## seeded-RNG test passes vacuously.
func _make_branching_world() -> Dictionary:
	var helper := H.new()
	var graph := helper.make_graph([[0, 1], [1, 2], [1, 3], [1, 4], [1, 5]], self)
	var attacker := helper.make_entity(graph, "A", Color.RED)
	var defender := helper.make_entity(graph, "D", Color.BLUE)
	helper.give_big_hp(defender)
	helper.assign_owner(graph, attacker, [0])
	helper.assign_owner(graph, defender, [1, 2, 3, 4, 5])
	return {helper = helper, graph = graph, attacker = attacker, defender = defender}


func _resolve_random_pick(world: Dictionary, rng: RandomNumberGenerator) -> AttackOutcome:
	var helper: H = world.helper
	var graph: Graph = world.graph
	var config := helper.make_config(
		helper.random_pick_step(), helper.owner_enemy(), null, {max_hops = 1})
	var spell := helper.make_spell(config, [DamageEffect.new()], 10.0)
	var nodes: Array = graph.get_skill_nodes()
	return SpellResolver.resolve(spell, nodes[1], nodes[0], world.attacker, graph, rng)


func _seeded(value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = value
	return rng


# ── The invariant: seeded resolution is reproducible ─────────────────────────

func test_the_fingerprint_is_sensitive_to_a_different_seed() -> void:
	# Guards every test below it. If the fingerprint could not tell two
	# different resolutions apart, "same seed reproduces" would pass
	# vacuously and this whole file would assert nothing.
	var seen := {}
	for s in [11, 22, 33, 44, 55, 66, 77, 88]:
		var world := _make_branching_world()
		seen[str(fingerprint(_resolve_random_pick(world, _seeded(s))))] = true
	assert_gt(seen.size(), 1,
		"RandomPickStep must pick differently across seeds, or this fixture " +
		"has no observable branch and the reproducibility tests are vacuous")


func test_same_seed_reproduces_the_same_magic_outcome() -> void:
	# The core claim, for a stochastic spell: identical inputs and identical
	# starting state produce an identical landing list, in identical order.
	var a := fingerprint(_resolve_random_pick(_make_branching_world(), _seeded(0xA11CE)))
	var b := fingerprint(_resolve_random_pick(_make_branching_world(), _seeded(0xA11CE)))
	assert_eq(a, b, "same seed + same world must produce an identical outcome")
	assert_false(a.is_empty(), "fixture produced no hits — the test proves nothing")


func test_same_seed_reproduces_the_same_crit_stream() -> void:
	# Crits are the second RNG consumer, derived from the propagation seed
	# (`crit_rng.seed = rng.seed ^ 0xC217`, propagation_context.gd:51) so
	# they reproduce WITHOUT consuming the propagation stream (#213). A
	# 50% chance across a fan makes divergence overwhelmingly likely if the
	# derivation were broken.
	var fingerprints: Array = []
	for _i in 2:
		var world := _make_branching_world()
		var helper: H = world.helper
		var cc: Stat = world.attacker.stat_board.get_stat(&"crit_chance")
		assert_not_null(cc, "fixture needs a crit_chance stat to roll against")
		cc.base_value = 0.5
		var config := helper.make_config(
			helper.fan_all(), helper.owner_enemy(), null, {max_hops = 1})
		var spell := helper.make_spell(config, [DamageEffect.new()], 10.0)
		var graph: Graph = world.graph
		var nodes: Array = graph.get_skill_nodes()
		fingerprints.append(fingerprint(SpellResolver.resolve(
			spell, nodes[1], nodes[0], world.attacker, world.graph, _seeded(0xC0FFEE))))
	assert_eq(fingerprints[0], fingerprints[1],
		"a seeded cast must reproduce its crit rolls, not just its hop choices")


func test_a_deterministic_spell_needs_no_seed_to_reproduce() -> void:
	# The other half of the picture, and the reason the gaps below are
	# narrow: a spell with no stochastic step and no crit chance is already
	# fully reproducible with rng == null. Most spells are in this class.
	var fingerprints: Array = []
	for _i in 2:
		var world := _make_branching_world()
		var helper: H = world.helper
		var config := helper.make_config(
			helper.fan_all(), helper.owner_enemy(), null, {max_hops = 1})
		var spell := helper.make_spell(config, [DamageEffect.new()], 10.0)
		var graph: Graph = world.graph
		var nodes: Array = graph.get_skill_nodes()
		fingerprints.append(fingerprint(SpellResolver.resolve(
			spell, nodes[1], nodes[0], world.attacker, world.graph)))
	assert_eq(fingerprints[0], fingerprints[1],
		"a non-stochastic, non-critting cast must be reproducible unseeded")


# ── Melee and ranged crits (#507) ────────────────────────────────────────────
#
# Until #507 these two modes drew no randomness at all — `crit_chance` was a
# universal stat that only SpellResolver read. Now all three modes roll it
# through one shared [CritRoll], off `AttackPlan.resolve_seed`, which puts
# melee and ranged under the same reproducibility claim as magic.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")


## A real graph + AllocationSystem, because ranged reads the attacker's
## EntityNavigator for its firing leaves and `H.assign_owner` only writes
## `owned_by` (no mirror). Returns the pieces the two fixtures below share.
func _make_allocated_world() -> Dictionary:
	var graph: Graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	var alloc := AllocationSystem.new()
	alloc.graph = graph
	add_child_autofree(alloc)
	var attacker := Entity.new()
	attacker.display_name = "A"
	attacker.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	# Both entities default to the `npc` faction, which makes them ALLIED —
	# and `RangedAttackPlan.validate` refuses a non-hostile target, so without
	# this the fixture resolves to zero shots and every crit assertion below
	# passes vacuously.
	attacker.faction = _PLAYER_FACTION
	graph.add_child(attacker)
	var defender := Entity.new()
	defender.display_name = "D"
	defender.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	defender.stat_board.get_stat(&"node_health").base_value = 9999.0
	graph.add_child(defender)
	return {graph = graph, alloc = alloc, attacker = attacker, defender = defender}


func _spawn_at(graph: Graph, nm: String, pos: Vector2) -> SkillNode:
	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	sn.name = nm
	graph.add_skill_node(sn)
	sn.global_position = pos
	return sn


## A star of five attacker leaves around a hub, all reaching one hostile
## target. Five reaching leaves means five shots, so five crit draws — enough
## that a broken derivation shows up as a different pattern rather than a
## coin flip that happens to agree.
func _ranged_plan(crit_chance: float) -> RangedAttackPlan:
	var w := _make_allocated_world()
	var graph: Graph = w.graph
	var alloc: AllocationSystem = w.alloc
	var attacker: Entity = w.attacker
	var hub := _spawn_at(graph, "Hub", Vector2.ZERO)
	var leaves: Array[SkillNode] = []
	for i in 5:
		var leaf := _spawn_at(graph, "Leaf%d" % i, Vector2.ZERO)
		graph.add_edge(hub, leaf)
		leaves.append(leaf)
	var target := _spawn_at(graph, "Target", Vector2.ZERO)
	alloc.force_allocate(attacker, hub)
	for leaf in leaves:
		alloc.force_allocate(attacker, leaf)
	attacker.core_location = hub
	alloc.force_allocate(w.defender, target)
	w.defender.core_location = target
	# Non-zero offense, or every hit is amount 0 and CritRoll skips it — the
	# test would pass while rolling nothing at all.
	attacker.stat_board.get_stat(&"dexterity").base_value = 100.0
	attacker.stat_board.get_stat(&"crit_chance").base_value = crit_chance
	var plan := RangedAttackPlan.new()
	plan.attacker = attacker
	plan.target = target
	return plan


## Pivot + one arm, target coincident with the arm so the swing scans a hit
## without depending on physics-server sync timing (same trick as
## `test_melee_swing_characterization.gd`).
func _melee_plan(crit_chance: float) -> MeleeAttackPlan:
	var w := _make_allocated_world()
	var graph: Graph = w.graph
	var alloc: AllocationSystem = w.alloc
	var attacker: Entity = w.attacker
	attacker.stat_board.blade_size.base_value = 2.0
	attacker.stat_board.get_stat(&"crit_chance").base_value = crit_chance
	var pivot := _spawn_at(graph, "Pivot", Vector2.ZERO)
	var arm := _spawn_at(graph, "Arm", Vector2(150, 0))
	graph.add_edge(pivot, arm)
	var target := _spawn_at(graph, "Target", Vector2(150, 0))
	await get_tree().process_frame
	alloc.force_allocate(attacker, pivot)
	alloc.force_allocate(attacker, arm)
	attacker.core_location = pivot
	alloc.force_allocate(w.defender, target)
	w.defender.core_location = target
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	var plan := MeleeAttackPlan.new()
	plan.attacker = attacker
	plan._on_node_left_clicked(pivot)
	plan._on_node_left_clicked(arm)
	return plan


func _crit_flags(outcome: AttackOutcome) -> Array[bool]:
	var out: Array[bool] = []
	for hit in OutcomeApplier.in_arrival_order(outcome.hits):
		out.append(hit.is_crit)
	return out


func test_ranged_rolls_crits_at_all() -> void:
	# The gap #507 closed, stated positively: before it, `crit_chance` could be
	# 1.0 and a volley still never crit. Guards the reproducibility tests below
	# from passing vacuously on an outcome where nothing ever crits.
	var plan := _ranged_plan(1.0)
	plan.resolve_seed = 0xA11CE
	var outcome := plan.resolve()
	assert_gt(outcome.hits.size(), 0, "fixture produced no shots")
	for hit in outcome.hits:
		assert_true(hit.is_crit, "crit_chance 1.0 must crit every arrow")
		assert_eq(hit.crit_multiplier, 2.0, "and carry the board's multiplier")
		assert_eq(hit.crit_tier, 1, "stat path only — conditions stay magic-only")


func test_ranged_reproduces_its_crit_pattern_under_a_stamped_seed() -> void:
	var a := _ranged_plan(0.5)
	a.resolve_seed = 0xC0FFEE
	var b := _ranged_plan(0.5)
	b.resolve_seed = 0xC0FFEE
	assert_eq(fingerprint(a.resolve()), fingerprint(b.resolve()),
		"the same stamped seed must reproduce the same volley, crits included")


func test_ranged_crits_differ_across_seeds() -> void:
	# The other half: if every seed produced the same pattern, the test above
	# would prove nothing. 5 shots at 50 % — eight seeds agreeing is a 1-in-2^28
	# accident, so a failure here is a broken derivation, not bad luck.
	var seen := {}
	for s in [11, 22, 33, 44, 55, 66, 77, 88]:
		var plan := _ranged_plan(0.5)
		plan.resolve_seed = s
		seen[str(_crit_flags(plan.resolve()))] = true
	assert_gt(seen.size(), 1, "the volley's crit pattern must depend on the seed")


func test_ranged_carries_its_seed_out_on_the_outcome() -> void:
	# Same self-describing-artifact contract magic already satisfied: a peer
	# handed (intent + this seed) can re-resolve to a bit-identical outcome.
	var plan := _ranged_plan(0.5)
	plan.resolve_seed = 4242
	assert_eq(plan.resolve().resolve_seed, 4242)


func test_melee_rolls_crits_at_all() -> void:
	var plan: MeleeAttackPlan = await _melee_plan(1.0)
	plan.resolve_seed = 0xA11CE
	var outcome := plan.resolve()
	assert_gt(outcome.hits.size(), 0, "fixture produced no blade contacts")
	for hit in outcome.hits:
		assert_true(hit.is_crit, "crit_chance 1.0 must crit every blade landing")
	assert_eq(outcome.resolve_seed, 0xA11CE, "the outcome carries its own seed")


func test_melee_reproduces_its_crit_pattern_under_a_stamped_seed() -> void:
	var a: MeleeAttackPlan = await _melee_plan(0.5)
	a.resolve_seed = 0xC0FFEE
	var b: MeleeAttackPlan = await _melee_plan(0.5)
	b.resolve_seed = 0xC0FFEE
	assert_eq(_crit_flags(a.resolve()), _crit_flags(b.resolve()),
		"the same stamped seed must reproduce the same swing's crits")


func test_the_live_melee_and_ranged_paths_resolve_under_the_stamped_seed() -> void:
	# Structural, like `test_the_live_magic_path_resolves_under_a_stamped_seed`
	# below: asserted against the source so a future refactor that reaches for
	# `randf()` — the hole 8dc6f77 closed for magic — cannot land quietly.
	for path in [
			"res://attack/plan/melee_attack_plan.gd",
			"res://attack/plan/ranged_attack_plan.gd"]:
		var src := FileAccess.get_file_as_string(path)
		assert_false(src.is_empty(), "could not read %s" % path)
		assert_string_contains(src, "CritRoll.stream_for(resolve_seed)",
			"%s must draw crits off the stamped seed" % path)
		assert_string_contains(src, "outcome.resolve_seed = resolve_seed",
			"%s's outcome must carry the seed it resolved under" % path)


func test_crit_draws_are_consumed_in_arrival_order() -> void:
	# The cross-mode constraint: one stream serves a whole attack, so if two
	# modes consumed it in different orders the same seed would stop
	# reproducing the same crits. CritRoll reuses OutcomeApplier's own sort
	# rather than re-deriving one, which is what makes them unable to disagree.
	var src := FileAccess.get_file_as_string("res://attack/outcome/crit_roll.gd")
	assert_false(src.is_empty(), "could not read crit_roll.gd")
	assert_string_contains(src, "OutcomeApplier.in_arrival_order",
		"the crit stream must be consumed in the order the applier lands hits")


func test_the_crit_multiplier_is_applied_at_land_not_at_resolve() -> void:
	# The other half of the two-clock split (#507): the DECISION is at resolve
	# so VFX can read `is_crit` on a projectile it is about to launch, but the
	# ARITHMETIC is at land, after ranged's live `ranged_damage` re-read (#503)
	# would otherwise have thrown a resolve-time multiply away.
	var plan := _ranged_plan(1.0)
	plan.resolve_seed = 7
	var outcome := plan.resolve()
	var hit: HitInstance = outcome.hits[0]
	var base := hit.amount
	assert_gt(base, 0.0, "fixture must deal real damage or this proves nothing")
	assert_true(hit.is_crit, "decided at resolve")
	OutcomeApplier.apply(outcome)
	assert_almost_eq(hit.amount, base * 2.0, 0.001, "multiplied at land")


# ── The gaps, pinned ─────────────────────────────────────────────────────────
#
# These assert that a known determinism hole IS STILL OPEN. They are
# structural, not statistical, so they are not flaky — and each one fails the
# day its hole is closed, which is the point: closing it should have to come
# past this file.

func test_gap_an_unseeded_context_mints_a_randomized_crit_stream() -> void:
	# propagation_context.gd:54 — with no propagation seed, `rng_for_crits()`
	# calls `randomize()`.
	#
	# NARROWED, not closed. The LIVE cast path no longer reaches this:
	# MagicAttackPlan now arms an RNG off the stamped AttackPlan.resolve_seed.
	# But SpellResolver.resolve's `rng` is still an optional parameter, and
	# resolve()'s other callers — spell tooltip, spell playground, balance
	# harness — still pass nothing and land here.
	#
	# That is survivable (they are read-only previews, and a preview cannot
	# predict the real cast's roll anyway) but it means an unstamped preview
	# reshuffles its crits on every repaint. Fixing it is a matter of routing
	# those callers through a plan, which owns the fixed-stream default.
	var seeds := {}
	for _i in 8:
		seeds[PropagationContext.new().rng_for_crits().seed] = true
	assert_gt(seeds.size(), 1,
		"unseeded crit RNGs are randomize()d — if these now agree, #457's " +
		"determinism contract has landed and this test must be inverted")


func test_the_live_magic_path_resolves_under_a_stamped_seed() -> void:
	# CLOSED (was a gap): the live cast path used to call
	# SpellResolver.resolve/5, defaulting `rng` to null, so
	# PropagationContext randomize()d its crit stream and a real cast was not
	# reproducible even on one machine.
	#
	# Now BattleSystem.launch_attack stamps AttackPlan.resolve_seed from its
	# own _seed_source before resolving, MagicAttackPlan arms an RNG off it,
	# and the outcome carries the seed back out.
	#
	# Asserted structurally against the source so it cannot rot silently.
	var plan_src := FileAccess.get_file_as_string("res://attack/plan/magic_attack_plan.gd")
	assert_false(plan_src.is_empty(), "could not read magic_attack_plan.gd")
	assert_string_contains(plan_src, "seeded_rng()",
		"the live magic path must resolve under the stamped seed")
	assert_string_contains(plan_src, "outcome.resolve_seed = resolve_seed",
		"the outcome must carry the seed it was resolved under, or it " +
		"cannot reproduce itself")
	var bs_src := FileAccess.get_file_as_string("res://systems/battle_system.gd")
	assert_false(bs_src.is_empty(), "could not read battle_system.gd")
	assert_string_contains(bs_src, "attack_plan.resolve_seed = _seed_source.randi()",
		"the authority must stamp a fresh seed per committed attack")


func test_an_unstamped_plan_resolves_on_a_fixed_stream() -> void:
	# The preview/AI-rollout contract: resolve_seed == 0 is not "random", it
	# is a FIXED stream. A tooltip that reshuffles its crits on every repaint
	# would be worse than one showing a stable representative roll.
	# AttackPlan is @abstract, so this goes through a concrete plan. The
	# field and `seeded_rng()` both live on the base, so any plan proves it.
	var a := RangedAttackPlan.new()
	var b := RangedAttackPlan.new()
	assert_eq(a.resolve_seed, 0, "an unstamped plan reads 0")
	assert_eq(a.seeded_rng().seed, b.seeded_rng().seed,
		"two unstamped plans must draw from the same stream")
	a.resolve_seed = 12345
	assert_ne(a.seeded_rng().seed, b.seeded_rng().seed,
		"a stamped plan must diverge from the unstamped stream")


func test_relic_rolls_are_unseeded_and_deliberately_stay_that_way() -> void:
	# NOT a gap, despite looking exactly like one. skill_dust_addon.gd
	# (249,297,307,355) shuffles relic pools off Godot's global RNG, so two
	# peers rolling the same kill would draw different relics.
	#
	# The resolution is NOT to seed this. Per
	# `docs/domain/multiplayer-sync-model.md`, loot rolls stay HOST-ONLY: the
	# host draws, and the only thing crossing the wire is the CHOSEN
	# modifier. Nothing observable depends on peers agreeing about the draw,
	# because no peer ever performs one.
	#
	# So do NOT "fix" this by threading AttackPlan.resolve_seed into it —
	# that would be solving a problem the authority model already deletes.
	# What is still owed is the host-only wiring, not a seed.
	var src := FileAccess.get_file_as_string("res://skill_node/addons/skill_dust_addon.gd")
	assert_false(src.is_empty(), "could not read skill_dust_addon.gd")
	assert_string_contains(src, "pool.shuffle()",
		"relic rolls draw from the global RNG by design — the sync answer " +
		"is host-only rolls, not a seeded stream")


func test_gap_melee_hit_detection_truncates_a_physics_query() -> void:
	# The structural one, and the reason melee can never be intent-only
	# replayed regardless of what #457 does.
	#
	# blade_hit_scan.gd queries `space_state.intersect_shape(params,
	# _MAX_HITS_PER_QUERY)`. That is a CAP: when more shapes overlap the
	# blade than the cap allows, WHICH ones come back depends on broadphase
	# ordering, for which Godot documents no guarantee. The hit set is
	# therefore not a function of world state alone, and no seeding fixes it.
	#
	# This test does not fail when a gap closes — it pins an assumption. If
	# the cap is ever removed, or the scan stops using a physics query,
	# revisit `docs/domain/attack-timeline.md`'s melee physics note.
	var src := FileAccess.get_file_as_string("res://attack/melee/sim/blade_hit_scan.gd")
	assert_false(src.is_empty(), "could not read blade_hit_scan.gd")
	assert_string_contains(src, "_MAX_HITS_PER_QUERY",
		"melee still truncates its physics query — see attack-timeline.md")
	assert_string_contains(src, "intersect_shape",
		"melee hit detection is still a physics query and cannot be replayed " +
		"from intent alone")
