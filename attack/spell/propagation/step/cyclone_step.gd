@tool
class_name CycloneStep
extends FanAllStep

## [FanAllStep] plus the cycle bookkeeping Cyclone's identity is made of. Fans
## to every candidate the filter allowed, then stamps each minted child with
## whether that hop CLOSED a cycle, and with the set the child may not travel
## back into.
##
## [b]The bookkeeping happens at MINT, not at landing[/b], and it has to: at
## mint the child knows both its destination and its parent's trail, which is
## exactly the pair the question needs. By the time it lands, `_propagate_to`
## has already appended the destination to `visited` and a closing mint has
## reset the trail outright — the answer is unrecoverable. So the step stamps
## [member CastSpell.closed_cycle] and [CycleCritCondition] reads it, per the
## Design A split [ConvergenceCritCondition] documents.
##
## The rule, per hop into candidate `nb`:
## [codeblock]
## closed = nb in payload.visited        # BEFORE _propagate_to appends it
## closed  → visited = [nb],             came_from = []
## ¬closed → visited = payload.visited + [nb], came_from = [payload.current_node]
## [/codeblock]
##
## [b]Why the veto is the immediate predecessor and not the whole trail.[/b]
## Vetoing the trail would make a cycle unclosable — on a triangle A→B→C, C
## could never step back onto A, which is the very hop the spell exists to
## reward. Only "where I just came from" is barred, and only until the loop
## closes.
##
## Cycle detection needs no algorithm. The walk is its own DFS, so closing a
## cycle IS a back-edge onto your own trail: one membership test against the
## trail [method PropagationStep._propagate_to] already maintains. The graph
## theory that enumerates a graph's cycles answers a question this spell never
## asks — it only ever asks "did I just close one", and it is standing on the
## answer.


func step(
		current_node: SkillNode,
		payload: CastSpell,
		candidates: Array[SkillNode],
		config: PropagationConfig,
		ctx: PropagationContext) -> Array[CastSpell]:
	var out := super.step(current_node, payload, candidates, config, ctx)
	for child in out:
		# `payload.visited`, never `child.visited`: the base mint has already
		# appended the destination to the child's copy, so asking the child
		# would answer "yes" every single hop.
		if payload.visited.has(child.current_node):
			child.closed_cycle = true
			child.visited = [child.current_node]
			child.came_from = []
		else:
			child.closed_cycle = false
			child.came_from = [payload.current_node]
	return out


func get_description() -> String:
	return "Fans onward without ever doubling back, until the loop closes."
