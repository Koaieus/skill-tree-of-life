class_name SwingResult
extends RefCounted
## Everything one swing resolution produced, in one bundle (#782).
##
## [b]Why this exists.[/b] [method MeleeAttackPlan.resolve_against] used to
## publish its artifacts straight onto the [code]last_*[/code] fields, which
## made "resolve a swing" and "declare that swing the committed one" the same
## act. The preview needs the first without the second: it resolves the CURRENT
## selection against a throwaway shadow purely to draw it, and must not touch
## the artifacts [MeleePreview.launch] replays for the swing the authority
## actually landed. So [method MeleeAttackPlan._resolve_swing] is the single
## implementation, and the two callers differ only in where they put the
## result — see the repo rule against parallel mirrors of the same logic.
##
## Lifted out of [MeleeAttackPlan] by #1003; the engine that fills it is
## [SwingResolve].

var outcome: AttackOutcome = null
var trajectory: BladeTrajectory = null
var events: Array[BladeHitEvent] = []
var pops: BladePopResolver.Result = null
var live_gate: BladePopResolver.LiveGate = null
var hits: Array[HitInstance] = []
## The swing's own drag clock and defender field, at their END state. Both
## null exactly when [method MeleeAttackPlan.build_defender_zones] came back
## empty — the ordinary swing, which allocates neither. Since #811 they
## travel together: one field, one clock, or neither.
var clock: BladeSwingClock = null
var obstacles: BladeObstacleField = null
