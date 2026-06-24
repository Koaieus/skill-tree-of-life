@tool
class_name MaxVisitsFilter
extends PropagationFilter

## Blocks onward copies into nodes that have already been resolved
## [code]config.max_visits_per_node[/code] times during this cast. Reads
## [member PropagationContext.global_visit_count]. The default cap of 1
## yields the classic never-revisit behaviour; setting it high (Resonator
## territory) lets the spell loop through self-loops + cycles.
##
## Reads its cap off the [PropagationConfig] the resolver is currently
## running with — passed in via the [code]payload[/code] back-reference is
## awkward, so the resolver injects [member cap] before each filter call.
## To keep filters stateless, we instead embed the cap on the filter itself
## and let [PropagationConfig] mirror its [code]max_visits_per_node[/code]
## onto this filter at compose time. For now: read [member cap] directly,
## and let [PropagationConfig.max_visits_per_node] live on the config as
## the source of truth; this filter has a fallback default.

## Override of the cap. -1 = read off the active config (the resolver sets
## this before stepping). Any non-negative value pins it.
@export var cap_override: int = -1
## Fallback cap when no override and no config-managed value is supplied.
@export var fallback_cap: int = 1


func allows(_from: SkillNode, to: SkillNode, _payload: CastSpell, ctx: PropagationContext) -> bool:
	var cap := cap_override if cap_override >= 0 else fallback_cap
	return ctx.visit_count(to) < cap


func get_description() -> String:
	if cap_override >= 0:
		return "Each node hit at most %d time(s)." % cap_override
	return ""
