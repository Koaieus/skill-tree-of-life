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
## Only magic reads it today; melee and ranged consume no randomness at all
## (crit lives solely in [SpellResolver] — see
## `test/unit/attack/test_attack_determinism.gd`). When crits reach those
## modes they must draw from here, not from the global RNG.
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


## error messages, empty = valid
@abstract func validate() -> Array[String]


## Pure resolution — what would happen if this plan were committed right now.
## Called for BOTH preview (UI tooltips, AI scoring) and commit (the launch
## flow drives VFX off these hits then applies them). Implementations should
## be side-effect free: no state mutation on the plan, attacker, or any node.
@abstract func resolve() -> AttackOutcome

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
