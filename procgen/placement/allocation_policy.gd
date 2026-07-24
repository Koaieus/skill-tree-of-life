@tool
class_name AllocationPolicy
extends Resource

## Picks the next node an entity should claim. Shared between spawn-time
## territory seeding ([TerritorySeeder], via [method AllocationSystem.force_allocate])
## and runtime AI allocation (`AIController`, via the gated
## [method AllocationSystem.allocate]) — see D-24 in docs/design/mvp_decisions.md
## and #275.
##
## NEVER reaches for `graph` or `navigator` itself — the caller supplies the
## exact candidate set to choose from. The seeder passes the frontier over the
## whole graph; a future sensed-subgraph AI passes only what it can see. This
## is the same rule `.claude/rules/graph.md` pins for
## `RangeFinder.gather(source, mirror)`: "gather traverses whatever mirror
## it's handed. That divergence is the point." Same pattern, same reason.
##
## Only picks — never applies (force_allocate vs. allocate is the caller's
## call) and never gates (SP/AP checks live in AllocationSystem).

## Determinism seam for policies that need tie-break randomness (the greedy
## BFS ball's uniform pick among equally-near frontier candidates). Callers
## that care about reproducibility (TerritorySeeder) assign a freshly-seeded
## RNG before each call; policies with no randomness (e.g. a first-match AI
## picker) simply never read it. Not `@export`ed — RandomNumberGenerator is a
## RefCounted, not a Resource/Node/built-in/enum, so Godot rejects it as an
## exported property.
var rng: RandomNumberGenerator


## Returns null if no viable pick exists among [param candidates].
## [param objective] is a switchable-off tactics hook (D-24) — the seeder
## always passes a neutral/null objective; only a future tactical AI policy
## would interpret it.
func pick_next(_entity: Entity, _candidates: Array[SkillNode], _objective) -> SkillNode:
	push_error("AllocationPolicy.pick_next is abstract — override in a subclass")
	return null
