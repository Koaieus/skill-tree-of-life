# Degree — one question, three legitimate answers, zero hand-rolling

Degree drives real mechanics (Leafblower's downhill walk, the `min_degree`
cast gate, Bruiser's ranker, TrailBlazer's junction slam), so "how many edges
does this node have" has to give the same answer everywhere. It didn't, and
the divergence was invisible: every wrong call still returned a plausible int.

## The three accessors

| Call | Means | Use when |
|---|---|---|
| `SkillNode.get_graph_degree(graph)` | every incident edge, any owner | the rule is about board-wide connectedness (DegreeRanker) |
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

## Why `get_entity_degree` does not just call the navigator

It looks like hand-rolled duplication of `GraphMirror.get_degree` — "why
reinvent the wheel, badly?" — and it isn't. `entity.navigator` is an
`EntityNavigator`, whose `_should_mirror` admits **only nodes the entity owns**.
So on a node the entity does *not* own, `vertex_id` misses and `get_degree`
returns **`-1`** — not the count of entity-owned neighbours that the section
below contractually requires.

Tried 2026-08-07; `test/unit/spell/test_leafblower_reach.gd` went 7/7 → 2/7,
including a literal `[-1] expected to equal [4]`. The delegation is only
equivalent on the subset of calls where the node is already owned by the entity
being asked about, and the accessor exists precisely to serve the other case.

Two further reasons it stays a loop: the navigator dedupes parallel edges (see
below) and it is `null` on an `Entity` with no `Graph` ancestor, which would turn
a documented `0` into a crash.

**Corollary — do NOT add `+ 2 * self_loop_count` to this body.**
`Graph._adjacency` appends both endpoints of a self-loop (`graph.gd:125-128`),
so the loop already visits `self` twice and inherits the +2. Adding it again
double-counts. This is the same reason `get_graph_degree` doesn't add it either
and `GraphMirror.get_degree` must — AStar holds no self-edge, the adjacency
index does.

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

**`TrailBlazerStep` was still on graph degree until 2026-08-07** — the same bug,
missed by the same reasoning, and it survived a full sweep of this file. Its
junction test (`degree > 2`) now reads entity degree: the spell punishes the
DEFENDER's constellation shape, so an unrelated enemy node adjacent to the
string must not read as a junction and stop the walk.

Two layers of tests said it was fine and both were wrong in the same direction,
which is the part worth remembering:

- the **step-level** fixtures built graphs and never assigned an owner. An
  unowned node returns 0 from `get_entity_degree` (the null guard), and 0 never
  trips `> 2` — so they asserted graph-degree behaviour against a step that no
  longer implemented it;
- the **end-to-end** fixtures did assign an owner — to the whole string — and on
  a fully-owned string entity degree and graph degree are equal by construction.

**Lesson for any future degree test: a fixture that leaves nodes unowned cannot
tell the two accessors apart, and neither can one where a single entity owns
everything.** Distinguishing them takes a mixed-ownership fixture — a defender's
string with a foreign node adjacent to it.
