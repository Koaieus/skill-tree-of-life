---
description: Graph accessors rebuild their result (never call in a loop); reach queries use gather(), not in_range()
paths:
  - "graph/**"
  - "attack/**"
  - "effects/**"
  - "systems/**"
  - "procgen/**"
---

# Graph (`graph/graph.gd`)

## Graph accessors rebuild their result — never call them inside a loop

`get_skill_nodes()`, `get_edges()`, and `get_neighbours()` look like O(1) field
reads. They are not. Each one walks `get_children()` on a container, type-checks
every child, and builds a fresh typed Array.

**Why:** the containers are the source of truth; there is no stored list. So an
accessor call is O(N) or O(E), and calling one *per node* silently makes the
caller quadratic.

This shipped as a real bug. `Graph.get_neighbours()` called `get_edges()`, and
`VisionSystem`'s sensed traversal called `get_neighbours()` once per popped
node — so every hop rebuilt all 230 Edge objects into a new array. Allocating a
node cost 13.9ms at 41 owned nodes on a 150-node graph and grew from there. The
symptom read as "the fog/aura shader is slow"; the overlays were flat at 0.4ms.
Fixed in c5f3e42 by adding a cached adjacency index.

**How to apply:**

- Hoist the call out of the loop: `var edges := graph.get_edges()` once, then
  iterate `edges`. Most existing quadratic risk is one hoist away.
- For per-node neighbour queries, use `get_neighbours()` — it now reads a cached
  adjacency index, so it *is* O(degree). Don't hand-roll an edge walk.
- Before adding a new accessor here, decide whether it rebuilds or caches, and
  say so in its docstring. `get_neighbours()` documents that it's on a hot path.
- **The same quadratic has a second shape: a predicate asked per point.** Not an
  accessor in a loop — a *test* run once per candidate against a set that never
  changes during the sweep. `VisionSystem.is_within_circles(p, positions, radii)`
  was a linear scan over every owned node's circle, called once per graph node:
  2025 × 200 = 400k iterations, 13.3ms of a 19.4ms recompute, on every
  allocation (and the identical shape in `AiRecon` per AI turn). Fixed
  2026-08-17 by giving the set a home that can carry an index
  (`VisionCircles`, a uniform grid) instead of passing two packed arrays around.
  **The tell:** a `static` predicate taking a *collection* plus one point. If
  callers ask about many points, the collection wants to be an object.
- When profiling something that "must be the GPU", **measure the CPU first.**
  `Time.get_ticks_usec()` around the suspect functions, run the sandbox headless,
  watch which number grows with graph size. The overlay shaders were the obvious
  suspect and the innocent party.

## The adjacency cache is invalidated by child add/remove, not by `Edge.from`/`to`

`_adjacency` is rebuilt lazily whenever either container gains or loses a child
(`child_entered_tree` / `child_exiting_tree`), which covers `add_edge`,
`remove_edge`, `remove_skill_node`, procgen, and any direct `add_child`.

It does **not** notice an `Edge.from` / `Edge.to` reassignment on an edge that's
already in the tree, because that mutates topology without touching the child
list. Every current caller sets the endpoints *before* `add_child` (see
`Graph.add_edge` and `playground_panel._add_edge`), so this is safe today.

**How to apply:** if you ever re-point a live edge's endpoints, call
`_mark_adjacency_dirty()`. The editor path (`Engine.is_editor_hint()`) skips the
cache entirely for exactly this reason — an inspector edit to `from`/`to` would
otherwise go unnoticed.

## Reach queries: `gather()`, never `in_range()` in a loop

`RangeFinder.in_range(attacker, source, candidate)` is a per-candidate predicate,
and `HopRangeFinder`'s implementation runs an **AStar query per candidate**. Asking
it "which of my N nodes are in reach?" is N × AStar — the same quadratic shape this
file already documents twice.

`RangeFinder.gather(source, mirror) -> Dictionary[SkillNode, float]` is the
set-shaped sibling: one BFS (hops) or one linear scan (euclidean), and it returns
the **distance**, which a bool predicate can't (auras need it for `DistanceScale`).

**`gather` and `in_range` are not interchangeable, by design.** `in_range` on
`HopRangeFinder` hardwires the *global* `graph.navigator` (reach through anyone's
territory); `gather` traverses whatever mirror it's handed. That divergence is the
point — an aura's hop distance must be measured over the *owned* subgraph
(`entity.navigator`), or a path shortcuts through enemy land. Never "simplify"
`gather` to read `graph.navigator` for consistency.

## Populate a Graph through `add_skill_node` / `add_edge`, not the containers

`Graph.add_skill_node(sn)` and `Graph.add_edge(a, b)` emit `node_added` /
`edge_added`. Adding a child straight to `skill_nodes_container` /
`edges_container` does **not** — so the Graph's `Navigator` never mirrors it and
every global-mirror query silently returns empty (`vertex_id` → -1,
`nodes_within` → `{}`). No error.

`test/unit/test_move_core.gd` builds its fixture by adding to the containers
directly; it gets away with it only because it reads `entity.navigator` (populated
explicitly by `AllocationSystem.force_allocate` → `mirror_add`) and never touches
`graph.navigator`. Don't copy that shortcut into a fixture that does.

## `stable_id` mints LAZILY; `entity_id` mints eagerly — never read the field

`Entity.entity_id` is minted on entry to `entities_container`, so it is always
real. `SkillNode.stable_id` is minted inside `_ensure_topology()`, which only
runs on demand — so a node added straight to `skill_nodes_container`, or
authored in a scene, reads **0** until something asks a topology question.

**Why it matters:** a `Command` carrying node id 0 resolves to `null` at apply
time and the verb silently does nothing. No error, no warning.

**How to apply:** build commands with `graph.get_stable_id(node)` (it forces the
rebuild first), never `node.stable_id`. Same for fixtures — a test that adds
nodes via the container and then reads `.stable_id` gets zeros for all of them.

## Accessors return a private copy; callers may mutate it

`playground_panel.gd` does `var candidates := graph.get_skill_nodes()` then
`candidates.append(caster_node)`. That contract is load-bearing: any caching
here must hand out a `duplicate()`, never the cached array itself.
