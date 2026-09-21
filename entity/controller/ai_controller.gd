class_name AIController
extends EntityController

## Minimum-viable NPC controller (AI v1, #22). There are no turn phases —
## the controller sequences its own actions within the single turn, pausing
## briefly between them so the player can read what happened, then ends the
## turn. No infinite loops — every branch exits in bounded steps.
##
## Sequence (budget-driven, not phase-driven): NPC v1 never voluntarily
## deallocates → recon pass (fog-aware, per-entity — see [AiRecon]) → spend
## all SP on frontier growth, scored via [method AiCombatScorer.score_frontier]
## (directional-toward-enemies + a tactical-enable bonus for a pick that lands
## a near-miss kill) → if no hostile is visible, end turn (growth-only
## short-circuit); otherwise the AP×2 loop scores every ranged + magic
## candidate against every visible hostile via [AiCombatScorer], executes the
## best, and re-evaluates — the re-eval is what makes dent-then-finish and the
## 1-damage floor fall out naturally rather than needing special-casing.
## Melee candidates come from [AiBladeRollout] (#378 slice C) — a bounded
## reach-bound-reject / steerable-proposal / two-tier-evaluation rollout
## rather than exhaustive enumeration (the induced-subgraph space is too
## large and a full swing resolve is milliseconds, not microseconds).
##
## [b]The AI emits commands, it does not call systems[/b] (#512). Every
## mutation it decides on leaves through [method _submit_and_wait] as a
## [Command] applied by the one [CommandApplier], the same queue the player's
## clicks feed — which is what makes the applier the ONLY mutation path rather
## than merely one of them. Read-only system access for scoring stays
## ([BattleSystem] for plan composition, the navigator for reachability); what
## went is the [AllocationSystem] reference the AI could have mutated through.
## `turn_delay` is unaffected and deliberately kept: it is host-local
## presentation pacing with no sync meaning — see
## `docs/domain/multiplayer-sync-model.md`.
##
## [b]Dormant Cores are scenery until they are a wall[/b] (#604). An NPC is
## indifferent to them by default ([member Faction.targeted_by_ai]) — but the
## indifference is a stance, not a rule, and it is re-decided every turn from
## [method AiRecon.is_growth_capped]. Asked AFTER the growth step (that is when
## "nowhere left to allocate" is a fact rather than a guess), a capped NPC
## unlocks them for the rest of its turn, shoots its way out through one, and
## spends its still-banked SP on the freed node in a second growth pass — kill,
## relic, expand, all on the same turn. Nothing about the *player's* ability to
## clear a core changes; see [method AiRecon.is_ai_target].
##
## Fog-aware since #378: each AI consults [AiRecon] for its OWN visibility
## (not the shared player-only VisionSystem instance) — settled 2026-08-07,
## "each enemy acts only on what it personally sees", no faction-shared
## reveal in v1. Faction filtering uses [member Entity.faction] so future
## multi-faction support drops in trivially.

const _DEFAULT_TURN_DELAY := 0.4

## No-run fallback base for [member rng]'s seed (#823 D5) — `GameSession` may
## hold no live run at all (`dev_sandbox.tscn`, most unit fixtures). A fixed,
## distinctly-named constant, deliberately NOT [constant RunConfig
## .resolve_seed]'s own `1`: a real run can legitimately resolve to seed 1,
## and sharing the value would make "no run" and "a run that drew 1"
## indistinguishable while staring at a divergence. Never `randomize()` —
## reproducible is the whole point (tests/replays pin [member rng] directly).
const _NO_RUN_RNG_BASE_SEED := 823

## Two-tier gate for ranged + magic (#537 D1/D3): a cheap ungated heuristic
## ([method AiCombatScorer.cheap_estimate]) ranks every candidate, and only
## the top K get a real gate-accurate [method AttackPlan.resolve] (the
## [code]EntityCombat.snapshot()[/code] cost #537 exists to budget). Mirrors
## [constant AiBladeRollout._FINALIST_COUNT]'s shape and value — the #537 D1
## arithmetic that justified the whole approach assumed the same K across all
## three modes (`3 modes x 3 finalists x 11.58ms ~= 104ms`), so this stays in
## lockstep with melee's own constant rather than drifting to a tuned number
## nobody asked for (D2: "the worst has passed", not a millisecond target).
## Below this count, gating is a no-op — every candidate is both cheaply AND
## gate-accurately scored, identically to the pre-#537 exhaustive behaviour.
const _CANDIDATE_GATE_K := 3
## Arrows a kill-sized volley carries BEYOND arrows-to-kill (#958) — the
## owner's "+ margin": a shadow-world resolve is exact for the seed it rolled,
## the live launch rolls its own, so one spare arrow covers a crit that does
## not repeat. Tuning: owner tunes (hub #496); never a per-target formula.
const KILL_MARGIN_ARROWS := 1
## The authored [AmmoType] roster a volley's composition follows (#958):
## specials first in roster `order`, base fills the rest — the AI has no
## composer, so this IS its composition policy.
const _AMMO_TYPES: AmmoTypeRoster = preload("res://attack/ammo/ammo_type_roster.tres")

## Diagnostic only (#537's "count it before trusting the arithmetic" ask) —
## how many candidates PASS 1 validated (cheaply) before the two-tier gate
## trimmed to [constant _CANDIDATE_GATE_K], and how many survived, for the
## LAST gather of each mode this turn. Read by
## `test/perf/bench_ai_turn.gd`'s candidate-count instrumentation; nothing in
## this class's own control flow reads them back.
var last_ranged_candidate_count: int = 0
var last_ranged_promoted_count: int = 0
var last_magic_candidate_count: int = 0
var last_magic_promoted_count: int = 0

## Synced from Settings.current.ai_turn_delay at _ready unless a caller
## already overrode it (tests set this explicitly before add_child, to a
## value other than the compile-time default, to control pacing/avoid
## take_turn recursion — see .claude/rules/turn-manager.md).
@export var turn_delay: float = _DEFAULT_TURN_DELAY
## Tier-gates [AiCombatScorer]'s cut-vertex / enemy-weak-point / self-shape-
## risk bonuses. 0 = naive, picks by raw EV. Kept here (not on the scorer)
## since it's the controller's single behavior-shaping knob.
@export var ai_tier: int = 1
## Seeded off [code]GameSession.config.seed[/code] (#823 D5, owner 2026-09-10:
## "AI only runs by authority so option 1 should be fine even for
## multiplayer") mixed with a per-ENTITY discriminator — every AI on the
## board sharing the bare run seed would draw the identical sequence, so
## e.g. requirement 6's `rng.randi_range(ai_tier, ai_tier + 1)` would pick the
## same handle length for every AI on turn 1. Null sentinel: [method _ready]
## seeds a real one unless a caller already set one (tests set this
## explicitly before add_child, exactly as they already do for
## [member turn_delay]). Never [method RandomNumberGenerator.randomize] —
## reproducible is the point.
## Plain var, not `@export`: RandomNumberGenerator is RefCounted, not a
## Resource/Node/built-in, and `@export` only accepts those. Tests set it
## the same way regardless — directly, before `add_child`.
var rng: RandomNumberGenerator = null
## Verbose `print_rich` trace of candidate scoring / chosen action to the
## console. [signal Events.ai_decision] fires regardless of this toggle —
## this only gates the local console sink.
@export var debug_trace: bool = false
## Explicit injection wins over the GameRoot tree-walk — lets tests wire a
## bare CommandApplier / BattleSystem without composing a full game_root.tscn.
## Unset in production (GameRoot._ensure_controllers doesn't set these), so
## real levels keep resolving via [method _game_root_or_null] unchanged.
##
## There is deliberately no `allocation_system_override` any more (#512): the
## AI no longer holds a reference it could mutate the world through — every
## allocation goes out as a [Command].
@export var command_applier_override: CommandApplier = null
@export var battle_system_override: BattleSystem = null

# Cached on first use. Walked once via _find_game_root; cheap lookup.
var _game_root: GameRoot = null


func _ready() -> void:
	super._ready()
	if turn_delay == _DEFAULT_TURN_DELAY:
		turn_delay = Settings.current.ai_turn_delay
	Settings.changed.connect(_on_settings_changed)
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.seed = _resolve_rng_seed()


func _on_settings_changed(key: StringName, value: Variant) -> void:
	if key == &"ai_turn_delay":
		turn_delay = value


## The run seed (or [constant _NO_RUN_RNG_BASE_SEED] with no live run) mixed
## with a per-entity discriminator, so every AI on the board draws its own
## sequence rather than the one shared stream `GameSession.config.seed` would
## give them all. The discriminator must be STABLE and REPRODUCIBLE — the same
## on every machine and across a reload of the same run — so it is never
## `entity_id` (minted by entry order into `entities_container`, the same
## per-process-order trap `.claude/rules/graph.md` calls out for accessors)
## and never `get_instance_id()`. [member Entity.core_location]'s
## [method Graph.get_stable_id] is: one core per entity, and procgen assigns
## starting nodes deterministically off the same resolved seed. Falls back to
## [member Entity.display_name] for a coreless fixture entity (most unit
## tests) — good enough there since nothing in a fixture asks two same-named
## entities to roll independently in the same test.
func _resolve_rng_seed() -> int:
	var base := GameSession.config.seed \
			if GameSession.is_active() else _NO_RUN_RNG_BASE_SEED
	var discriminator := ""
	if entity != null:
		if entity.core_location != null and entity.navigator != null \
				and entity.navigator.graph != null:
			discriminator = "core:%d" % entity.navigator.graph.get_stable_id(entity.core_location)
		else:
			discriminator = "name:%s" % entity.display_name
	return hash("%d:%s" % [base, discriminator])


func take_turn() -> void:
	# A non-authority peer never originates mutations (#510's contract,
	# already enforced for SkillDustAddon's claim flow — see
	# CommandApplier.is_authority) — and #512 made this entity's decisions
	# real submissions, so a MIRROR peer's own copy of this controller would
	# decide and submit independently of the host's AI the instant its local
	# TurnManager hands this entity the turn (which a mirrored EndTurnCommand
	# does). Bail before the decision loop runs at all: this entity's turn
	# crosses the wire as the authority's commands, never ours.
	var applier := _command_applier()
	if applier != null and not applier.is_authority:
		return

	# Opening beat so the handover reads. NPC v1 never voluntarily deallocates.
	await _wait()
	if not _continue():
		return

	var visible_enemies := AiRecon.visible_enemy_nodes(entity)
	var saw_hostile := not visible_enemies.is_empty()

	# Spend all available SP on frontier growth, fog-aware or not — the
	# fog short-circuit only gates the ATTACK step below.
	visible_enemies = await _spend_skill_points(visible_enemies)
	saw_hostile = saw_hostile or not visible_enemies.is_empty()

	# Only NOW is "boxed in" a fact: the question is whether growth has run out
	# of board, so it has to be asked after growth has taken everything it can.
	# A capped NPC unlocks Dormant Cores for the rest of this turn (#604) —
	# they stay scenery for everyone else, see [method AiRecon.is_ai_target].
	var was_capped := _refresh_dormant_core_stance()
	if was_capped:
		var unlocked := AiRecon.visible_enemy_nodes(entity)
		# Announce only when the stance actually revealed something. Being
		# boxed in by real enemies is the common case and says nothing about
		# dormant cores — a decide line there would be noise, and it is what
		# the #512 parity golden would read as drift.
		if unlocked.size() > visible_enemies.size():
			_decide("growth-capped — %d dormant core(s) unlocked as targets" \
					% (unlocked.size() - visible_enemies.size()))
		visible_enemies = unlocked
		saw_hostile = saw_hostile or not visible_enemies.is_empty()

	if not saw_hostile:
		_decide("no visible hostile — growth only")
		_end_turn()
		return

	# Attack loop: score every ranged/magic/melee candidate against every
	# visible hostile, execute the best, re-evaluate — the board changed (a
	# dent, a kill), so re-running recon + enumeration each pass is what makes
	# dent-then-finish fall out naturally instead of needing special-casing.
	#
	# Two economies since #957/#958: melee and magic cost AP; a volley costs
	# 0 AP and spends arrows + per-leaf shots + a volley slot instead. So the
	# loop runs while EITHER can still act — at 0 AP only ranged is gathered —
	# and the owner's fire-to-kill / reload policy (hub #496, 2026-09-18) sits
	# in front of the pick: *"fires min(shots_left, arrows-to-kill + margin)
	# per target, greedy over scored targets, never single-shots, reloads when
	# stock < Σ shots_left and no kill is on the table."* The sizing lives in
	# [method _gather_ranged_candidates]; the reload-vs-fire order is here.
	if entity.stat_board != null:
		var ap: PoolStat = entity.stat_board.action_points
		var reload_stalled := false
		while _continue():
			visible_enemies = AiRecon.visible_enemy_nodes(entity)
			if visible_enemies.is_empty():
				break
			var has_ap := ap != null and ap.available() > 0
			var best := _best_attack_candidate(visible_enemies, not has_ap)
			# A kill on the table fires first; otherwise a due reload (1 AP)
			# tops the quiver up BEFORE the chip volley, so the chip is as
			# large as the leaves can carry. Bounded: each reload spends AP,
			# and a reload that minted nothing stops the reloading for good.
			var no_kill_volley := best == null \
					or (best.mode == BattleSystem.AttackMode.RANGED and not best.is_kill)
			if no_kill_volley and not reload_stalled and _reload_is_due():
				if await _reload():
					await _wait()
					continue
				reload_stalled = true
				continue
			if best == null:
				_decide("no reachable attack this turn")
				break
			# BattleSystem.launch_attack() has bail-outs (insufficient AP for
			# outcome.ap_cost, insufficient mana) that return WITHOUT deducting
			# anything or clearing the plan — _execute_candidate still reports
			# true since it awaited the call. Without this guard the loop would
			# re-enumerate, re-pick the same candidate, and spin forever
			# (synchronously, at turn_delay = 0). Break on no observed progress
			# — AP for melee/magic, the volley counter for ranged — instead of
			# trusting the return value alone.
			var ap_before: float = ap.current if ap != null else 0.0
			var volleys_before := entity.volleys_launched_this_turn
			if not await _execute_candidate(best):
				_decide("attack execution failed: %s" % best.trace)
				break
			var ap_now: float = ap.current if ap != null else 0.0
			if ap_now >= ap_before and entity.volleys_launched_this_turn <= volleys_before:
				_decide("attack committed but nothing was spent — stopping: %s" % best.trace)
				break
			_decide(best.trace)
			await _wait()

	# A cleared Dormant Core frees the node it held, and the SP the growth loop
	# above couldn't spend is still banked — so a capped NPC walks through the
	# door it just opened THIS turn rather than next. Only reachable when the
	# unlock fired: an uncapped NPC left the growth loop with nothing to buy.
	if was_capped:
		visible_enemies = await _spend_skill_points(visible_enemies)

	_end_turn()


## Spend every available SP on frontier growth, returning the enemy list as of
## the last allocation — territory changes each pass, so recon is re-run (a new
## leaf can put a previously-out-of-range hostile in vision). Returns rather
## than mutates: reassigning the parameter would not reach the caller.
##
## Runs twice per turn since #604 — once before the attack step, once after, so
## a Dormant Core cleared for being in the way is walked through on the same
## turn. Idempotent when there is nothing to buy: the first `_try_allocate_frontier`
## returns false and the loop breaks.
func _spend_skill_points(visible_enemies: Array[SkillNode]) -> Array[SkillNode]:
	if entity.stat_board == null:
		return visible_enemies
	var sp: SkillPointStat = entity.stat_board.skill_points
	if sp == null:
		return visible_enemies
	# Un-inlined loop (#512): the allocation suspends until the applier has
	# applied it, and `await` cannot live inside a `while` condition.
	while sp.current > 0 and _continue():
		if not await _try_allocate_frontier(visible_enemies):
			break
		await _wait()
		visible_enemies = AiRecon.visible_enemy_nodes(entity)
	return visible_enemies


## Re-decide, for this turn only, whether Dormant Cores are worth this NPC's AP
## — true iff it is growth-capped ([method AiRecon.is_growth_capped]). Returns
## the capped verdict; the stance itself lands on
## [member Entity.ai_growth_capped], which is where both halves of the
## AI target filter read it (list building AND swing valuation — see
## [method AiRecon.is_ai_target]).
##
## Always ASSIGNS rather than only setting on true: the flag must not outlive
## the turn that earned it, or an NPC that broke out once keeps shooting
## scenery forever.
func _refresh_dormant_core_stance() -> bool:
	var capped := AiRecon.is_growth_capped(entity)
	entity.ai_growth_capped = capped
	return capped


## Hand the turn back, as an [EndTurnCommand] rather than a direct
## [method TurnManager.end_turn] — the clock is a mutation like any other
## (#512). Not awaited: it is the last thing this turn does, and the applier
## running the next entity's turn inside it is exactly the shape the queue is
## built for. Still gated on [method _continue] — an AI that died mid-turn
## must not end someone else's.
func _end_turn() -> void:
	if _continue():
		_submit(EndTurnCommand.new(entity.entity_id))


## Emits [signal Events.ai_decision] unconditionally, and mirrors it to the
## console when [member debug_trace] is on. The single seam both channels
## (#378) go through.
func _decide(summary: String) -> void:
	Events.ai_decision.emit(entity, summary)
	if debug_trace:
		print_rich("[AIController] %s: %s" % [entity.display_name, summary])


func _try_allocate_frontier(visible_enemies: Array[SkillNode]) -> bool:
	var graph := _graph_or_null()
	if graph == null:
		return false
	var candidate := _pick_frontier_node(visible_enemies)
	if candidate == null:
		return false
	return await _submit_and_wait(
			AllocateCommand.new(entity.entity_id, graph.get_stable_id(candidate)))


## Frontier = unowned node adjacent to a node this entity already owns.
## Scored via [method AiCombatScorer.score_frontier] — directional-toward-
## enemies + a tactical-enable bonus for a pick that turns a near-miss ranged
## kill into a landed one (#378 acceptance: tactical-leaf-for-near-miss-kill).
## No visible enemies -> first match, there's nothing to score against yet.
func _pick_frontier_node(visible_enemies: Array[SkillNode]) -> SkillNode:
	var graph := entity.navigator.graph if entity.navigator != null else null
	if graph == null:
		return null
	var frontier := AiRecon.frontier_nodes(entity)
	if frontier.is_empty():
		return null
	if visible_enemies.is_empty():
		return frontier[0]
	var near_miss := AiCombatScorer.near_miss_targets(entity, visible_enemies)
	var best: SkillNode = null
	var best_score := -INF
	for candidate in frontier:
		var s := AiCombatScorer.score_frontier(candidate, entity, visible_enemies, near_miss)
		if s > best_score:
			best_score = s
			best = candidate
	return best


## Every ranged + magic + melee candidate against every visible hostile,
## scored via [AiCombatScorer].
## [param ranged_only]: at 0 AP a magic or melee candidate could still
## outscore a volley, get picked, bail in `launch_attack` and end the loop
## with the volley unfired — so out of AP, only the 0-AP mode is enumerated.
func _best_attack_candidate(visible_enemies: Array[SkillNode], ranged_only: bool = false) -> AiCombatScorer.ScoredCandidate:
	var candidates: Array[AiCombatScorer.ScoredCandidate] = []
	candidates.append_array(_gather_ranged_candidates(visible_enemies))
	if not ranged_only:
		candidates.append_array(_gather_magic_candidates(visible_enemies))
		candidates.append_array(_gather_melee_candidates(visible_enemies))
	return AiCombatScorer.pick_best(candidates)


## Owner (2026-09-18): the AI *"reloads when stock < Σ shots_left and no kill
## is on the table"* — the kill half is the caller's; this is the stock half,
## plus what makes the AP worth it: the entity can pay ([method Entity
## .can_reload]) and the quiver is below capacity (a full quiver still pays,
## so that would be an AP for nothing). Σ shots_left is over every firing
## position the entity holds, not one target's reaching subset — the question
## is "could my leaves fire more than I carry", whoever the target is.
func _reload_is_due() -> bool:
	if entity == null or entity.stat_board == null or not entity.can_reload():
		return false
	var quiver := entity.stat_board.arrows as Quiver
	if quiver == null:
		return false
	var stock: int = roundi(quiver.current)
	if stock >= roundi(float(quiver.get_value())):
		return false
	var probe := RangedAttackPlan.new()
	probe.attacker = entity
	var shots := 0
	for leaf in probe.get_firing_positions():
		shots += leaf.shots_left()
	return stock < shots


## Submit a [ReloadCommand] and report whether it actually grew the stock —
## the loop's progress signal, since a reload with nothing to mint (no
## turn-start leaves, a core that is not a producer) still pays its AP and
## would otherwise be re-decided every pass until the AP ran dry.
func _reload() -> bool:
	var quiver := entity.stat_board.arrows as Quiver
	var before: int = roundi(quiver.current)
	var ok := await _submit_and_wait(ReloadCommand.new(entity.entity_id))
	var after: int = roundi(quiver.current)
	_decide("reload: %d → %d arrows" % [before, after])
	return ok and after > before


## The typed composition of an [param n]-arrow volley from the live quiver:
## specials first in roster `order`, base fills the rest (owner, 2026-09-18 —
## the AI has no composer). Each bin contributes at most what it holds.
func _compose_volley(n: int) -> Dictionary:
	var counts: Dictionary = {}
	var quiver := entity.stat_board.arrows as Quiver
	if quiver == null or n <= 0:
		return counts
	var remaining := n
	for t in _AMMO_TYPES.sorted():
		if t.id == AmmoTypeRoster.BASE_ID:
			continue
		var take := mini(remaining, quiver.stock_of(t.id))
		if take > 0:
			counts[t.id] = take
			remaining -= take
	var base := mini(remaining, quiver.stock_of(AmmoTypeRoster.BASE_ID))
	if base > 0:
		counts[AmmoTypeRoster.BASE_ID] = base
	return counts


## Bounded melee rollout — see [AiBladeRollout] for the reach-bound rejection
## / steerable-proposal / two-tier-evaluation pipeline. Empty when the entity
## has no territory to pivot from or no candidate reaches a visible enemy.
func _gather_melee_candidates(visible_enemies: Array[SkillNode]) -> Array[AiCombatScorer.ScoredCandidate]:
	return AiBladeRollout.gather_melee_candidates(entity, visible_enemies, ai_tier, rng)


## Two-tier gated (#537 D1/D3): [method AttackPlan.is_valid] is the cheap PASS
## 1 — no shadow world, no snapshot (see [method AttackPlan.validate]) — so
## every reachable target is enumerated and cheaply ranked for free. Only the
## top [constant _CANDIDATE_GATE_K] then pay for the real
## [method AttackPlan.resolve] in PASS 2. `order.sort()` after the promotion
## restores fog-list order among the survivors: below the gate (the common
## case in every existing fixture — visible-enemy counts rarely exceed K) this
## is byte-for-byte the old exhaustive enumeration, same order, same scores.
func _gather_ranged_candidates(visible_enemies: Array[SkillNode]) -> Array[AiCombatScorer.ScoredCandidate]:
	var out: Array[AiCombatScorer.ScoredCandidate] = []
	var raw_damage: float = float(entity.stat_board.ranged_damage.value) \
			if entity.stat_board != null and entity.stat_board.ranged_damage != null else 0.0
	var reachable: Array[SkillNode] = []
	for target in visible_enemies:
		var plan := RangedAttackPlan.new()
		plan.attacker = entity
		plan.target = target
		if plan.is_valid():
			reachable.append(target)
	var order := AiBladeRollout.top_k_indices(
			reachable,
			func(a: SkillNode, b: SkillNode) -> bool:
				return AiCombatScorer.cheap_estimate(a, raw_damage) > AiCombatScorer.cheap_estimate(b, raw_damage),
			_CANDIDATE_GATE_K)
	last_ranged_candidate_count = reachable.size()
	last_ranged_promoted_count = order.size()
	order.sort()
	for i in order:
		var target := reachable[i]
		var plan := RangedAttackPlan.new()
		plan.attacker = entity
		plan.target = target
		# Size the volley to the kill (#958): resolve the LARGEST volley the
		# leaves and quiver allow, read arrows-to-kill off that outcome, and
		# — when it kills with arrows to spare — re-resolve at kill + margin
		# so the scored outcome IS the launched one. No kill on the table:
		# fire everything (the chip is as large as it can be). Never one
		# arrow when more would do — "never single-shots".
		plan.ammo_counts = _compose_volley(plan.max_n())
		var outcome := plan.resolve()
		var to_kill := AiCombatScorer.arrows_to_kill(outcome, target, entity)
		if to_kill > 0 and to_kill + KILL_MARGIN_ARROWS < plan.n():
			plan.ammo_counts = _compose_volley(to_kill + KILL_MARGIN_ARROWS)
			outcome = plan.resolve()
		var c := AiCombatScorer.score(BattleSystem.AttackMode.RANGED, outcome, target, entity, ai_tier)
		c.ammo_counts = plan.ammo_counts.duplicate()
		c.trace += " n=%d" % plan.n()
		out.append(c)
	return out


## Every (known spell × eligible casting source × visible hostile target)
## combination whose plan validates. No spellbook / no known spells -> no
## magic candidates, same as a naive entity that never learned one.
##
## [b]Reachability comes from #728's shared [SpellTargetUnion][/b] (#745) — one
## [method SpellTargetUnion.build] per spell, whose [method RangeFinder.gather_multi]
## walks every eligible caster in a single pass.
##
## What that replaces: the pre-#745 loop stamped a source onto a fresh probe
## plan and asked [method AttackPlan.get_node_role]. That falls through to
## [method MagicAttackPlan._rebuild_target_cache], which builds the plan's
## union — a WHOLE-TERRITORY gather over every eligible caster — just to read
## one source's row out of it. A fresh probe per owned node meant that whole
## build ran once PER OWNED NODE, per spell, per turn. Same candidates, same
## scores, same order: the range test stops being a traversal and becomes a
## dictionary lookup.
##
## The union's [member SpellTargetUnion.best_source] collapse is deliberately
## NOT used. It auto-picks a caster by node-local `spell_damage` alone, while
## the loop below scores every (source, target) pair fully and lets
## [method AiCombatScorer.pick_best] decide — which strictly dominates that
## heuristic. Only the ENUMERATION is shared, never the pick.
##
## Fog stays here ([param visible_enemies], off [method AiRecon.visible_enemy_nodes]):
## the union answers reachability only, and each caller applies its own viewer's
## fog.
##
## [b]The intersection is taken from the REACH side[/b] — the smaller one.
## [member SpellTargetUnion.per_source] is already ownership-filtered, so it
## holds the hostile nodes inside this spell's ball (a handful), while
## [param visible_enemies] holds every fog-visible hostile node and grows with
## the board. Enumerating the reach and testing fog membership therefore costs
## O(reach) per source instead of O(visible).
##
## The fog list's ORDER is then re-imposed via [code]visible_order[/code],
## because [method AiCombatScorer.pick_best] breaks a score tie by
## first-appended: appending in the range finder's gather order would silently
## re-decide ties that the pre-#745 implementation settled the other way. The
## sort is over the intersection only, which is why it is free.
##
## The range test itself stays necessary — [method AttackPlan.is_valid] cannot
## stand in for it. validate() checks presence and source degree only, and
## [method AttackPlan.resolve] trusts a set target unconditionally (it exists to
## preview/commit a UI-picked target, not to re-validate one), so dropping it
## would let the AI "cast" at an out-of-hop-range target and still score a hit.
## Two-tier gated since #537 (D1/D3) — PASS 1 below enumerates every
## (spell, source, target) combination exactly as before (still cheap:
## [method AttackPlan.is_valid] never resolves), then PASS 2 promotes only the
## top [constant _CANDIDATE_GATE_K], globally across every spell and source
## this turn, to a real gate-accurate [method AttackPlan.resolve]. Below the
## gate — every existing fixture, whose spell/source/target counts are small —
## this is byte-for-byte the old exhaustive behaviour: same candidates, same
## order, same scores.
func _gather_magic_candidates(visible_enemies: Array[SkillNode]) -> Array[AiCombatScorer.ScoredCandidate]:
	var out: Array[AiCombatScorer.ScoredCandidate] = []
	if entity.spellbook == null or entity.navigator == null:
		return out
	var spells := entity.spellbook.spells
	if spells.is_empty():
		return out
	var mana: PoolStat = entity.stat_board.mana if entity.stat_board != null else null
	var graph := entity.navigator.graph
	# Visible enemy -> its index in the fog list, built once for the whole
	# gather. Doubles as the fog membership test and as the sort key that
	# restores this function's candidate order — see the note above.
	var visible_order: Dictionary[SkillNode, int] = {}
	for i in visible_enemies.size():
		visible_order[visible_enemies[i]] = i

	# PASS 1 — identity only, no resolve. Each entry is
	# [SpellDef, SkillNode source, SkillNode target, float raw_damage];
	# raw_damage is the seed-hit formula's own un-mitigated input
	# (spell_damage(source) x power — attack/spell/spell_resolver.gd:321),
	# constant per (spell, source) so it's read once per source, not once per
	# target.
	var pre: Array = []
	for spell in spells:
		# MagicAttackPlan.validate() deliberately doesn't gate on mana (a
		# preview/UI concern, not a plan-shape one) — BattleSystem.launch_attack
		# bails on insufficient mana WITHOUT deducting AP or clearing the plan,
		# so an unaffordable spell must never win pick_best or the AP loop
		# stalls with AP left unspent (violates the 1-damage floor). Filter
		# here, the one place that actually knows the entity's current mana.
		if mana != null and mana.current < float(spell.mana_cost):
			continue
		var union := SpellTargetUnion.build(spell, entity, graph)
		# `sources` and not `per_source`: the latter is keyed in gather_multi's
		# own order, while `sources` is a filtered subsequence of
		# get_mirrored_nodes() — the order the pre-#745 loop walked. It is also
		# already min_degree-filtered, so the ineligible sources that used to be
		# probed and then thrown away by is_valid() never enter the loop at all.
		for source in union.sources:
			# .get() and not targets_from(): this reads the row, and does not
			# need the defensive copy that view makes.
			var reachable: Dictionary = union.per_source.get(source, {})
			if reachable.is_empty():
				continue
			# Sorting the INDICES rather than the nodes keeps this a plain
			# integer sort with no comparator closure per source.
			var picked: Array[int] = []
			for candidate: SkillNode in reachable:
				var at: int = visible_order.get(candidate, -1)
				if at >= 0:
					picked.append(at)
			if picked.is_empty():
				continue
			picked.sort()
			var raw_damage := float(source.get_local_value(&"spell_damage")) * spell.power
			var probe := MagicAttackPlan.new()
			probe.attacker = entity
			probe.spell = spell
			probe.source = source
			for at in picked:
				var target := visible_enemies[at]
				probe.target = target
				if probe.is_valid():
					pre.append([spell, source, target, raw_damage])
				probe.target = null

	# PASS 2 — cheap-rank the WHOLE turn's magic candidates (across every
	# spell/source) and promote only the top K to a real resolve.
	# `order.sort()` restores PASS 1's own enumeration order among the
	# survivors: the #745 characterization tests pin THAT order (fog order
	# within a source, source order within union.sources, spell order within
	# the spellbook), never cheap-score order.
	var order := AiBladeRollout.top_k_indices(
			pre,
			func(a: Array, b: Array) -> bool:
				return AiCombatScorer.cheap_estimate(a[2], a[3]) > AiCombatScorer.cheap_estimate(b[2], b[3]),
			_CANDIDATE_GATE_K)
	last_magic_candidate_count = pre.size()
	last_magic_promoted_count = order.size()
	order.sort()
	for i in order:
		var entry: Array = pre[i]
		var spell: SpellDef = entry[0]
		var source: SkillNode = entry[1]
		var target: SkillNode = entry[2]
		var probe := MagicAttackPlan.new()
		probe.attacker = entity
		probe.spell = spell
		probe.source = source
		probe.target = target
		var outcome := probe.resolve()
		var c := AiCombatScorer.score(BattleSystem.AttackMode.MAGIC, outcome, target, entity, ai_tier)
		c.source_node = source
		c.spell = spell
		out.append(c)
	return out


## Re-requests the mode fresh off [BattleSystem] (which stamps the live
## `attacker`) and copies the scored candidate's target/source/spell onto it,
## rather than committing the throwaway plan [method _gather_ranged_candidates]
## / [method _gather_magic_candidates] scored against — BattleSystem owns the
## one live [member BattleSystem.attack_plan] and its signal-driven UI/VFX
## seam, so scoring must not mutate it N times per turn.
func _execute_candidate(candidate: AiCombatScorer.ScoredCandidate) -> bool:
	var bs := _battle_system()
	if bs == null or candidate == null:
		return false
	bs.request_attack_mode(candidate.mode)
	match candidate.mode:
		BattleSystem.AttackMode.RANGED:
			var plan := bs.attack_plan as RangedAttackPlan
			if plan == null:
				return false
			plan.target = candidate.target
			# The N that was scored is the N that fires (#958).
			plan.ammo_counts = candidate.ammo_counts.duplicate()
		BattleSystem.AttackMode.MAGIC:
			var plan := bs.attack_plan as MagicAttackPlan
			if plan == null:
				return false
			plan.source = candidate.source_node
			plan.spell = candidate.spell
			plan.target = candidate.target
		BattleSystem.AttackMode.MELEE:
			var plan := bs.attack_plan as MeleeAttackPlan
			if plan == null:
				return false
			plan.source = candidate.source_node
			plan.blade_nodes = candidate.blade_nodes
			# Not cosmetic, and not optional: the rollout ranked and resolved
			# THIS direction. `request_attack_mode` seeds a fresh plan from
			# `BattleSystem.next_melee_cw` — the HUMAN's sticky tray toggle —
			# so leaving it alone makes an AI swing whichever way the player
			# last chose, which is neither what was scored nor reproducible.
			plan.swing_cw = candidate.swing_cw
			# #823 requirement 9: arm the SAME handle the rollout scored —
			# same shape [member AiCombatScorer.ScoredCandidate.swing_cw]
			# above is, and same reason: a phantom clamp only ever existed to
			# be scored (`MeleeAttackPlan.ai_phantom_clamp_nodes`), so
			# launching without turning it into a real temp-upgrade addon
			# would execute a floppier blade than the one that won. No new
			# command (owner, 2026-08-21: AI is host-only, so direct calls
			# are fine) — the same door `apply_temp_upgrade`'s UI caller uses.
			for node in candidate.clamp_nodes:
				bs.toggle_temp_upgrade_on(node, bs.temp_upgrade_by_id(&"clamp"))
		_:
			return false
	if not bs.attack_plan.is_valid():
		bs.cancel_attack()
		return false
	# A plain call, and deliberately so: since #511 `launch_attack` IS the
	# routing — it builds the [LaunchAttackCommand], submits it, and awaits that
	# command's own `command_applied`. Building a command here instead would be
	# a second implementation of one verb. Composing the plan above is likewise
	# local composition, exactly what PlayerInputController does without a
	# command.
	#
	# Why this is not a hole in #512's "no direct mutating system call" grep —
	# **owner call 2026-08-21:** *"hmm well AI will only be ran by the host, so
	# to me it matters little how they do it, via a command or directly.
	# clients won't ever run AI controllers anyway."*
	await bs.launch_attack()
	return true


# --- the one door out into the world ---------------------------------------

## Submit [param command] and suspend until the applier has actually applied
## it, returning the applier's own verdict — the AI's replacement for reading a
## gated system call's return value (#512).
##
## Waiting is not optional: the next decision is scored against the board this
## command changes. Two arrival shapes, both handled by the same code:
##
## [b]Idle applier[/b] — [method CommandApplier.submit] drains synchronously, so
## `watch` has already fired by the time it returns and the loop never suspends.
## Identical to the direct call this replaced, which is what makes the parity
## test (test/unit/test_ai_command_parity.gd) hold.
##
## [b]Mid-drain[/b] — an AI turn started from inside an [EndTurnCommand]'s
## application, so [member CommandApplier.is_applying] is already true and this
## command is QUEUED behind it. Awaiting yields back up to that drain, which
## applies the command and resumes us from inside its own
## [signal CommandApplier.command_applied] emit. The queue is FIFO, so the
## command we are waiting on always arrives.
func _submit_and_wait(command: Command) -> bool:
	var applier := _command_applier()
	if applier == null or command == null:
		return false
	# An Array as the latch, not two locals: a lambda captures locals BY VALUE.
	var verdict: Array[bool] = [false, false] # [applied, success]
	var watch := func(applied: Command, ok: bool) -> void:
		if applied == command:
			verdict[0] = true
			verdict[1] = ok
	applier.command_applied.connect(watch)
	applier.submit(command)
	while not verdict[0] and applier.is_applying:
		await applier.command_applied
	applier.command_applied.disconnect(watch)
	return verdict[1]


## Fire-and-forget submit, for the one command whose verdict the AI has no use
## for: its own end-of-turn. Warns rather than silently no-opping when nothing
## is wired — an AI that cannot mutate is a wiring bug, not a pacifist.
func _submit(command: Command) -> void:
	var applier := _command_applier()
	if applier == null:
		push_warning("AIController: no CommandApplier wired; dropping '%s'" \
				% command.type_tag())
		return
	applier.submit(command)


# --- helpers ---------------------------------------------------------------

## Bail if the turn has already ended or the entity died mid-turn. Keeps the
## action sequence from racing on side effects.
func _continue() -> bool:
	return _turn_manager != null \
			and _turn_manager.current_entity == entity \
			and is_instance_valid(entity)


func _wait() -> void:
	if turn_delay > 0.0:
		await get_tree().create_timer(turn_delay).timeout


## The board, reached through the entity's own navigator (the same route
## [method _pick_frontier_node] already uses). Needed to turn a picked
## [SkillNode] into the [member SkillNode.stable_id] a [Command] carries —
## reading `node.stable_id` directly is the trap [method Graph.get_stable_id]
## documents.
func _graph_or_null() -> Graph:
	return entity.navigator.graph if entity != null and entity.navigator != null else null


func _game_root_or_null() -> GameRoot:
	if _game_root != null:
		return _game_root
	var n: Node = entity
	while n != null:
		if n is GameRoot:
			_game_root = n
			return _game_root
		n = n.get_parent()
	return null


func _command_applier() -> CommandApplier:
	if command_applier_override != null:
		return command_applier_override
	var gr := _game_root_or_null()
	return gr.command_applier if gr != null else null


func _battle_system() -> BattleSystem:
	if battle_system_override != null:
		return battle_system_override
	var gr := _game_root_or_null()
	return gr.battle_system if gr != null else null
