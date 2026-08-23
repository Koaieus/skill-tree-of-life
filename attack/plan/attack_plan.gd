@abstract
class_name AttackPlan
extends HighlightProvider
## Abstract parent class for a plan for an [Entity] preparing an attack.
##
## Holds shared state (attacker, mode) and the input + visualization contract:
## concrete plans handle [method _on_node_left_clicked] /
## [method _on_node_right_clicked] for input, expose visualization roles via
## [method HighlightProvider.get_node_role], and emit
## [signal HighlightProvider.state_changed] whenever any of their internal state
## shifts (pivot picked, blade toggled, target set, spell selected, etc.).
## BattleSystem rebinds [signal HighlightProvider.state_changed] across plan
## swaps so UI subscribes once to the system, not every plan.
##
## The highlight contract (HighlightRole enum, get_node_role, get_node_range,
## get_range_visual, state_changed) lives on [HighlightProvider] — a plan is one
## kind of highlight provider among several (core-move is another).

var attacker: Entity
var mode: BattleSystem.AttackMode

## The RNG seed [method resolve] runs under — the one input that makes a
## stochastic resolution reproducible.
##
## [b]The authority mints this, not the plan.[/b] Under
## `docs/domain/multiplayer-sync-model.md` the host stamps a seed, resolves
## with it, and posts it alongside the outcome; any peer handed
## (intent + seed) can replay the attack and land on a bit-identical result.
## That is what makes a re-resolve-and-compare desync check EXACT: without
## the seed, a peer's crit draws differ and a mismatch cannot be told apart
## from a genuine divergence.
##
## Per-ATTACK rather than a session-global stream on purpose. A global stream
## makes every peer's result depend on having consumed prior draws in the
## same order — the ordering fragility that sank lockstep in #473. A seed
## carried by the action it resolves has no such coupling.
##
## All three modes read it (#507). Magic arms its propagation walk off it and
## derives a crit stream from it; melee and ranged consume it only for crits,
## via [method CritRoll.stream_for]. Nothing in an attack may draw from the
## global RNG — see `test/unit/attack/test_attack_determinism.gd`.
##
## 0 = "unstamped", which resolves under a FIXED stream. That is deliberate
## for previews and AI scoring: a tooltip that reshuffles its crits on every
## repaint is worse than one showing a stable representative roll. It is
## [b]not[/b] the same roll the real cast will make — the launch path stamps
## a fresh seed.
var resolve_seed: int = 0


## The RNG [method resolve] should draw from, armed off [member resolve_seed].
## Concrete plans with a stochastic resolution call this; deterministic ones
## ignore it.
func seeded_rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = resolve_seed
	return rng


## The plan's wire form (#511) — mode, attacker id, seed. Subclasses call
## `super(graph)` and add their own fields.
##
## [param graph] is required because node ids mint LAZILY: a subclass must
## read one through [method Graph.get_stable_id], never `node.stable_id`,
## or a hand-authored node serializes as 0 and resolves to nothing on the
## far side, silently (`.claude/rules/multiplayer-sync.md`).
##
## What crosses is INPUT only. Resolution residue —
## [member MeleeAttackPlan.last_events] and friends, the `_cached_*` target
## sets — is rebuildable from these fields on any peer and must not ride
## along.
func to_dict(_graph: Graph) -> Dictionary:
	return {
		"mode": int(mode),
		"attacker": attacker.entity_id if attacker != null else 0,
		"seed": resolve_seed,
	}


## Read the base fields back. Subclasses call this from their own
## `static from_dict` before filling in their mode-specific slots — see
## [AttackPlanCodec] for why the dispatch is not a static on this class.
func _read_base(d: Dictionary, graph: Graph) -> void:
	attacker = graph.get_by_entity_id(int(d.get("attacker", 0))) if graph != null else null
	resolve_seed = int(d.get("seed", 0))


## error messages, empty = valid
@abstract func validate() -> Array[String]


## Run this plan in [param world] and return what happened (#536, closing #498
## step 3). Called for BOTH preview (UI tooltips, AI scoring) and commit — the
## launch flow computes its record with this and then replays that record, so
## "the preview is the execution path" is a fact rather than a discipline.
##
## [b]The outcome is ALREADY LANDED in [param world] when this returns.[/b] That
## is the contract, and it is what every gate below depends on: magic's
## candidate filter reads ownership, so wave N's kill has to be in the world
## before wave N+1 selects, and the only honest way to put it there is to land
## it. Ranged and melee do not gate during selection, but they land here too —
## one contract, so a caller never has to know which mode it is holding, and so
## every mode's post-mitigation numbers, cascades and pops are settled by the
## same [OutcomeApplier] pass in every mode.
##
## [b]Which world is the caller's choice, and the real world is never it.[/b]
## Owner call 2026-08-23 — [i]"shadow always"[/i]. Resolution mutates a
## [method CombatWorld.shadow] and nothing else, which is what leaves
## [OutcomeApplier] the sole mutator of the real world with nothing to suppress.
## See [method BattleSystem.apply_launch_command] for the launch path and
## docs/domain/attack-timeline.md for the timeline this sits in.
@abstract func resolve_against(world: CombatWorld) -> AttackOutcome


## [method resolve_against] on a throwaway shadow — what a preview, a tooltip
## or an AI rollout wants, since none of them own a world and all of them must
## leave the real one untouched.
##
## The shadow is freed before this returns, which is safe because an
## [AttackOutcome] holds real [SkillNode]s throughout: a hit's target is its
## IDENTITY, and only the STATE it was resolved against lived in the shadow (see
## [CombatWorld]).
func resolve() -> AttackOutcome:
	var world := CombatWorld.shadow()
	var outcome := resolve_against(world)
	world.free_shadow()
	return outcome

## all required slots filled
func is_valid() -> bool:
	return validate().is_empty()


## Wipe plan-internal selection state back to its initial empty form. Keeps the
## plan instance (and any sticky mode-level preferences like melee swing_cw)
## alive — the UI's RESET button calls this so the player can re-target without
## re-picking the mode. Default is a no-op; subclasses override and emit
## state_changed when they've actually cleared something.
func reset() -> void:
	pass


## Input hooks — concrete plans override the ones they react to. Defaults
## are no-ops so plans only implement what's relevant to their mode.
## (get_node_role / get_node_range / get_range_visual are inherited from
## HighlightProvider — concrete plans override those.)
##
## Left-click always pushes forward: arms the origin, resolves a target, or
## toggles a blade member — whatever the plan's current level expects.
func _on_node_left_clicked(_node: SkillNode) -> void:
	pass


## Right-click always pops exactly one level and ignores which node was
## clicked — see docs/design/click_grammar.md. Returns true if there was a
## level to pop (origin/target cleared); false means the plan was already at
## its floor ("mode armed, no origin"), and the caller
## (PlayerInputController) exits the mode entirely instead.
func _on_node_right_clicked(_node: SkillNode) -> bool:
	return pop()


## The stack-pop primitive: clear the origin level (and everything built on
## it — target, blade members) in one step. Returns false when there was
## nothing set to clear. Also called from a left-click on the origin when it
## fails the mode's own target-validity check (self-targeting fallthrough,
## docs/design/click_grammar.md) — never call this from a left-click for any
## other reason.
func pop() -> bool:
	return false


func _to_string() -> String:
	var cls: String = str(get_script().get_global_name()) if get_script() else "AttackPlan"
	var mode_name: String = BattleSystem.AttackMode.keys()[mode]
	var atk: String = attacker.display_name if attacker != null else "?"
	return "<%s %s by %s>" % [cls, mode_name, atk]
