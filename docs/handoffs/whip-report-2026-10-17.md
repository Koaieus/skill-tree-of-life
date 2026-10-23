# Whip report 2026-10-17

**Landed 29/32 · 156 commits `b82ed8c..master` · back to Needs design 1 · orphaned In progress 0 · dropped 0 · still Ready 0**

## Landed
- #1401 Armor break row, child 0: armor penetration stat (flat and/or %)
- #1638 Test fixtures, sweep: test/unit/ (top level, non-recursive) onto TestWorld
- #1639 Test fixtures, sweep: test/unit/attack/ onto TestWorld
- #1640 Test fixtures, sweep: test/unit/systems/ onto TestWorld
- #1641 Test fixtures, sweep: test/unit/ui/ onto TestWorld
- #1642 Test fixtures, sweep: test/unit/effects/ onto TestWorld
- #1645 Test fixtures, sweep: test/unit/vfx/ onto TestWorld
- #1651 Inner aspect ring: ring resource, points, spend command, snapshot, AI spender
- #1654 Faced Dormant Cores: per-aspect core class, size-scaled grants, pinned loot offer
- #1655 Aspect spirits: procgen-placed skill dust with a fixed +1 aspect offer, plus a gray mystery variant
- #1663 Inner ring: ring renderer + sandbox tab
- #1664 Inner ring: ring modal + buy flow
- #1665 Inner ring: hero card opens the ring + unspent badge
- #1666 Inner ring: build silhouette on the hero card
- #1667 Inner ring: inspect another entity's silhouette (core visible only)
- #1671 Spell picker chips: shared IdentityChip — dark pill, tinted rrect border, bare tinted glyph + count
- #1672 Projectile visuals: one VisualDrain helper replaces seven copied done-latches
- #1673 ComposedProjectileVisual tints its arrival companions + tint_strength; Healing Beam folds onto the wrapper
- #1674 ImpactRing reads visit_index; Reverberator folds onto the stock wrapper
- #1676 Armor break row: armor_pierce lines in the DEX pool
- #1679 Shop card: fixed-size TempUpgradeButton with a price strip
- #1680 GraphCamera.reveal(rect, policy): nudge or centre a world rect into view
- #1682 Blade-node menu: click a picked node for un-pick + a growing CardFan of placeable temps
- #1683 Z–B quickbar: per-run temp-upgrade favourites replace the catalog row
- #1684 Melee tray receipt strip (click to refund) + hover detail panel
- #1686 Cracked core hands its statuses to the entity (rider-order prerequisite)
- #1687 Concept card: StatusSections + self-describing spread + ConceptCard scene
- #1688 Status riders land before their paired hit: landing-scoped priority + two-step gate
- #1689 Inline concept token {id:amount} + BadgeLabel tooltip; crucible readout adopts it

## Back to Needs design
- #1606 Explosive barrel: temp-placeable — one AoE hit on impact

## Still Ready
- none

## Orphaned In progress
- none

## Dropped by the owner
- none

## Filed since start (2026-10-17T15:49:37Z)
#1690 Ring grants lost from core_modifiers after snapshot restore: Entity-held RingTable seam or by-value row?
#1689 Inline concept token {id:amount} + BadgeLabel tooltip; crucible readout adopts it
#1688 Status riders land before their paired hit: landing-scoped priority + two-step gate
#1686 Cracked core hands its statuses to the entity (rider-order prerequisite)
#1687 Concept card: StatusSections + self-describing spread + ConceptCard scene
#1685 Quickbar favourites survive a mid-run save/load
#1684 Melee tray receipt strip (click to refund) + hover detail panel
#1683 Z–B quickbar: per-run temp-upgrade favourites replace the catalog row
#1682 Blade-node menu: click a picked node for un-pick + a growing CardFan of placeable temps
#1681 Role tags on addons: categories for the shop's canonical order
#1680 GraphCamera.reveal(rect, policy): nudge or centre a world rect into view
#1679 Shop card: fixed-size TempUpgradeButton with a price strip
#1678 Whip run 2026-10-17

## Needs the owner
- none

## Incidents
- 18:18 relief relief-a-1 recorded for the top to spawn: top relieves lead-a
- 18:56 relief relief-a-2 recorded for the top to spawn: top relieves relief-a-1
- 18:57 note: relief-a-2 blocked on relief-a-1
- 19:10 relief-a-1 drained: returned, relieved
- 19:40 relief-a-2 DONE 5b4b20f 22/23

## Cost (agent-cost, latest 20)
```
agent     model        turns calls  final   peak    Σctx     eff  priced   out  wall  top tools / hints
add06889  opus-5-5        69    81   149k   149k   6.46M   1.54M   4.07M    1k   94m  Bash 63, Agent 13, SendMessage 2, advisor 1  #1686
a0b63eed  opus-5-5        10    12    45k    45k    351k     75k    586k    0k    4m  Bash 9, advisor 2, SubagentHandback 1  #1688
aa0726df  opus-5-5        29    31    73k    73k   1.46M    215k   1.12M    0k   11m  Bash 28, advisor 2, SubagentHandback 1  #1605 wt:wt-sweep2
ab40093e  opus-5-5        24    27    88k    88k   1.62M    247k   1.35M    0k   10m  Bash 23, advisor 2, SendMessage 1, SubagentHandback 1  #1684 wt:wt-melee-receipt
afc64715  opus-5-5        40    43   112k   112k   3.09M    421k   2.35M    0k   15m  Bash 37, advisor 3, SendMessage 2, SubagentHandback 1  #1683 wt:wt-temp-quickbar
a0a59af5  opus-5-5        42    43   108k   108k   3.33M    443k   1.96M    0k   14m  Bash 39, advisor 2, SendMessage 1, SubagentHandback 1  #1682 wt:wt-1682b-blade-menu
a3b72bef  opus-5-5        13    15    54k    54k    535k    100k    736k    0k    5m  Bash 12, advisor 2, SubagentHandback 1  #1688 wt:wt-sweep
ae48f94a  opus-5-5        56    59   160k   160k   6.06M    773k   2.99M    1k   19m  Bash 54, advisor 2, Write 1, SendMessage 1  #1688 wt:wt-rider-order
acacddd1  opus-5-5        24    23    68k    68k   1.24M    186k   1.01M    0k   10m  Bash 20, advisor 2, SubagentHandback 1  #1689 wt:wt-badge-label
acf14e99  opus-5-5        19    21    77k    77k   1.04M    177k   1.08M    0k   10m  Bash 17, advisor 2, SendMessage 1, SubagentHandback 1  #1682 wt:wt-cardfan-1682a
a01aef63  opus-5-5        39    39    87k    87k   2.47M    338k   1.51M    0k   10m  Bash 35, advisor 2, SendMessage 1, SubagentHandback 1  #1686 wt:wt-core-crack-status
a4dc1681  opus-5-5        32    37    94k    94k   2.14M    316k   1.83M    1k    9m  Bash 30, advisor 3, SendMessage 2, SubagentHandback 2  #1687 wt:wt-status-card-1687
a5828cd8  opus-5-5        21    23    69k    69k   1.12M    181k   1.03M    0k    8m  Bash 20, advisor 2, SubagentHandback 1  #1679 wt:wt-temp-upgrade-price
aa705864  opus-5-5        14    16    56k    56k    609k    114k    743k    0k    8m  Bash 13, advisor 2, SubagentHandback 1  #1680 wt:wt-cam-reveal-1680
ad9156b0  opus-5-5        46    51   112k   112k   3.52M    612k   1.80M    1k   44m  Bash 42, Agent 5, SubagentHandback 2, advisor 1  #1401
a2df48b6  opus-5-5        25    27    68k    68k   1.25M    189k   1.03M    0k    6m  Bash 23, advisor 2, SendMessage 1, SubagentHandback 1  #1667 wt:wt-ring-inspect
a9f04228  opus-5-5        48    48   131k   131k   4.63M    709k   2.47M   19k   12m  Bash 43, advisor 2, Skill 1, Agent 1
a550d650  fable-5-1       11    11    79k    79k    757k    124k    621k    2k    2m  Bash 4, Edit 3, Read 1, Write 1
a07ac6ca  opus-5-5        44    45   104k   104k   3.37M    450k   1.83M    1k   14m  Bash 39, advisor 2, SubagentHandback 2, Write 1  #1666 wt:wt-ring-silhouette
a91a7587  opus-5-5        16    19    70k    70k    842k    157k    990k    0k    6m  Bash 15, advisor 2, SendMessage 1, SubagentHandback 1  #1674 wt:wt-reverb-ring
TOTAL                    622   671                45.87M   7.37M  31.09M   29k
  Σctx = Σ over API calls of context at that call (the cost integral); eff = 1·input + 1.25·cache_creation + 0.1·cache_read + 5·output; priced = eff × model tier (haiku 0.5, sonnet 1, opus 2.5, fable 5, sonnet units) — a best estimate, priced per agent alone, cross-agent chatter not modelled.
```

No daemon, timer or session was ever started; nothing to tear down.
