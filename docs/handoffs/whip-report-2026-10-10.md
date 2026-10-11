# Whip report 2026-10-10

**Landed 11/11 · 61 commits `84ee00d..master` · back to Needs design 0 · orphaned In progress 0 · dropped 0 · still Ready 0**

## Landed
- #1526 Blocker tiers look identical: small, medium and large Dormant Cores need a visual tell
- #1530 Addon cap reads stake level, not fill (+ ADR for the #1528 calls)
- #1531 Procgen addons: draw nodes with replacement, a repeat draw stakes the node
- #1532 Extract denies when it would leave more addons than the cap
- #1534 Seamless Abstract Pack as a shader-texture library (CC0 provenance + first consumer #1526)
- #1536 Staking channels: stake and extract step toward a target cap over turn starts, inside a leash
- #1537 Staking channels cross the wire: snapshot rows, fingerprint fold, save bump, mp:e2e
- #1538 Staking channels are visible: reach/leash denials, tooltip progress, node channel cue
- #1539 ADR: staking is a channel on the node; knobs are exports until stat defs
- #1549 
- #1550 

## Back to Needs design
- none

## Still Ready
- none

## Orphaned In progress
- none

## Dropped by the owner
- none

## Filed since start (2026-10-10T17:33:33Z)
#1550 Staking channels: a Cancel card in the Manage tray
#1549 Staking channels: a live electric lasso from core to channelling node
#1548 Instance-uniform slots overflow on first_level_sandbox (1359 'Too many instances' errors in 30 s under opengl3)
#1540 Whip run 2026-10-10

## Needs the owner
- 2026-10-10 19:58 needs owner #1526 (train a, lead-a): eyeball in first_level_sandbox: lobes 1/2/3 by tier, slow motion, same-tier cores differ, 3 damage stages; tune knobs (tier_lobes, blob_radius_scale, deform_speed 0.15, glitch_intensity 0.35, damage_spread 0.4, void colour)
- 2026-10-10 19:58 needs owner #1534 (train a, lead-a): eyeball: blob interior reads as tinted pattern not rainbow; layer_a/b_scale tuned for 256px now drive 512px; texture picks 28/11 (contact-sheet regen cmd in docs/domain/abstract-textures.md)
- 2026-10-10 21:34 needs owner #1537 (train c, lead-c): save migration: MIN_FORMAT_VERSION=7 (v7 loads) contradicts ADR 0042 'refused, never migrated' — supersede that clause with a new ADR or drop v7 support
- 2026-10-10 21:34 needs owner #1539 (train c, lead-c): ADR 0004 'predates' note put in 0053 Consequences (accepted ADRs immutable) — edit 0004 only if wanted
- 2026-10-10 21:34 needs owner #1537 (train c, lead-c): mp:e2e never runs the sandbox sweep (AI lobby); acceptance 4/5 verified by hand host/client autopilot (43 in-sync); autopilot-only overrides: 4 MP + leash_ratio 1.0
- 2026-10-10 21:34 needs owner #1536 (train c, lead-c): tentative knobs: stake_reach_px 250, stake_leash_ratio 2.0, stake/extract channel turns 2/3, stake_sp_cost 1, extract_sp_refund 1; blockers rolled past 3 now keep stake (5) and lift ceiling
- 2026-10-10 21:34 needs owner #1538 (train c, lead-c): eyeball rim pulse (period 1.4, floor 0.35, flash 0.4s) + denial strings EXTRACTING/STAKING; rim goes via ring_tint since rim_ring.gdshader:295 overwrites COLOR, so feedback/status/subtype tints never reach the rim (pre-existing)
- 2026-10-10 22:05 needs owner #1549 (train c2, lead-c2): eyeball lasso (tab 73 / first_level_sandbox); tentative knobs lasso_tier_full=VALUE, pulse_strength 0.5, core_whip_kick 3.0, flash_radius 12, flash_duration 0.3, director z_index 2000; game_root.tscn ChannelLassoDirector lacks unique_id — run refresh on a clean checkout; save-load path to rebuild() untraced
- 2026-10-10 22:05 needs owner #1550 (train c2, lead-c2): Cancel card borrows Stake colour + armed_stake.png icon (ActionPalette has no cancel colour) — pick one; card widens Manage tray, eyeball width (#753)

## Incidents
- 19:33 owner: dropped #1536 from train c
- 19:48 note: owner stopped lead-a's Bash 'wait for drone transcript to reach end of turn' aft
- 20:05 owner (via #1524 swarmify session): #1536 back in Ready at rev 2 -> head of train c; new #1549 #1550 (blocked by #1536) -> train c2 after c; ~4/lead trial limit kept
- 20:33 note: train b follow-up: #1536 must wire stake_ceiling (+1 at graph_procgen.gd:1171, e

## Cost (agent-cost, latest 20)
```
agent     model        turns calls  final   peak    Σctx     eff  priced   out  wall  top tools / hints
aeedf83d  opus-5-5        26    28    65k   129k   1.36M    342k   1.73M    7k   30m  Bash 22, Agent 3, advisor 2, Read 1  #1549 wt:wt-lasso
a6107255  opus-5-5        26    27    76k   147k   1.51M    252k   1.65M    6k    6m  Bash 25, advisor 2  #1549 wt:wt-lassodir
a8bd798d  opus-5-5        34    36    75k   135k   1.93M    444k   2.01M   18k   14m  Bash 34, advisor 2  #1549 wt:wt-lasso
a7a4699f  opus-5-5        13    14    59k    59k    581k    139k    853k    6k    4m  Bash 12, advisor 2  #1550 wt:wt-cancel-channel-verb
a16c8fc2  opus-5-5        42    44    97k   102k   3.01M    823k   2.57M   14k   61m  Bash 35, Agent 6, Read 1, advisor 1  #1536
a5a746fa  opus-5-5        27    30    70k   137k   1.48M    255k   1.57M    8k    6m  Bash 28, advisor 2  #1538 wt:wt-chan-drive
a93d0658  opus-5-5        46    48   111k   111k   3.40M    518k   2.67M   12k   14m  Bash 45, advisor 3  #1537 wt:wt-snap-chan
a5c4662d  opus-5-5        46    50   100k   189k   3.31M    511k   2.93M   16k   13m  Bash 47, advisor 3  #1538
a8bd960f  sonnet-5-5      12    11    50k    50k    489k    110k    110k    1k    1m  Bash 11  #1539 wt:wt-adr-stake
aef5edfe  opus-5-5        29    29    74k    74k   1.63M    553k   1.57M   14k   64m  Bash 24, Agent 3, advisor 1, SendMessage 1  #1530 wt:wt-addon-stake-scaling
ae5f245e  opus-5-5        39    41   120k   234k   3.58M    607k   3.01M   25k   13m  Bash 38, advisor 2, Read 1  #1536 wt:wt-stake-channel
a14b83ac  opus-5-5        31    32    86k   167k   2.05M    370k   2.00M   15k    9m  Bash 30, advisor 2  #1536 wt:wt-stake-ceil
a6bdd824  opus-5-5        27    28    76k   150k   1.60M    290k   1.73M   11k    7m  Bash 26, advisor 2  #1531 wt:wt-addon-repeat-draw
a4894db2  sonnet-5-5       9     8    34k    34k    255k     68k     68k    1k    1m  Bash 8  #1532 wt:wt-addon-cap-gate
a6651b2e  opus-5-5        41    46    91k   148k   2.78M    469k   3.01M   19k   11m  Bash 41, advisor 4, SendMessage 1  #1530 wt:wt-addon-stake-scaling
a44f9788  haiku-4-5-20    34    33    34k    34k    873k    127k     64k    0k    3m  Bash 25, Read 8
a023f6e0  opus-5-5        28    30    72k   142k   1.62M    398k   1.91M   11k   25m  Bash 25, advisor 2, Agent 2, SendMessage 1  #1526
af084edf  opus-5-5        20    21    57k   106k    878k    180k   1.15M    8k    6m  Bash 17, advisor 2, Read 1, Write 1  #1534 wt:wt-abstract-textures
add9254b  sonnet-5-5       4     4    72k    72k    251k     74k     74k    1k    1m  Bash 4
a1dad933  opus-5-5        33    34    94k   185k   2.38M    436k   2.30M   20k   10m  Bash 32, advisor 2  #1526 wt:wt-dormant-core-blob
TOTAL                    567   594                34.99M   6.97M  32.98M  214k
  Σctx = Σ over API calls of context at that call (the cost integral); eff = 1·input + 1.25·cache_creation + 0.1·cache_read + 5·output; priced = eff × model tier (haiku 0.5, sonnet 1, opus 2.5, fable 5, sonnet units) — a best estimate, priced per agent alone, cross-agent chatter not modelled.
```

Tree transport: no daemon, timer or session was ever started; nothing to tear down.
