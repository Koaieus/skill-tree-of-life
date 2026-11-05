# Whip report 2026-11-05

**Landed 20/20 · 119 commits `a177d88..master` · back to Needs design 0 · orphaned In progress 0 · dropped 0 · still Ready 0**

## Landed
- #427 self_loops is derived state that the editor serializes — two disagreeing degree answers
- #580 Extract the HDR endpoint lift shared by Edge and MenuEdgeView into one helper
- #1014 gh-project hygiene: in_progress_stale — an In progress claim with no activity for a few hours is stale, hubs handled separately
- #1216 Gate confirm: Esc / right-click should disarm it (ArmedMode)
- #1124 tooltip fan: FanAnchor._route rebuilds router params by hand and drops shoulder
- #335 SkillNode.modifiers conflates authored `@export` with derived runtime modifiers
- #440 Per-repaint quadratic walks in the melee and ranged attack plans
- #442 AllocationVFX: five code-composed effect trees → scenes
- #471 perf: VisionCircles cell size == max radius, so a query scans every circle in the tile
- #721 LobbyScreen is the last code-composed screen: retire configure()'s before-_ready contract and author lobby_screen.tscn
- #855 blade_obstacle_field.gd still carries a GDScript FieldCtx per-substep pass — a mirror #847 missed, only a test helper calls it
- #986 test_wire_outlives_the_level.gd:321 flakes under integration-tier sharding
- #1145 NodeFeedback: hit-flash / blink / shake tweens out of skill_node.gd
- #1214 refactor(graph): GraphMirror.flip_pairs seam — GateFlipInstance stops poking astar
- #1242 Volatility colour: owner_panel scalar rows + recolour on a flip that leaves the value unchanged
- #1579 Status tag channel has no shipped consumer: remove it
- #1767 SkillNode lab: an editor tool button that opens skill_node_lab.tscn
- #428 Melee blade construction is written three times
- #859 A skipped starter slot mis-zips every later participant onto the wrong spawn
- #1026 SpellCatalog: const preload list + ALL array → authored .tres catalog wired as an `@export` (the #1008 shape)

## Back to Needs design
- none

## Still Ready
- none

## Orphaned In progress
- none

## Dropped by the owner
- none

## Filed since start (2026-11-05T18:22:50Z)
#1770 mp:e2e: client's join resync sometimes goes unanswered (2/5 runs time out)
#1769 VFX idea: panels as superheavy objects that lens the space beneath them
#1768 SkillNode lab: verification readouts (where they live)
#1767 SkillNode lab: an editor tool button that opens skill_node_lab.tscn
#1766 Whip run 2026-11-05

## Needs the owner
- none

## Incidents
- none

## Cost (agent-cost, latest 20)
```
agent     model        turns calls  final   peak    Σctx     eff  priced   out  wall  top tools / hints
a5ff117b  opus-5-5        66    70   116k   116k   5.64M    989k   2.88M   26k   54m  Bash 60, Agent 5, SendMessage 3, advisor 1  #1767
a384e9b9  opus-5-5        23    25    62k   104k   1.18M    251k   1.61M   14k    9m  Bash 21, advisor 2, SubagentHandback 2  wt:wt-flake-reveal
aee27c01  opus-5-5        56    60   143k   267k   5.99M    939k   4.34M   38k   20m  Bash 52, SendMessage 3, advisor 2, Write 2  #1026 wt:wt-spell-catalog-1026
ac0aa916  opus-5-5        29    31    74k   140k   1.72M    325k   1.95M   16k    7m  Bash 26, advisor 2, Write 1, SendMessage 1  #428 wt:wt-d428
a64fce9f  sonnet-5-5      12    14    41k    41k    420k    108k    108k    4k    3m  Bash 10, bash 1, Edit 1, SendMessage 1  #859 wt:wt-short-starters
a3b024e7  sonnet-5-5       6     7    33k    33k    179k     65k     65k    2k    2m  Bash 5, SendMessage 1, SubagentHandback 1  #1767
a8f5c2fa  opus-5-5        73    86   157k   157k   8.03M   1.39M   4.06M   39k   44m  Bash 66, Agent 14, SendMessage 2, SubagentHandback 2  #1145
a7b5476f  opus-5-5        29    31    80k   156k   1.86M    350k   2.30M   16k    8m  Bash 27, advisor 2, Read 1, SubagentHandback 1  #1145 wt:wt-gate-b
aff51c04  haiku-5-5       25    27    29k    29k    599k    125k     62k    6k    2m  Bash 27  #435
a8fe15bb  fable-5-1       29    29   110k   211k   2.47M    349k   3.41M   33k   14m  Bash 24, advisor 2, Write 1, SendMessage 1  #335 wt:wt-u335
a52365d1  sonnet-5-5       8    12    45k    87k    366k    104k   1.10M    6k    5m  Bash 7, advisor 3, SendMessage 1, SubagentHandback 1  #1124 wt:wt-fan-anchor-1124
a8677187  sonnet-5-5      15    16    47k    47k    550k    129k    129k    7k    2m  Bash 15, SubagentHandback 1  #721 wt:wt-wt-sweep-b
a925454a  opus-5-5        19    22    58k   111k    977k    193k   1.50M    9k    5m  Bash 19, advisor 2, SubagentHandback 1  #1242 wt:wt-d1242
a3aa233b  fable-5-1       26    25   100k   192k   1.90M    384k   3.39M   42k   21m  Bash 21, advisor 2, SendMessage 1, SubagentHandback 1  #471 wt:wt-vision-circles-471
a4651790  opus-5-5        15    17    46k    89k    640k    136k   1.11M    7k   11m  Bash 14, advisor 2, SubagentHandback 1  #986 wt:wt-wire-outlives-986
ac34cdf3  sonnet-5-5      11    17    38k    74k    415k     93k   1.28M    4k    4m  Bash 10, advisor 5, SendMessage 1, SubagentHandback 1  #1214 wt:wt-m1214
ac310a2b  opus-5-5        27    27    87k   166k   1.98M    399k   2.41M   23k    8m  Bash 24, advisor 2, SubagentHandback 1  #442 wt:wt-vfx-442
aa14dfbe  sonnet-5-5      15    18    42k    77k    566k    135k    711k    6k    6m  Bash 12, SendMessage 2, SubagentHandback 2, advisor 2  #440 wt:wt-melee-neighbor
ab31b97a  opus-5-5        35    37   104k   204k   2.84M    508k   2.88M   23k    9m  Bash 34, advisor 2, SubagentHandback 1  #1579 wt:wt-d1579
abbae1d5  opus-5-5        26    27    83k   158k   1.78M    330k   2.17M   13k    7m  Bash 23, advisor 2, SendMessage 1, SubagentHandback 1  #855 wt:wt-i855-blade-obstacle
TOTAL                    545   598                40.11M   7.30M  37.47M  333k
  Σctx = Σ over API calls of context at that call (the cost integral); eff = 1·input + 1.25·cache_creation + 0.1·cache_read + 5·output; priced = eff × model tier (haiku 0.5, sonnet 1, opus 2.5, fable 5, sonnet units) — a best estimate, priced per agent alone, cross-agent chatter not modelled.
```

No daemon, timer or session was ever started; nothing to tear down.
