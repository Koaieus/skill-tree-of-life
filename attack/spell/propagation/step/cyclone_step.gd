@tool
class_name CycloneStep
extends FanAllStep

## [FanAllStep] plus the cycle bookkeeping Cyclone's identity is made of. Fans
## to every candidate the filter allowed, then stamps each minted child with
## whether that hop CLOSED a cycle, with the ring it closed, and with the set
## the child may not travel back into.
##
## [b]The bookkeeping happens at MINT, not at landing[/b], and it has to: at
## mint the child knows both its destination and its parent's trail, which is
## exactly the pair the question needs. By the time it lands, `_propagate_to`
## has already appended the destination to `visited` — the answer is
## unrecoverable. So the step stamps [member CastSpell.closed_cycle] and
## [CycleCritCondition] reads it, per the Design A split
## [ConvergenceCritCondition] documents.
##
## The rule, per hop into candidate `nb`:
## [codeblock]
## idx    = payload.visited.find(nb)      # BEFORE _propagate_to appends it
## closed = idx >= 0
##
## closed  → visited = closed_ring(payload.visited, idx),  came_from = []
## ¬closed → visited = payload.visited + [nb],             came_from = [payload.current_node]
## [/codeblock]
##
## [b]Why the trail truncates to the ring instead of resetting to the node
## (#699).[/b] A reset made the storm forget the loop the instant it found it,
## so the lap home crit fired and the next three hops went quiet. Truncating
## keeps exactly the ring and nothing else, which is what makes the grind
## crit every beat once the loop is closed — and what keeps that grind
## [i]honest[/i] in dense territory, where a never-reset footprint would cover
## everything by wave 2 and degrade the crit into a flat damage multiplier.
##
## [b]Why the short case takes the complementary arc.[/b] On triangle ABC after
## the lap home the trail is `[B,C,A]`, and the hop `A → C` finds C one step
## back: the forward arc is the single edge, so a naive truncation would leave
## the lineage holding `[A,C]`, ping-ponging A↔C and closing a "cycle" of
## length 2 forever. But that hop really did close the triangle — the other way
## round — so the ring it keeps is the whole ring, rotated. The hop crits
## either way; what the case decides is what the lineage remembers next.
##
## [b]The invariant all of this buys[/b], and the reason it beats both rejected
## alternatives: the trail is always ring + all-distinct tail, so a close is
## always a back-edge onto a SIMPLE walk. Every crit therefore certifies a
## genuine simple cycle of length ≥ 3 — never a closed walk that laps back
## through a vertex it already used. Minimum length 3 falls out; no gate needed.
##
## [b]Why the veto is the immediate predecessor and not the whole trail.[/b]
## Vetoing the trail would make a cycle unclosable — on a triangle A→B→C, C
## could never step back onto A, which is the very hop the spell exists to
## reward. Only "where I just came from" is barred, and only until the loop
## closes; a closing mint clears it outright so the storm re-seeds and fans
## both shoulders again. Self-loops are barred by [NoSelfLoopFilter] and not by
## this set — relying on `came_from` for that was the bug #699 fixed.
##
## Cycle detection needs no algorithm. The walk is its own DFS, so closing a
## cycle IS a back-edge onto your own trail: one `find` against the trail
## [method PropagationStep._propagate_to] already maintains, which doubles as
## the ring's own starting index. The graph theory that enumerates a graph's
## cycles answers a question this spell never asks — it only ever asks "did I
## just close one, and which one", and it is standing on the answer.


## Shortest ring worth remembering. Below this the "cycle" is the reversal edge
## itself, which is a footprint the lineage would ping-pong on forever.
const MIN_RING := 3


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
		var idx := payload.visited.find(child.current_node)
		if idx < 0:
			child.closed_cycle = false
			child.came_from = [payload.current_node]
			continue
		child.closed_cycle = true
		child.came_from = []
		child.visited = closed_ring(payload.visited, idx)
	return out


## The ring a closing hop just walked, ending at the landed node — which is
## where the front now stands, and where the next hop measures its own trail
## from. [param idx] is the landed node's previous position in [param trail].
##
## Normally that is the trail's suffix from `idx`: the pre-cycle tail is
## discarded and what is left is exactly the loop.
##
## [b]The short case is a reversal, and it takes the long way round.[/b] The
## one hop that can measure under [constant MIN_RING] is a step back onto the
## node one behind — reachable only immediately after a close, when the veto
## has just cleared and the trail is a bare ring. The forward arc between them
## is the single edge, but the cycle that hop closes is the [i]complementary
## arc[/i]: the whole ring, the other way. So rotate rather than truncate —
## same nodes, re-ordered to end where the front now stands, which is a real
## walk because a ring's ends are adjacent.
##
## [b]Never append.[/b] An earlier cut kept the parent trail and appended the
## landed node on the short branch, which put a node in the trail twice; two
## hops later [method Array.find] returned the FIRST occurrence, the slice ran
## long, and the guard waved through a "ring" like `[C,A,C,B]`. That certifies
## a vertex-repeating closed walk — the exact shape #699 exists to refuse.
## Truncating on every close is what keeps the trail all-distinct, and the
## all-distinct trail is what makes every crit a real simple cycle.
static func closed_ring(trail: Array[SkillNode], idx: int) -> Array[SkillNode]:
	var landed: SkillNode = trail[idx]
	var forward: Array[SkillNode] = trail.slice(idx + 1)
	forward.append(landed)
	if forward.size() >= MIN_RING:
		return forward
	var complementary: Array[SkillNode] = trail.slice(idx + 1)
	complementary.append_array(trail.slice(0, idx + 1))
	# Below MIN_RING either way there is no ring to keep — a trail too short to
	# hold one. Unreachable while the self-loop veto holds; harmless if it ever
	# is not, since the forward arc is still all-distinct.
	return complementary if complementary.size() >= MIN_RING else forward


func get_description() -> String:
	return "Fans onward without ever doubling back, and keeps the loops it closes."
