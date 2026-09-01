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

## A base scene earns its keep by packaging children — otherwise delete it

A one-node "template" `.tscn` (bare root + script, no children) is dead weight.
It carries nothing an instantiator couldn't get from the script alone, so
nothing inherits it, and any default authored into it silently fails to reach
the concrete scenes that *don't* inherit it.

The test is the same as the section below: **does every instance need specific
sub-nodes?** If yes, make the base scene and have the concrete variants be
**inherited scenes** of it — then structural changes propagate for free. If no,
there is no base scene to make; put the shared default in the script.

`skill_node/addons/skill_node_addon.tscn` was exactly this and was deleted
(#334 follow-up): a bare `Node2D` + `SkillNodeAddon` script that nothing
inherited, while bunker/fortification/clamp/spike_ring/skill_dust were each
standalone scenes attaching the same script. A `z_index` authored into the
"template" reached none of them. It belonged in `SkillNodeAddon._ready`.

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

## A scene-wired NodePath export resolves BEFORE the target's `_ready`

So a setter that *subscribes* to something the target replaces during its own
`_ready` ends up holding the discarded object. The live case: `Entity._ready`
does `stat_board = stat_board.duplicate(true)`, and `dev_sandbox.tscn` wires
`PlayerInputController.player` as a NodePath — so `_set_player`'s
`action_points.current_changed` connection landed on a board the entity threw
away one frame later. Nothing errors; the signal simply never arrives.

**How to apply:** an export setter may cache the *node*, but must re-assert any
subscription to that node's *resources* from a later, idempotent bind call
(`GameRoot.bind_player` is the one here). Which means **a same-value early
return in such a setter is load-bearing in the wrong direction** — scope it to
the state that genuinely must not be clobbered, never to the re-subscription.
That regression is what 2fa1d9e fixed; `test/unit/scenes/test_act_gate_across_turns.gd`
pins it, and a procgen sandbox cannot reproduce it because it spawns its player
in `_setup_level`, after the swap.

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

## An instance placed deep inside another instance needs `[editable path=…]`

A `.tscn` may add nodes into an instanced sub-scene. Added at the instance's
**root** they always survive. An **instance** placed *below* that root — under a
node the sub-scene itself owns — survives only if the outer scene also declares

```
[editable path="PanelLayer/FrontmatterColumns"]
```

Without it the scene loads and runs correctly from source and the node is
**silently dropped when the editor converts the scene for an export**. Every
cheap signal stays green: the suite passes, `godot --path .` is right, F5 is
right, and only the shipped build is missing a subtree — with no error printed
in it either.

That is #711. `frontmatter_root.tscn` instanced `FrontmatterPanels` at
`PanelLayer/FrontmatterColumns/Remainder`, one level below the
`FrontmatterColumns` instance root, so **every export shipped a menu with no
panels at all**: navigating to Single Player raised nothing, and the same click
raised the lobby from source.

Established by A/B export, not by reading engine source:

- with the `[editable]` line, the converted `.godot/exported/…-frontmatter_root.scn`
  contains `FrontmatterPanels`; without it, zero occurrences;
- the same file perturbed by whitespace alone (new content hash, so a fresh
  conversion, ruling out a stale export cache) still drops the node;
- a plain `PackedScene` → `ResourceSaver.save()` → reload round-trip **keeps**
  it, so this is the editor's export conversion, not binary serialisation;
- plain `type=`-declared children in the same position survive
  (`frontmatter_panel.tscn`'s own `Column`/`Title`/`Body` render in the export),
  which is why the rule is scoped to *instances*.

`mise run lint-scene-instance-depth` (wired into `mise run check`) fails on the
shape. Editor-only trees — `addons/*`, `*_live_sandbox.tscn`, sandbox panels —
are exempt, because the export strips them anyway.

**How to apply.** Either add the `[editable path=…]` line for the instance you
are reaching into, or — better — give the sub-scene a real slot and instance
into it from a scene that owns the slot. The second is the shape the rest of
this doc argues for; the first is the one-line fix when the slot already exists
and the reach is honest.

## An instance that re-anchors must author its own `anchors_preset` (2026-09-01)

Sibling of the rule above, same signature — correct from source, wrong only in
an exported build — but a different mechanism, so `lint-scene-instance-depth`
was clean while the bug shipped.

Exporting re-saves every scene as binary, and that re-save writes the editor
helper `anchors_preset` onto each node **whether or not the text scene had
one**. Its setter assigns all four anchors. What survives that is only the
subset of `anchor_*` values the instance actually stores — and an instance
stores only what DIFFERS from its base scene's root, so an override that
happens to *match* the base is dropped as redundant and nothing restores it.

`title_band.tscn` re-anchored two `banner.tscn` instances to (0, 0.5, 1, 0.5)
and authored no preset. The export synthesized `0` (`PRESET_TOP_LEFT`), which
zeroed all four; `anchor_top`/`anchor_bottom` came back because 0.5 differs
from `banner.tscn`'s own root, while `anchor_right = 1.0` — identical to that
root — had already been dropped. The band loaded with correct height and
**zero width**: "YOUR TURN" slid around x=0, roughly 80% off the left edge,
and its backdrop (anchored 0..1 *inside* the band) had no width to draw, so it
read as missing entirely.

Established by reading the exported `PackedScene`'s own `SceneState` at runtime
from the shipped build:

- the exported scene lists `anchors_preset = 0` on a node whose `.tscn` never
  contained the property, and lists **no** `anchor_left` / `anchor_right`;
- a `ResourceSaver.save()` → reload round-trip in-editor **keeps** all four
  anchors, so this is the export conversion, not binary serialisation — the
  same split as #711;
- the parent (`TitleBand`, a plain `type=` node) was a healthy 1440x960
  throughout, because its anchors are stored against the CLASS default and so
  nothing is dropped as redundant;
- `callout_band.tscn` — same layer, same shape, plain children — is unaffected
  for that reason. **Only instances are exposed.**

The synthesized value is **not computed from the node's anchors**: `TitleBand`
is anchored (0, 0, 1, 1) — `FULL_RECT`, 15 — and the export writes `0` for it
too. It survives regardless, being a plain node whose stored `anchor_right`
re-applies afterwards. So do not reason about which preset an unauthored node
will be given; author one.

The fix is verified the same way, by reading the converted scene the export
leaves at `.godot/exported/<n>/export-<hash>-title_band.scn`: with
`anchors_preset = 14` authored, the converted binary carries `14`, and
instantiating it straight from that file yields anchors (0, 0.5, 1, 0.5) and
offsets (0, -132, 0, 8) — correct before any code runs.

`mise run lint-instanced-anchors` (wired into `mise run check`) fails on an
instanced node that sets any `anchor_*` without an `anchors_preset` line.

**How to apply.** Author the preset that matches the intent — `anchors_preset =
14` is `HCENTER_WIDE`, i.e. exactly left 0 / right 1 / top 0.5 / bottom 0.5.
A preset the author chose is written back unchanged and applied harmlessly. A
widget with a geometric contract of its own can also re-assert it in `_ready()`
(`Banner._assert_full_width()`), which is belt-and-braces rather than the fix:
prefer the authored preset, since the code guard only covers the sides that
one widget happens to know about.
