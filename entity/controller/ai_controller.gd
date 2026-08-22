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
## Fog-aware since #378: each AI consults [AiRecon] for its OWN visibility
## (not the shared player-only VisionSystem instance) — settled 2026-08-07,
## "each enemy acts only on what it personally sees", no faction-shared
## reveal in v1. Faction filtering uses [member Entity.faction] so future
## multi-faction support drops in trivially.

const _DEFAULT_TURN_DELAY := 0.4

## Synced from Settings.current.ai_turn_delay at _ready unless a caller
## already overrode it (tests set this explicitly before add_child, to a
## value other than the compile-time default, to control pacing/avoid
## take_turn recursion — see .claude/rules/turn-manager.md).
@export var turn_delay: float = _DEFAULT_TURN_DELAY
## Tier-gates [AiCombatScorer]'s cut-vertex / enemy-weak-point / self-shape-
## risk bonuses. 0 = naive, picks by raw EV. Kept here (not on the scorer)
## since it's the controller's single behavior-shaping knob.
@export var ai_tier: int = 0
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


func _on_settings_changed(key: StringName, value: Variant) -> void:
	if key == &"ai_turn_delay":
		turn_delay = value


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
	# fog short-circuit only gates the ATTACK step below. Territory changes
	# each allocation, so recon is re-run each pass (a new leaf can put a
	# previously-out-of-range hostile in vision).
	if entity.stat_board != null:
		var sp: SkillPointStat = entity.stat_board.skill_points
		if sp != null:
			# Same loop as before #512, un-inlined because the allocation now
			# suspends until the applier has applied it — `await` cannot live
			# inside a `while` condition.
			while sp.current > 0 and _continue():
				if not await _try_allocate_frontier(visible_enemies):
					break
				await _wait()
				visible_enemies = AiRecon.visible_enemy_nodes(entity)
				saw_hostile = saw_hostile or not visible_enemies.is_empty()

	if not saw_hostile:
		_decide("no visible hostile — growth only")
		_end_turn()
		return

	# AP×2 loop: score every ranged/magic candidate against every visible
	# hostile, execute the best, re-evaluate — the board changed (a dent, a
	# kill), so re-running recon + enumeration each pass is what makes
	# dent-then-finish fall out naturally instead of needing special-casing.
	if entity.stat_board != null:
		var ap: PoolStat = entity.stat_board.action_points
		while ap != null and ap.current > 0 and _continue():
			visible_enemies = AiRecon.visible_enemy_nodes(entity)
			if visible_enemies.is_empty():
				break
			var best := _best_attack_candidate(visible_enemies)
			if best == null:
				_decide("no reachable attack this turn")
				break
			# BattleSystem.launch_attack() has bail-outs (insufficient AP for
			# outcome.ap_cost, insufficient mana) that return WITHOUT deducting
			# AP or clearing the plan — _execute_candidate still reports true
			# since it awaited the call. Without this guard the loop would
			# re-enumerate, re-pick the same candidate, and spin forever
			# (synchronously, at turn_delay = 0). Break on no observed AP
			# progress instead of trusting the return value alone.
			var ap_before := ap.current
			if not await _execute_candidate(best):
				_decide("attack execution failed: %s" % best.trace)
				break
			if entity.stat_board.action_points != null and entity.stat_board.action_points.current >= ap_before:
				_decide("attack committed but AP unchanged — stopping: %s" % best.trace)
				break
			_decide(best.trace)
			await _wait()
			ap = entity.stat_board.action_points

	_end_turn()


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
	var frontier := _frontier_candidates(graph)
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


## Every unowned node adjacent to one this entity already owns, deduplicated.
func _frontier_candidates(graph: Graph) -> Array[SkillNode]:
	var out: Array[SkillNode] = []
	var seen: Dictionary[SkillNode, bool] = {}
	for edge in graph.get_edges():
		if edge == null or edge.from == null or edge.to == null:
			continue
		var a := edge.from
		var b := edge.to
		if a.owned_by == entity and b.owned_by == null and not seen.has(b):
			seen[b] = true
			out.append(b)
		if b.owned_by == entity and a.owned_by == null and not seen.has(a):
			seen[a] = true
			out.append(a)
	return out


## Every ranged + magic + melee candidate against every visible hostile,
## scored via [AiCombatScorer].
func _best_attack_candidate(visible_enemies: Array[SkillNode]) -> AiCombatScorer.ScoredCandidate:
	var candidates: Array[AiCombatScorer.ScoredCandidate] = []
	candidates.append_array(_gather_ranged_candidates(visible_enemies))
	candidates.append_array(_gather_magic_candidates(visible_enemies))
	candidates.append_array(_gather_melee_candidates(visible_enemies))
	return AiCombatScorer.pick_best(candidates)


## Bounded melee rollout — see [AiBladeRollout] for the reach-bound rejection
## / steerable-proposal / two-tier-evaluation pipeline. Empty when the entity
## has no territory to pivot from or no candidate reaches a visible enemy.
func _gather_melee_candidates(visible_enemies: Array[SkillNode]) -> Array[AiCombatScorer.ScoredCandidate]:
	return AiBladeRollout.gather_melee_candidates(entity, visible_enemies, ai_tier)


func _gather_ranged_candidates(visible_enemies: Array[SkillNode]) -> Array[AiCombatScorer.ScoredCandidate]:
	var out: Array[AiCombatScorer.ScoredCandidate] = []
	for target in visible_enemies:
		var plan := RangedAttackPlan.new()
		plan.attacker = entity
		plan.target = target
		if not plan.is_valid():
			continue
		var outcome := plan.resolve()
		out.append(AiCombatScorer.score(BattleSystem.AttackMode.RANGED, outcome, target, entity, ai_tier))
	return out


## Every (known spell × owned casting source × visible hostile target)
## combination whose plan validates. No spellbook / no known spells -> no
## magic candidates, same as a naive entity that never learned one.
##
## Filters targets via [method AttackPlan.get_node_role] == IN_RANGE (the
## plan's own cached [method MagicAttackPlan._valid_targets], built once per
## (spell, source) off ONE [method RangeFinder.gather] traversal — see #385)
## rather than [method AttackPlan.is_valid], which only checks presence, not
## reachability: [method AttackPlan.resolve] trusts a set target unconditionally
## (it exists to preview/commit a UI-picked target, not to re-validate one), so
## skipping this filter would let the AI "cast" at an out-of-hop-range target
## and still score a hit.
func _gather_magic_candidates(visible_enemies: Array[SkillNode]) -> Array[AiCombatScorer.ScoredCandidate]:
	var out: Array[AiCombatScorer.ScoredCandidate] = []
	if entity.spellbook == null or entity.navigator == null:
		return out
	var spells := entity.spellbook.spells
	if spells.is_empty():
		return out
	var mana: PoolStat = entity.stat_board.mana if entity.stat_board != null else null
	var owned := entity.navigator.get_mirrored_nodes()
	for spell in spells:
		# MagicAttackPlan.validate() deliberately doesn't gate on mana (a
		# preview/UI concern, not a plan-shape one) — BattleSystem.launch_attack
		# bails on insufficient mana WITHOUT deducting AP or clearing the plan,
		# so an unaffordable spell must never win pick_best or the AP loop
		# stalls with AP left unspent (violates the 1-damage floor). Filter
		# here, the one place that actually knows the entity's current mana.
		if mana != null and mana.current < float(spell.mana_cost):
			continue
		for source in owned:
			var probe := MagicAttackPlan.new()
			probe.attacker = entity
			probe.spell = spell
			probe.source = source
			for target in visible_enemies:
				if probe.get_node_role(target) != HighlightProvider.HighlightRole.IN_RANGE:
					continue
				probe.target = target
				if not probe.is_valid():
					probe.target = null
					continue
				var outcome := probe.resolve()
				var c := AiCombatScorer.score(BattleSystem.AttackMode.MAGIC, outcome, target, entity, ai_tier)
				c.source_node = source
				c.spell = spell
				out.append(c)
				probe.target = null
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
