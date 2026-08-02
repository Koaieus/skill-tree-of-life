# Degree — one question, three legitimate answers, zero hand-rolling

Degree drives real mechanics (Leafblower's downhill walk, the `min_degree`
cast gate, Bruiser's ranker, TrailBlazer's junction slam), so "how many edges
does this node have" has to give the same answer everywhere. It didn't, and
the divergence was invisible: every wrong call still returned a plausible int.

## The three accessors

| Call | Means | Use when |
|---|---|---|
| `SkillNode.get_graph_degree(graph)` | every incident edge, any owner | the rule is about board-wide connectedness (DegreeRanker, TrailBlazerStep) |
| `SkillNode.get_entity_degree(graph, entity = null)` | degree in the induced subgraph of `entity`'s nodes; defaults to the node's own `owned_by` | **the default for gameplay rules** — territory shape is what the player reads and plays against |
| `GraphMirror.get_degree(node)` | degree inside that mirror (`entity.navigator` = owned subgraph, `graph.navigator` = whole board) | you already hold the mirror (cast gates: `SpellBook`, `MagicAttackPlan`) |

**Never `graph.get_neighbours(n).size()`.** It happens to equal
`get_graph_degree` today, but it is the idiom that produced every
inconsistency below, and it reads as "count the neighbours" — which quietly
invites `for nb in ...: if nb.owned_by == e` re-implementations of
`get_entity_degree` that forget self-loops.

## Self-loops count +2, everywhere

A self-loop is a real `Edge` child with `from == to` (`graph/edge.gd` registers
it into `from.self_loops`). `Graph._adjacency` appends **both** endpoints, so
`get_neighbours` lists the node itself twice and both `SkillNode` accessors
inherit the +2 for free. `GraphMirror.get_degree` can't — AStar won't hold a
self-edge — so it adds `+ 2 * node.self_loop_count` explicitly.

Verified equal: one self-loop on a degree-2 node reads 4 from all three.

This is what makes fortification legible: two self-loops turn a degree-2 node
into a degree-6 node, and a downhill walk turns away from it.

## The one place they diverge: parallel edges

`_adjacency` appends per edge; AStar dedupes by point pair. Two edges between
the same pair read 2 from `get_graph_degree` and 1 from `GraphMirror`.
Nothing emits parallel edges today — procgen doesn't, and `Graph.add_edge`
doesn't check. If that changes, this is the seam.

## Entity degree on a node you don't own

`get_entity_degree(graph, red)` on an *unowned* node counts its red-owned
neighbours — it is **not** 0. That's why the `entity` parameter defaults to
`owned_by`: the defaulted call is the one that means "how connected is this
node within its own land", and it reads 0 for an unallocated node.

## History

`DegreeFilter`, `DegreeRanker`, `TrailBlazerStep`, `ExpressionFilter` and
`LeafCritCondition` all hand-rolled graph degree while the cast gate
(`SpellBook._node_meets_source_requirements`, `MagicAttackPlan`) used entity
degree via the navigator mirror. Leafblower therefore gated on entity degree
and then walked on graph degree — and on a contested board a defender's
dangling leaf is routinely adjacent to two enemy nodes, so graph degree read
it as a hub and hid it from the very walk the spell exists to perform.
