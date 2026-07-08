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

## Accessors return a private copy; callers may mutate it

`playground_panel.gd` does `var candidates := graph.get_skill_nodes()` then
`candidates.append(caster_node)`. That contract is load-bearing: any caching
here must hand out a `duplicate()`, never the cached array itself.
