# Scene composition (DX-first)

When to reach for a `.tscn` scene vs. composing in code, and how to expose
tuning. The throughline: **lean on the editor**. If the engine can compose,
wire, and preview something for you, don't reimplement that in `_ready`.

## Decision table

| Situation | Do this |
|---|---|
| Composing a node tree in code (`X.new()` + `add_child` chains) | Make a **scene** and `instantiate()` it instead. |
| A node depends on specific sub-nodes existing | **Scene-compose them.** The instance must come pre-packaged with the nodes it depends on — never assume a caller adds them. |
| Cross-system dependency (NodePath to another node) | **DI via `@export`**, wired in the composing scene (GameRoot). Set NodePaths at compose time, not `get_node` in code. |
| Lots of toggles / tweakables (would-be `var`s or `const`s) | Promote to `@export` so they're designable in the inspector (reactive in-editor for visuals). |
| Has an animation / one-shot effect to trigger | Scene + `@export_tool_button` (or `@export` knobs) so it's previewable in-editor. |
| Variation is identity/runtime-bound (the human player, spawned at runtime) | Can't be a scene NodePath — inject the plain `var` from the composer after it resolves. |

## Why "pre-packaged with its deps" matters

A scene's `@onready var nodes := $Nodes` (or pre-wired child NodePaths) only
holds if every instance actually carries those children. That's the contract of
instancing the scene — and the reason `graph.tscn` bundles Navigator + Nodes +
Edges + Entities and pre-wires `navigator`. Code that does `Graph.new()` and
hand-builds containers breaks that contract (and crashed 41 tests when graph.gd
moved its containers to `@onready $Child`). The fix is to **instantiate the
scene**, not to defensively null-guard the `@onready`s.

Corollary for **tests**: build fixtures by `preload("res://…/foo.tscn").instantiate()`,
not `Foo.new()` + manual child wiring. Same contract, same payoff.

## Where a dependency points decides where a node lives

- `graph.tscn` houses what the graph **owns / is depended-on-by** topologically:
  Navigator + the Nodes/Edges/Entities containers.
- **FogOverlay stays in GameRoot**, NOT graph.tscn — it depends *outward* on
  `Systems/VisionSystem` (a GameRoot-composed node). Housing it in graph.tscn
  would leave its `vision_system` NodePath dangling at graph-compose time,
  violating "pre-packaged with deps". A node belongs in the scene that can
  satisfy its dependencies.
- Camera is a free choice (no hard dep on graph internals); kept in GameRoot as
  a presentation/level concern since GameRoot owns camera resolution + framing.

## Sandboxes

A sandbox that wants to poke at an instance's internals can mark it
**editable children** in the editor — but the base instance still ships
complete. Don't fork a divergent hand-composed copy (the dev_sandbox lesson:
it was a standalone tree that drifted from game_root.tscn; now it's an
**inherited scene**, so structural changes to game_root propagate for free).

See also [godot-workflow.md](godot-workflow.md) for the scene-node `_ready`
vs `initialize()` injection-timing gotcha.
