@tool
class_name NoSelfLoopFilter
extends PropagationFilter

## Vetoes the self-loop hop — travel from a node into itself.
##
## [b]Author this explicitly on any spell that means it.[/b] Self-loops are a
## first-class mechanic here ([Graph] appends a self-looped node to its own
## adjacency twice, per graph theory's degree +2), and every spell has to
## confirm its own intent about them — Resonator [i]wants[/i] the two self
## copies so its SUM merger can weaponise them, Reverberator crits on
## traversing one, Leafblower reads one as +2 degree. See the self-loop open
## question in [code]docs/design/spells.md[/code].
##
## Cyclone refuses them: going nowhere is not a cycle, and a length-1 loop is
## Reverberator's turf. It used to refuse them [i]by accident[/i] — the claim
## was that [BacktrackFilter] covers it, since a self-loop hop has
## [code]to == from == current_node[/code]. That was never true.
## [member CastSpell.came_from] holds the [b]predecessor[/b], never the current
## node, so the veto never fired and a self-loop crit on the very next wave.
## The lesson is the reason this class exists rather than a flag on some other
## filter: an unrelated rule that happens to cover your case is a rule that can
## stop covering it silently.


func allows(
		from_node: SkillNode,
		to_node: SkillNode,
		_payload: CastSpell,
		_ctx: PropagationContext) -> bool:
	return from_node != to_node


func get_description() -> String:
	return "Never travels into itself."
