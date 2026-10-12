# Whip report 2026-10-11

**Landed 14/16 · 81 commits `b186e9e..master` · back to Needs design 2 · orphaned In progress 0 · dropped 0 · still Ready 0**

## Landed
- #1386 Curse × Addon: Doombrand — +1 aspect on the map, 2 curse per contact, a kill spills harder
- #1505 Poison × Spell: Remedy — the boon face (cleanse)
- #1551 Turnless hosts never tick statuses: blockers and dormant cores tick on a world turn, one every N played turn ends
- #1552 World turn: TurnManager ends one world turn every N played turn ends
- #1555 Poison × Spell: Remedy kit — cure table, drain cure effect, status filter, need-split spread
- #1558 Per-concept stats: hand-declared triplets, or a typed per-concept shape?
- #1559 Concept→stat edge: derive StatusDef / AmmoType / AspectCurrency ids from StatDef.role
- #1560 Curse × Spell: Malediction — the shipped hex reshaped: downhill by floor, ties fork, a minor fraction to the rest
- #1566 Corruption sandpile: SandpileSpread rule + the burst hook (topple-only damage)
- #1567 Corruption sandpile: CombatWorld settles topples every beat, recorded; corruption switches over
- #1569 Corruption × Spell: Purification — corruption and curse cure on Remedy's kit
- #1571 Scout lantern: LanternLayer — dynamic fog layer + view-only lit nodes
- #1572 Scout lantern: arrows, eagle_eye and scout_line carry lanterns
- #1573 Scout lantern: scout blade vertices carry lanterns

## Back to Needs design
- #1393 Scout × Addon: blade face and watchtower look
- #1561 Curse × Spell: Gloomflux — 1 damage, add, double, copy out through Curse's spill

## Still Ready
- none

## Orphaned In progress
- none

## Dropped by the owner
- none

## Filed since start (2026-10-11T15:12:03Z)
#1573 Scout lantern: scout blade vertices carry lanterns
#1572 Scout lantern: arrows, eagle_eye and scout_line carry lanterns
#1571 Scout lantern: LanternLayer — dynamic fog layer + view-only lit nodes
#1570 Corruption: retune every source's stacks per hit under topple-only damage
#1569 Corruption × Spell: Purification — corruption and curse cure on Remedy's kit
#1568 Corruption sandpile: how (and whether) a core topples
#1567 Corruption sandpile: CombatWorld settles topples every beat, recorded; corruption switches over
#1566 Corruption sandpile: SandpileSpread rule + the burst hook (topple-only damage)
#1565 Whip run 2026-10-11

## Needs the owner
- 2026-10-11 17:43 needs owner #1505 (train a, lead-a): eyeball Remedy tint Color(0.72,0.94,0.78) + sandbox cast (acceptance 3, needs rendered frame)
- 2026-10-11 18:35 needs owner #1393 (train b, lead-b): melee temp-upgrade tray scaling past 5 cards (906px vs 890 cap) — blocks #1393 temp face and every new addon; #1393 → Needs design, map face landed
- 2026-10-11 18:35 needs owner #1561 (train b, lead-b): #1562 rider-order rule needed to author Gloomflux add→double→copy-out; #1561 → Needs design, WIP on wt-gloomflux ccda7f9 (3 red tests)
- 2026-10-11 18:35 needs owner #1386 (train b, lead-b): hotkey N picked for 5th temp card (one line in project.godot); eyeball Doombrand pentagram; knobs rider power 2, spill_scale 2.0
- 2026-10-11 18:35 needs owner #1560 (train b, lead-b): tentative knob off_path_share 0.25
- 2026-10-11 18:35 needs owner #1393 (train b, lead-b): eyeball watchtower lantern; knob temp_cost_blade_size 1
- 2026-10-11 19:20 needs owner #1573 (train e, lead-e): approve lead calls: scout-vertex = rider applies ScoutStatus, no lantern while aiming; core HP bar under lantern_lit?; give watchtower rider a power for real blade-lantern radius
- 2026-10-11 19:20 needs owner #1566 (train e, lead-e): tentative knobs SandpileSpread burn 1 keep 0 max_topples 4096; settle_round_cap 32 (#1567)
- 2026-10-11 19:20 needs owner #1571 (train e, lead-e): eyeball lantern fog fold in live sandbox; knobs max_lanterns 64, fade_seconds 0.25, node_grid_cell 128, lantern_radius_scale 1.0 (not in tunables.md); edges stay hidden under lantern on full fog — visual call
- 2026-10-11 19:20 needs owner #1569 (train e, lead-e): Purification poison rate 0.0 (0.1 for 'almost nothing'); tint picked by drone, reuses Remedy hospital_cross icon + VFX
- 2026-10-11 19:20 needs owner #1567 (train e, lead-e): 3 unfiled sandpile sync gaps (burst kill in live replay, gate flip degree change, burst order after resync) — worth a spec'd issue

## Incidents
- 17:14 owner: dropped #1558 from train c
- 17:14 owner: dropped #1559 from train c
- 17:16 owner: dropped #1386 from train d
- 17:16 owner: dropped #1393 from train d
- 17:16 owner: dropped #1560 from train d
- 17:16 owner: dropped #1561 from train d
- 17:16 note: owner: the Ready bulk is ONE DAG — a lead launches whatever front is unblocked (
- 18:35 owner: dropped #1571 from train f
- 18:35 owner: dropped #1572 from train f
- 18:35 owner: dropped #1573 from train f
- 18:35 owner: dropped #1569 from train g

## Cost (agent-cost, latest 20)
```
agent     model        turns calls  final   peak    Σctx     eff  priced   out  wall  top tools / hints
a2721f79  opus-5-5        36    42   104k   104k   2.52M    586k   1.72M   16k   44m  Bash 28, Agent 11, Read 1, advisor 1  #1566 wt:wt-gloomflux
a8574a83  sonnet-5-5      10     9    41k    41k    339k     86k     86k    1k    2m  Bash 9  #1573 wt:wt-bladeradius
a26c810d  opus-5-5        34    35    73k   115k   1.92M    368k   2.01M   10k   18m  Bash 32, advisor 3  #1573 wt:wt-blade-lantern
ac51d3bc  opus-5-5        44    47   139k   139k   4.14M    647k   2.62M   18k   17m  Bash 44, advisor 2, Write 1  #1567 wt:wt-sandpile-plumbing
a364737a  opus-5-5        33    36    96k   191k   2.28M    391k   2.25M   14k   11m  Bash 34, advisor 2  #1572 wt:wt-scout-lanterns
a4fd8832  opus-5-5        39    40   106k   106k   2.90M    498k   2.01M   20k   13m  Bash 36, advisor 2, Write 2  #1571 wt:wt-lantern-layer
aa12e0b6  opus-5-5        33    34    84k   166k   2.08M    345k   1.93M   10k    8m  Bash 32, advisor 2  #1566 wt:wt-sandpile-spread
a46fc8ff  sonnet-5-5      10     9    46k    46k    381k     92k     92k    0k    2m  Bash 9  #1569 wt:wt-purification
a552419d  haiku-5-5        8     7    53k    53k    348k     73k     36k    0k    0m  Bash 7  #1393
afb32ff8  haiku-5-5        3     2    39k    39k    109k     56k     28k    0k    0m  Bash 2  #1505 wt:wt-gloomflux
a1f4d213  haiku-5-5        8     9    70k    70k    377k     97k     48k    0k    0m  Bash 9  #1393 wt:wt-gloomflux
ae72f4f1  haiku-5-5        3     2    49k    49k    126k     69k     35k    0k    0m  Bash 2  #1505 wt:wt-gloomflux
a6076a3c  opus-5-5        59    65   126k   126k   5.38M   1.09M   3.23M   25k   52m  Bash 53, Agent 7, SendMessage 4, advisor 1  #1552 wt:wt-concept-facets
a4017a40  opus-5-5        31    32    90k    90k   2.11M    356k   1.61M   11k    9m  Bash 30, advisor 2  #1393 wt:wt-scout-addon-1393
a878c85d  sonnet-5-5      20    18    62k    62k    995k    255k    255k    4k   14m  Bash 18  #1559 wt:wt-stat-edge
a138bdf1  opus-5-5        36    38   112k   216k   2.96M    495k   2.68M   17k   12m  Bash 36, advisor 2  #1561 wt:wt-gloomflux
a93712a8  opus-5-5        40    42   104k   145k   2.91M    566k   3.32M   19k   26m  Bash 37, advisor 4, SendMessage 1  #1552 wt:wt-world-turn-1552
aed7778d  opus-5-5        60    61   118k   166k   4.83M    814k   3.61M   20k   19m  Bash 57, advisor 3, SendMessage 1  #1558 wt:wt-concept-facets
a38d8c04  opus-5-5        45    48   101k   195k   3.36M    498k   2.92M   12k   11m  Bash 43, advisor 3, Write 2  #1560 wt:wt-malediction
a5a551f2  opus-5-5        28    30    99k    99k   1.97M    347k   1.58M   11k   10m  Bash 28, advisor 2  #1386 wt:wt-doombrand
TOTAL                    580   606                42.04M   7.72M  32.09M  209k
  Σctx = Σ over API calls of context at that call (the cost integral); eff = 1·input + 1.25·cache_creation + 0.1·cache_read + 5·output; priced = eff × model tier (haiku 0.5, sonnet 1, opus 2.5, fable 5, sonnet units) — a best estimate, priced per agent alone, cross-agent chatter not modelled.
```

Tree transport: no daemon, timer or session was ever started; nothing to tear down.
