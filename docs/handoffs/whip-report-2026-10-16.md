# Whip report 2026-10-16

**Landed 19/21 · 73 commits `800c58f..master` · back to Needs design 1 · orphaned In progress 0 · dropped 0 · still Ready 1**

## Landed
- #431 One teardown atom in AllocationSystem
- #739 the core healing aura never reaches the effect readout — CoreAura is not an Effect
- #1370 Bruiser: land current-% health damage (it still lands flat)
- #1628 Test fixtures, child 1: TestWorld + one fixture home
- #1629 Spike Ring: spikes / spike_regen scale with allocation level, not stake
- #953 Node health bar: projected status damage segment + status icon row
- #1092 Design: corruption reads as a dark segment on the health bar; do DoTs proc at turn end?
- #1305 Bare force_deallocate drops statuses without spill (sandbox panels only today)
- #1570 Corruption: retune every source's stacks per hit under topple-only damage
- #1066 test purity: test_splash waits on the real clock (5.9 s) — splash sequence schedule or integration tier
- #1623 test purity tail: CommandApplier pre-roll on TweenClock
- #1625 test purity tail: FloaterDirector + CameraDirector on TweenClock
- #1626 test purity tail: melee preview steps BladeSwingClock; wall-clock tests to integration
- #1627 test purity tail: BUDGET sleeps → wait_until (14 scripts) + classify 5 newcomers
- #1630 Clamp: escalating temp cost per extra temp clamp on a swing
- #1631 Bunker refit: floor −5, blast-shielded on blades
- #1632 Remove Fortress (fortification_addon); swing_drag stays unowned
- #1633 Rigid break snaps the hit edge or the hitter's pivot-ward edge, not the most-strained rung
- #1635 Retire golden replays/fixtures (owner: no goldens until most of the game ships)

## Back to Needs design
- #1624 test purity tail: TweenClock for EdgeEnergize, FanTrace, modifier pulse, trail blazer

## Still Ready
- #1606 Explosive barrel: temp-placeable — one AoE hit on impact — not reached (run ended: no lead left)

## Orphaned In progress
- none

## Dropped by the owner
- none

## Filed since start (2026-10-16T14:57:52Z)
#1645 Test fixtures, sweep: test/unit/vfx/ onto TestWorld
#1644 Test fixtures, sweep: test/unit/combat/ onto TestWorld
#1643 Test fixtures, sweep: test/unit/network/ onto TestWorld
#1642 Test fixtures, sweep: test/unit/effects/ onto TestWorld
#1641 Test fixtures, sweep: test/unit/ui/ onto TestWorld
#1640 Test fixtures, sweep: test/unit/systems/ onto TestWorld
#1639 Test fixtures, sweep: test/unit/attack/ onto TestWorld
#1638 Test fixtures, sweep: test/unit/ (top level, non-recursive) onto TestWorld
#1637 Whip run 2026-10-16

## Needs the owner
- 2026-10-16 18:52 needs owner #1624 (train a, relief-a-1): modifier-pulse site is driven by Projectile._process, not a tween; options on the issue (hub #1070 moved with it)

## Incidents
- 17:32 relief relief-a-1 recorded for the top to spawn: top relieves lead-a
- 18:13 note: both leads cut off by the session limit (429) ~17:35; resumed with continue at 1
- 18:43 note: relief-a-1 asked relief with only d1628b left; declined per §7 (train done at th
- 18:52 relief-a-1: needs owner #1624 — modifier-pulse site is driven by Projectile._process, not a tween; options on th
- 18:52 relief-a-1 DONE 69e5876 19/21

## Cost (agent-cost, latest 20)
```
agent     model        turns calls  final   peak    Σctx     eff  priced   out  wall  top tools / hints
af1588a7  opus-5-5        76    87   162k   162k   7.94M   1.21M   3.25M    1k   80m  Bash 67, Agent 14, SendMessage 4, advisor 1
a8abc8cf  opus-5-5        24    26    52k    52k    972k    143k    785k    0k    8m  Bash 22, advisor 2, SendMessage 1, SubagentHandback 1  #1628 wt:wt-fixtures-to-support
a0558f43  opus-5-5        30    32    80k    80k   1.76M    253k   1.28M    0k    8m  Bash 28, advisor 2, SendMessage 1, SubagentHandback 1  #1635 wt:wt-sweep-goldens
a01e2dd9  sonnet-5-5      21    25    47k    47k    786k    119k    522k    0k    8m  Bash 21, advisor 2, SendMessage 1, SubagentHandback 1  #1627 wt:wt-d1627a
a4458bc2  sonnet-5-5       8     9    41k    41k    264k     60k     60k    0k    3m  Bash 7, SendMessage 1, SubagentHandback 1  #1627 wt:wt-d1627b
a738d683  opus-5-5        31    35    91k    91k   1.99M    290k   1.45M    0k   12m  Bash 31, advisor 2, SendMessage 1, SubagentHandback 1  #1633 wt:wt-d1633
ac3c3f04  sonnet-5-5      17    20    53k    53k    708k    117k    550k    0k    5m  Bash 16, advisor 2, SendMessage 1, SubagentHandback 1  #1624
adcafe45  opus-5-5        69    83   139k   139k   6.27M    971k   2.64M    1k   88m  Bash 62, Agent 14, SendMessage 5, advisor 1  #431
adffeb9e  sonnet-5-5      10    11    40k    40k    343k     67k     67k    0k    2m  Bash 9, SendMessage 1, SubagentHandback 1  #1570 wt:wt-t1570
ad9a6294  sonnet-5-5       7     8    39k    39k    229k     54k     54k    0k    2m  Bash 6, SendMessage 1, SubagentHandback 1  #1624
ade7ae5b  opus-5-5        14    17    53k    53k    582k    103k    726k    0k    7m  Bash 14, advisor 2, SubagentHandback 1  #1626 wt:wt-d1626
a34626bc  sonnet-5-5      18    20    55k    55k    752k    126k    126k    0k    4m  Bash 17, bash 1, SendMessage 1, SubagentHandback 1  #1623 wt:wt-t1625
a62ff8b9  sonnet-5-5      14    15    50k    50k    556k    100k    100k    0k    3m  Bash 13, SendMessage 1, SubagentHandback 1  #1626 wt:t1626
ab72f5b9  sonnet-5-5      17    18    53k    53k    696k    122k    122k    1k    3m  Bash 14, SendMessage 2, SubagentHandback 2  #1625 wt:wt-i1625
a2e890fd  sonnet-5-5       4     5    30k    30k    112k     33k     33k    0k    1m  Bash 3, SendMessage 1, SubagentHandback 1  #1066 wt:wt-move-splash-1066
ad14113f  sonnet-5-5       8    10    34k    34k    238k     50k     50k    0k    2m  Bash 8, SendMessage 1, SubagentHandback 1  #1623 wt:wt-i1623
a5f49fb9  opus-5-5        24    24    63k    63k   1.09M    212k   1.03M    0k   41m  Bash 20, advisor 2, SendMessage 1, SubagentHandback 1  #1629 wt:wt-spike-ring-1629
ac1385a9  sonnet-5-5      19    19    51k    51k    719k    183k    417k    0k   39m  Bash 17, advisor 1, SubagentHandback 1  #1635 wt:wt-g1635
ae4c6e8f  opus-5-5        27    31    95k    95k   1.77M    363k   1.62M    0k   47m  Bash 26, advisor 2, Write 1, SendMessage 1  #1092 wt:wt-i1092
a0e83f8e  opus-5-5        21    22     0k    79k   1.16M    192k   1.13M    0k    9m  Bash 20, advisor 2  #1630 wt:wt-i1630
TOTAL                    459   517                28.94M   4.76M  16.02M    6k
  Σctx = Σ over API calls of context at that call (the cost integral); eff = 1·input + 1.25·cache_creation + 0.1·cache_read + 5·output; priced = eff × model tier (haiku 0.5, sonnet 1, opus 2.5, fable 5, sonnet units) — a best estimate, priced per agent alone, cross-agent chatter not modelled.
```

No daemon, timer or session was ever started; nothing to tear down.
