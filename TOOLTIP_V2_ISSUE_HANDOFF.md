# Handoff: finish the Tooltip V2 issue bulk-write (#159)

**Temp file — delete once consumed.** A fresh agent should run this start-to-finish to
create the remaining sub-issues of epic **#159** and finish board-wiring the ones already made.

## ⚠️ Blocked on GitHub GraphQL rate limit
As of 2026-07-17 ~15:41 UTC the GraphQL budget was fully exhausted (5000/5000 points), resetting
**~16:21 UTC**. The `gh` CLI uses GraphQL for `issue list/create` (label+milestone name
resolution), `issue edit --parent`, and *especially* the `mise gh-project` board helper (it runs a
`project item-list --limit 999` query on **every** call). **Before running anything below**, confirm
the budget has reset:
```
gh api rate_limit -q '.resources.graphql'   # want remaining > ~1000
```
Root cause of the exhaustion: the board helper's per-call 999-item query × many calls × retry loops.
**Mitigation:** set board fields sparingly and do NOT retry a failing board call in a loop — if
`mise gh-project` errors, stop and report.

## Shell caveat
The Bash tool runs **zsh**, and a `#!/usr/bin/env bash` shebang inside a command string is NOT
honored. `read -ra` fails ("bad option: -a"). Either invoke `bash -c '...'` explicitly, or pass
`--label` flags literally per `gh issue create` call (recommended — see below).

## Per-issue procedure (this worked for #216–220)
```
gh issue create --title "<title>" --body-file <tmpfile> --label ui --label visuals [--label vfx|tech-debt] --milestone "VFX & juice"
gh issue edit <n> --parent 159
mise gh-project -- add <n>
mise gh-project -- status <n> <ready|backlog>
mise gh-project -- size <n> <xs|s|m|l|xl>
mise gh-project -- priority <n> <p1|p2>
```
Guard against duplicates: `gh issue list --state open --limit 60 --json title -q '.[].title'` and skip
any title already present.

## State

DONE — fully wired (parent #159, labels, milestone, board Ready):
- #216 TooltipFanConfig resource
- #217 trace routing helper
- #218 HoloPanel hologram shader
- #219 radar/attribute chart widget
- #220 HP readout widget

DONE creating but **MISSING board fields** — set status/size/priority (parent+labels+milestone already OK):
- #221 modifier glass-slab row → status `ready`, size `m`, priority `p1`
- #222 FanTrace scene → status `backlog`, size `m`, priority `p1`
- #223 FanPanel base scene → status `backlog`, size `m`, priority `p1`
- #224 FanUnit scene + state machine → status `backlog`, size `m`, priority `p1`

TODO — create these 11 (items 10–20). Body template for each:
```
Part of the circuit-fan node tooltip V2 (epic #159 — see the plan comment there).

**Scope:** <scope below>

**Depends on:** <deps below>

**Done when:** <infer 1–2 acceptance bullets from scope>
```

| # in plan | Title | Labels | Size | Board status | Priority | Scope | Depends on |
|---|---|---|---|---|---|---|---|
| 10 | `Tooltip V2: TooltipFan coordinator + node anchoring` | ui,visuals | l | backlog | p1 | Coordinator owning N FanUnits; anchors its origin to the hovered node's canvas position each frame via `get_global_transform_with_canvas()` (screen-space, zoom-independent — NOT a world Node2D); computes fan-out geometry (radial vs up/down); per-index stagger; triggers off `Events.skill_node_hovered`/`unhovered`. Sample content at this stage. | #216, #224 |
| 11 | `Tooltip V2: Granted Modifiers panel (live data)` | ui,visuals | m | backlog | p2 | Bind real `node.modifiers` (flatten CompositeStatModifier leaves), addon sections, keystone/procgen debug — lift formatting from current `skill_node_tooltip.gd`. | #221 |
| 12 | `Tooltip V2: Owner panel + radar (live data)` | ui,visuals | m | backlog | p2 | Hostile-owner header (name/level/class) + live attribute values feeding the radar widget. | #219 |
| 13 | `Tooltip V2: Addons panel (live data)` | ui,visuals | s | backlog | p2 | Render `node.get_addon_tooltip_sections()`. | #223 |
| 14 | `Tooltip V2: Node-Local loot panel (live data)` | ui,visuals | s | backlog | p2 | Render node local modifiers / loot payload. | #223 |
| 15 | `Tooltip V2: Core manifest panel (live data)` | ui,visuals | s | backlog | p2 | Core class identity modifiers, gold-fixed skin. | #223 |
| 16 | `Tooltip V2: ID chip + HP integration` | ui,visuals | s | backlog | p2 | Node id/degree chip; wire HP readout at chosen placement, keep current damaged/core-health live-update bindings. | #220 |
| 17 | `Tooltip V2: in-editor sandbox host (@tool)` | ui,visuals | m | backlog | p2 | `@tool` sandbox host + inherited dev scene with sample content, so hover choreography + per-panel trace paths are previewable/tunable live in-editor while the shipped scene stays content-clean. | #10 (coordinator) |
| 18 | `Tooltip V2: idle-loop animations` | ui,visuals,vfx | s | backlog | p2 | Trace spark/pulse + panel static/blink/float idle states; enforce constant-brightness rule (never hand the trace to a dimmer rest style mid-loop). | #224 |
| 19 | `Tooltip V2: cutover — replace skill_node_tooltip` | ui,visuals,tech-debt | s | backlog | p2 | Swap `skill_node_tooltip` → `TooltipFan` in `ui/hud/hud_root.tscn`, delete old tooltip scene/script, migrate live-update signal bindings. | #10 + all Phase-2 panels |
| 20 | `Tooltip V2: trace glow shader polish` | ui,visuals,vfx | s | backlog | p2 | Final bloom/tip tuning of trace glow against a reference screenshot. | #222 |

(The "Depends on" numbers referencing plan-items 10 map to whatever issue number the coordinator
gets — resolve after creating #10's issue.)

## When done
Print a number→title→status table for all of #216 through the last created issue, and delete this file.
