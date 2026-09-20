class_name SwingContext
extends RefCounted
## Everything one [SwingResolve] run consumes, and nothing else (#1003).
##
## The resolver used to reach back into its [MeleeAttackPlan] for every one of
## these; this is that reach-in made explicit as a value, so a swing can be
## resolved from anything that can BUILD a blade — the plan today,
## [AiBladeRollout] tomorrow — without holding a plan. It carries the BUILT
## inputs (a [BladeState] with its defender field already attached, the
## drivers) rather than the blade node list, because building a state from
## nodes is the plan's job ([method MeleeAttackPlan.build_blade_state]: induced
## edges, addons, phantom clamps) and the resolver never read the nodes
## themselves.
##
## A null [member state] is the "invalid plan" shape: the run constructs its
## outcome, marks itself done and produces no trajectory — exactly what the
## resolver did when [method AttackPlan.is_valid] failed.

## The blade to swing, defender field attached, at its START pose. Null when
## there is nothing to swing.
var state: BladeState = null
## The arc drivers pulling that blade round — [method MeleeAttackPlan.build_drivers].
var drivers: Array[BladeDriver] = []
## The world the swing lands its hits on. A shadow for a prediction or a
## mirror's resim, the live one for the authority's resolve.
var world: CombatWorld = null
## Who swings. May be null in a bare test; the pop gate tolerates it.
var attacker: Entity = null
## The board the hit scan reads node identity off. May be null.
var graph: Graph = null
## Where the blade collides — null when the pivot is not in a scene tree, in
## which case the swing is simulated but scans nothing.
var space_state: PhysicsDirectSpaceState2D = null
## Bodies the scan never hits (the blade itself, the attacker's and allies'
## territory) — [method MeleeAttackPlan.collect_target_excludes].
var excludes: Array[RID] = []
## The pivot node; what every hit names as its [member HitInstance.origin].
var origin: SkillNode = null
## What every hit names as its [member HitInstance.source] — the plan, when
## there is one. Typed as the field it fills.
var hit_source: Variant = null
## The stamped crit seed ([member AttackPlan.resolve_seed]); 0 for an
## unstamped preview.
var resolve_seed: int = 0
## Sim parameters. Defaults are the authoritative / aim-time values.
var swing_duration: float = MeleeAttackPlan.SWING_DURATION
var dt: float = BladeSim.DEFAULT_DT
## #796: the peer draw-only resim's fidelity knob — only
## [method MeleeAttackPlan.begin_replay_resolve] ever lowers these.
var substeps: int = BladeSim.DEFAULT_SUBSTEPS
var enable_length_scaling: bool = true
