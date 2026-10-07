# Whip report 2026-10-03

**Landed 4/20 · 25 commits `094f666..master` · back to Needs design 0 · dropped 16 · still Ready 0** · fleet tasks peak 141

## Landed
- #1334 Save/load: SaveFile codec, single slot, quiescence gate, open_saved
- #1335 Save/load: pause-menu SAVE/LOAD + frontmatter LOAD
- #1355 Stat: equal-priority SET conflict push_errors; a load restores modifier obtain order
- #1362 Procgen fuse: MULTIPLY rolls fuse by floored delta sum, not product

## Back to Needs design

## Still Ready

## Dropped by the owner
- #1343 Status rows keyed by a group_by Expression; visible_if gates the count
- #1344 OnDealloc.LINGER: rows survive dealloc and tick on any turn end while unowned
- #1347 Status readouts respect visible_if: presence-only rows for foreign camps
- #1345 Scout status: camp-keyed, LINGER, -1/tick, radius = ½·√n·V; node remembers last-owned sight
- #1346 Scout arrow lands scout stacks; VisionSystem draws discs from rows; reveal path retires
- #1349 Aspect arrows: five AmmoType .tres + roster test (corruption, curse, wither, armor_break, blindness)
- #1350 AttackRecord: a hit's ammo type id round-trips (HitInstance.ammo_type_id)
- #1351 Status arrow base scene: status-tint tip + GPUParticles2D trail + impact burst; per-shot scene pick
- #1352 Per-type inherited arrow scenes for the six statused arrows
- #1359 On-hit: OnHitEffect takes a mode-agnostic HitLanding; StatusInstance.paired gate; ADR
- #1360 On-hit: AmmoType.on_hit_effects replaces status_def; RangedStatusInstance dies; ammo card lists all
- #1361 On-hit: DotAddon.on_hit_effects + per-vertex rider list (fixes second-addon overwrite); BladeStatusInstance dies
- #1321 Unverified claims left in design docs after the sweep
- #1322 Stale doc citations outside the sweep's fences
- #1348 Bug: AI camp-mates don't reveal for their camp's humans (vision_group human filter)
- #1353 Ammo card: status-colour swatch + status icon

## Filed since start
#1365 Whip v2 tool: start from anywhere, baton verbs, watchdog relief + disk-silence stall, report buckets
#1364 Save/load: pause-menu RESTART after a LOAD hangs (world_source stays ARRIVES)
#1363 Whip run 2026-10-03
#1362 Procgen fuse: MULTIPLY rolls fuse by floored delta sum, not product
#1361 On-hit: DotAddon.on_hit_effects + per-vertex rider list (fixes second-addon overwrite); BladeStatusInstance dies
#1360 On-hit: AmmoType.on_hit_effects replaces status_def; RangedStatusInstance dies; ammo card lists all
#1359 On-hit: OnHitEffect takes a mode-agnostic HitLanding; StatusInstance.paired gate; ADR
#1355 Stat: equal-priority SET conflict push_errors; a load restores modifier obtain order
#1353 Ammo card: status-colour swatch + status icon
#1352 Per-type inherited arrow scenes for the six statused arrows
#1351 Status arrow base scene: status-tint tip + GPUParticles2D trail + impact burst; per-shot scene pick
#1350 AttackRecord: a hit's ammo type id round-trips (HitInstance.ammo_type_id)
#1349 Aspect arrows: five AmmoType .tres + roster test (corruption, curse, wither, armor_break, blindness)
#1348 Bug: AI camp-mates don't reveal for their camp's humans (vision_group human filter)
#1347 Status readouts respect visible_if: presence-only rows for foreign camps
#1346 Scout arrow lands scout stacks; VisionSystem draws discs from rows; reveal path retires
#1345 Scout status: camp-keyed, LINGER, -1/tick, radius = ½·√n·V; node remembers last-owned sight
#1344 OnDealloc.LINGER: rows survive dealloc and tick on any turn end while unowned
#1343 Status rows keyed by a group_by Expression; visible_if gates the count

## Needs the owner
- none

## Incidents
- 2026-10-03 11:14 launched relief relief-a-1 (98401118) 
- 2026-10-03 11:26 note: owner 11:26: STOP — no further trains; let relief-a-1 land train a, then wrap up
- 2026-10-03 11:36 watchdog: whip blocked → stop + resume 11b2dd7b: backgrounded · 0f6835c4
  claude agents             list sessions
  claude attac
- 2026-10-03 11:41 note: owner 11:41: watchdog forked whip; 0f6835c4 claimed, de7ba246 stopped
- 2026-10-03 11:43 relief-a-1 DONE ffe7072 4/4

## Cost (agent-cost, latest 20)
```
agent     model        turns calls  final   peak    Σctx     eff  priced   out  wall  top tools / hints
ad1355fx  sonnet-5-5       8     8    38k    38k    279k     86k     86k    3k    2m  Bash 8  #1355 wt:wt-fixture-set-replace
ad1335-3  opus-5-5        44    43   113k   206k   3.69M    639k   3.29M   32k   14m  Bash 40, advisor 2, SendMessage 1  #1335 wt:wt-pause-save-load
ad1334c2  opus-5-5        14    14    46k    89k    596k    132k    774k    4k    3m  Bash 13, advisor 1  #1334 wt:wt-d1334c
aSage-2a  fable-5-1       25    19    88k    88k   1.68M    228k   1.14M   16k    7m  Bash 11, SendMessage 7, Agent 1  #1355
ad1355b-  opus-5-5        34    33    79k    79k   2.11M    382k    956k   20k    7m  Bash 29, SendMessage 4  #1355 wt:wt-d1355b
a6af548d  haiku-4-5-20    24    23    81k    81k   1.44M    275k    138k    8k    1m  Bash 14, Read 9  #775
ad1362-3  opus-5-5        17    15    58k    58k    838k    184k    460k   11k    4m  Bash 14, SendMessage 1  #1362
ad1355a-  opus-5-5        13    11    60k    60k    634k    174k    435k    8k    3m  Bash 10, SendMessage 1  #1355
a4dc2f34  haiku-4-5-20     8    12    21k    21k    147k     39k     19k    0k    1m  Bash 8, Read 3, SubagentHandback 1
ac448a98  haiku-4-5-20    19    20    24k    24k    397k     64k     32k    0k    1m  Bash 16, Read 3, SubagentHandback 1
a8f1c389  haiku-4-5-20    43    43    40k    40k   1.26M    177k     88k    1k    4m  Bash 38, Read 4, SubagentHandback 1
a08e34c7  haiku-4-5-20     8    11    19k    19k    137k     35k     18k    0k    1m  Bash 9, Read 1, SubagentHandback 1
ad5da691  sonnet-5-5       5     6    61k    61k    286k     62k     62k    0k    1m  Bash 4, Read 1, SubagentHandback 1  #794
aba961f0  sonnet-5-5       6     6    62k    62k    344k     69k     69k    0k    1m  Bash 4, Read 1, SubagentHandback 1  #1318
af317a17  haiku-4-5-20    91    91    96k    96k   5.63M    677k    339k    1k    4m  Bash 68, Read 22, SubagentHandback 1  #1321
a881dd03  sonnet-5-5       6     6    62k    62k    343k     69k     69k    0k    1m  Bash 4, Read 1, SubagentHandback 1
a9a58683  sonnet-5-5       5     6    61k    61k    283k     61k     61k    0k    1m  Bash 4, Read 1, SubagentHandback 1
a84daa0c  sonnet-5-5       5     6    59k    59k    279k     97k     97k    0k    0m  Bash 4, Read 1, SubagentHandback 1
a290d3f8  haiku-4-5-20    26    26    27k    27k    596k     92k     46k    0k    2m  Bash 22, Read 3, SubagentHandback 1
aef746dd  haiku-4-5-20    31    30    36k    36k    848k    133k     66k    3k    3m  Bash 25, Read 5
TOTAL                    432   429                21.83M   3.68M   8.24M  106k
  Σctx = Σ over API calls of context at that call (the cost integral); eff = 1·input + 1.25·cache_creation + 0.1·cache_read + 5·output; priced = eff × model tier (haiku 0.5, sonnet 1, opus 2.5, fable 5, sonnet units) — a best estimate, priced per agent alone, cross-agent chatter not modelled.
```
