# Whip report 2026-10-20

**Landed 12/13 · 41 commits `fd19391..master` · back to Needs design 1 · orphaned In progress 0 · dropped 0 · still Ready 0**

## Landed
- #1388 Wither × Addon: map + blade addon to the recipe
- #1391 Blindness × Addon: Dune — on-hit blindness rider that puffs onto 1-hop neighbours
- #1392 Blindness × Spell 2: Throw Sand
- #1393 Scout × Addon: re-enable the watchtower's temp face (flag flip)
- #1396 Armor break × Addon: map + blade addon to the recipe
- #1423 Greed × Addon: map +1 aspect, blade rider
- #1428 Weakness × Addon: map +1 aspect, blade rider
- #1699 StackTerm: a status rider's extra stacks from a defender stat (DefenderStatShare)
- #1701 Perf: Euclidean gathers walk the whole board — spatial index or physics broadphase
- #1702 Aimed targeting: delete the per-caster all-node branch — aimed spells take the main candidate-first path
- #1703 Aimed launch: host verifies source eligibility and submitted seeds match its hitscan
- #1705 Aimed input: snap the shape to the nearest caster, click locks, right-click unlocks

## Back to Needs design
- #1704 Aimed shapes: physics hitscan for seeds, one preview hitscan per aim change, tick-wait on stale

## Still Ready
- none

## Orphaned In progress
- none

## Dropped by the owner
- none

## Filed since start (2026-10-19T23:57:06Z)
#1709 Whip run 2026-10-20

## Needs the owner
- 2026-10-20 02:46 needs owner #1704 (train a, lead-a): seed hitscan spec assumed a physics backing; ADR 0068 chose the Graph grid — needs a respec

## Incidents
- none

## Cost (agent-cost, latest 20)
```
agent     model        turns calls  final   peak    Σctx     eff  priced   out  wall  top tools / hints
abc9af2a  opus-5-5        91   101   172k   172k   9.76M   1.24M   3.34M    1k   49m  Bash 84, Agent 13, SendMessage 2, advisor 1  #1388
a15ca73d  sonnet-5-5      15    17    46k    46k    589k    113k    113k    0k    3m  Bash 15, SendMessage 1, SubagentHandback 1  #1396 wt:wt-wt-sweep-a
a7981f0c  opus-5-5        24    28    86k    86k   1.54M    236k   1.25M    0k   11m  Bash 23, advisor 2, Write 2, SubagentHandback 1  #1428 wt:wt-sapling-1428
a3c6f7e6  opus-5-5        28    29    82k    82k   1.79M    260k   1.34M    0k    7m  Bash 26, advisor 2, SubagentHandback 1  #1423 wt:wt-midas-1423
ac4fd092  opus-5-5        19    22    65k    65k    947k    154k    917k    0k    7m  Bash 19, advisor 2, SubagentHandback 1  #1705 wt:issue-1705-aimed-input-snap-the-shape-to-the-neares
a05ac57e  opus-5-5        40    45   113k   113k   3.23M    440k   1.94M    0k    8m  Bash 38, advisor 2, SendMessage 2, Write 2  #1396 wt:wt-shredder-1396
a4f865df  opus-5-5        20    22    63k    63k    999k    157k    929k    0k    7m  Bash 18, advisor 2, SendMessage 1, SubagentHandback 1  #1703 wt:wt-1703-magic-aim
ac378e74  opus-5-5        23    26    81k    81k   1.43M    221k   1.20M    0k    6m  Bash 20, advisor 2, Write 2, SendMessage 1  #1391 wt:wt-1391-dune
a7c67001  sonnet-5-5       9    11    40k    40k    317k     79k     79k    0k    2m  Bash 9, SendMessage 1, SubagentHandback 1  #1393 wt:wt-w1393
a3ed6f6b  opus-5-5        38    41   108k   108k   2.93M    410k   2.32M    0k   12m  Bash 35, advisor 3, Write 2, SubagentHandback 1  #1701 wt:wt-euclid-grid
a7190542  opus-5-5        19    22    64k    64k    930k    156k    901k    0k    8m  Bash 19, advisor 2, SubagentHandback 1  #1702 wt:wt-1702-targeting
a7c18db0  opus-5-5        24    25    80k    80k   1.52M    234k   1.20M    0k    8m  Bash 20, advisor 2, SubagentHandback 2, SendMessage 1  #1392 wt:wt-pocket-sand-1392
a47fde2e  opus-5-5        19    23    72k    72k   1.04M    176k   1.02M    0k    7m  Bash 19, advisor 2, SendMessage 1, SubagentHandback 1  #1699 wt:issue-1699-stackterm-a-status-rider-s-extra-stacks-
a3482735  opus-5-5        26    28    86k    86k   1.73M    264k   1.38M    0k    7m  Bash 25, advisor 2, SubagentHandback 1  #1388 wt:wt-ashfall-1388
abdb43e6  haiku-5-5        8    11    29k    29k    196k     53k     26k    0k    1m  Bash 10, SubagentHandback 1  #1393
a7cca78c  haiku-5-5       10    21    93k    93k    640k    172k     86k    0k    2m  Bash 20, SubagentHandback 1  #1393
abe76224  opus-5-5        41    41   107k   186k   3.71M    549k   2.30M   11k    5m  Bash 39, Edit 1, advisor 1  wt:wt-lint1-rename
a30ecde0  fable-5-1       12    18   204k   204k   1.17M    197k   2.46M    8k    5m  Bash 14, Read 2, advisor 2  #1701
a977f55d  haiku-5-5       12    16    27k    27k    282k     69k     34k    2k    1m  Bash 16  #1701
a2637ea5  sonnet-5-5       6     6    72k    72k    383k    121k    121k    0k    3m  Bash 4, Read 2  #1701
TOTAL                    484   553                35.13M   5.30M  22.96M   26k
  Σctx = Σ over API calls of context at that call (the cost integral); eff = 1·input + 1.25·cache_creation + 0.1·cache_read + 5·output; priced = eff × model tier (haiku 0.5, sonnet 1, opus 2.5, fable 5, sonnet units) — a best estimate, priced per agent alone, cross-agent chatter not modelled.
```

No daemon, timer or session was ever started; nothing to tear down.
