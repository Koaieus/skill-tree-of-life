@tool
@abstract
class_name PropagationReach
extends Resource

## "Where can this landing's wave go?" — the candidate set a departure starts
## from, and nothing else. [SpellResolver] asks it once per landing, in place of
## the graph neighbours, when [member PropagationConfig.reach] is set; null
## keeps the neighbours.
##
## The reach only proposes. The visit cap, [method PropagationFilter.narrow],
## [method PropagationSpread.select] and [method PropagationConfig.mint] all run
## on its answer unchanged, so a reach cannot dodge the filter or the
## per-node visit cap. A candidate need not share an edge with
## [member LandingContext.node].


## The nodes this landing's wave may go to, before the cap and the filter.
## Order is the order the filter and spread see.
@abstract func candidates(lctx: LandingContext) -> Array[SkillNode]


## One tooltip line for [method PropagationConfig.get_description]; "" = none.
@abstract func get_description() -> String
