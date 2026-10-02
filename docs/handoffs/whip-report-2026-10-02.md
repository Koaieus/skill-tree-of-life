# Whip report 2026-10-02

> **Snapshot from 11:02, now stale.** Since then #1307 and #1309 landed and #1241 unit a landed (pushed 910b0b3). No leads are running. Live state: `docs/handoffs/swarm-2026-10-01.md`.

**Landed 7/12 · 30 commits `7d57a54..master` · back to Needs design 1 · dropped 0 · still Ready 1**

## Landed
- #1212 refactor(addons): draw-only SkillNodeAddon subclasses become scenes with a visual child
- #1237 Design-doc sweep: close-out (index, README map, unreferenced assets, handoff folder)
- #1257 Victory: turn limit — after N rounds, the camp with the most XP wins
- #1275 Stat scope on StatDef: which board a stat may live on, and whether a node may grant it
- #1291 Delete TempUpgradeDef: the catalog lists addon scenes, the kind crosses the wire
- #1308 Armor break is flat: -1 armor per stack, uncapped
- #1315 Whip: whip-selftest for the ledger verbs, report and watchdog paths

## Back to Needs design
- #1317 Aspect arrows: corruption, curse, wither, armor_break, blindness ammo types (the ranged column, one pass)

## Still Ready
- #1310 Status row is an int: half-up landing fold, floor-kept decay, poison/corruption decay shapes (ADR 0032)

## Dropped by the owner
- none

## Filed since start
#1326 Enable GitHub Discussions, then move the skill feedback boards there (+ mise feedback verbs)
#1325 Skill feedback boards for every charter
#1324 whip — skill feedback board

## Needs the owner
- none

## Incidents
- 2026-10-02 01:28 note: lead-a 2nd idle 01:27 was its reply to the nudge; agents state=working, waiting 
- 2026-10-02 01:28 watchdog: whip missing, resumed bbea1ab5: backgrounded · a2cf0157 · whip
  claude agents             list sessions
  claud
- 2026-10-02 01:33 launch lead-b FAILED: backgrounded · [36m0f493a88[39m · lead-b
[2m  claude agents             list sessions[22m
[2m  claude attach 0f493a88    open in this terminal[22m
[2m  claude logs 0f493a88      show recent out
- 2026-10-02 01:33 launch lead-c FAILED: backgrounded · [36m869ee360[39m · lead-c
[2m  claude agents             list sessions[22m
[2m  claude attach 869ee360    open in this terminal[22m
[2m  claude logs 869ee360      show recent out
- 2026-10-02 01:33 launch lead-d FAILED: backgrounded · [36m7b82b129[39m · lead-d
[2m  claude agents             list sessions[22m
[2m  claude attach 7b82b129    open in this terminal[22m
[2m  claude logs 7b82b129      show recent out
- 2026-10-02 01:33 launch lead-e FAILED: backgrounded · [36meb16a4dd[39m · lead-e
[2m  claude agents             list sessions[22m
[2m  claude attach eb16a4dd    open in this terminal[22m
[2m  claude logs eb16a4dd      show recent out
- 2026-10-02 01:35 note: owner-launched whip bbea1ab5 stands down: watchdog name-mismatch forked it as 'w
- 2026-10-02 01:49 watchdog: whip missing, resumed a2cf0157: backgrounded · 51573ba8 · whip
  claude agents             list sessions
  claud
- 2026-10-02 02:00 watchdog: whip missing, resumed a2cf0157: backgrounded · 0ae023a3 · whip
  claude agents             list sessions
  claud
- 2026-10-02 02:11 watchdog: whip missing, resumed a2cf0157: backgrounded · ad282a24 · whip
  claude agents             list sessions
  claud
- 2026-10-02 02:22 watchdog: whip missing, resumed a2cf0157: backgrounded · ef9cde9a · whip
  claude agents             list sessions
  claud
- 2026-10-02 02:33 watchdog: whip missing, resumed a2cf0157: backgrounded · 0b6511ac · whip
  claude agents             list sessions
  claud
- 2026-10-02 02:44 watchdog: whip missing, resumed a2cf0157: backgrounded · dd1b35a6 · whip
  claude agents             list sessions
  claud
- 2026-10-02 02:55 watchdog: whip missing, resumed a2cf0157: backgrounded · d714eea2 · whip
  claude agents             list sessions
  claud
- 2026-10-02 03:06 watchdog: whip missing, resumed a2cf0157: backgrounded · e3a46f45 · whip
  claude agents             list sessions
  claud
- 2026-10-02 03:17 watchdog: whip missing, resumed a2cf0157: backgrounded · c0c6bc88 · whip
  claude agents             list sessions
  claud
- 2026-10-02 03:28 watchdog: whip missing, resumed a2cf0157: backgrounded · ff2d5cf9 · whip
  claude agents             list sessions
  claud
- 2026-10-02 03:39 watchdog: whip missing, resumed a2cf0157: backgrounded · 3bc2f128 · whip
  claude agents             list sessions
  claud
- 2026-10-02 03:50 watchdog: whip missing, resumed a2cf0157: backgrounded · 096d0d94 · whip
  claude agents             list sessions
  claud
- 2026-10-02 04:01 watchdog: whip missing, resumed a2cf0157: backgrounded · 49fda7bf · whip
  claude agents             list sessions
  claud
- 2026-10-02 04:12 watchdog: whip missing, resumed a2cf0157: backgrounded · d3a02574 · whip
  claude agents             list sessions
  claud
- 2026-10-02 04:23 watchdog: whip missing, resumed a2cf0157: backgrounded · 70de76a9 · whip
  claude agents             list sessions
  claud
- 2026-10-02 04:34 watchdog: whip missing, resumed a2cf0157: backgrounded · 56da0c01 · whip
  claude agents             list sessions
  claud
- 2026-10-02 04:46 watchdog: whip missing, resumed a2cf0157: backgrounded · 2979011c · whip
  claude agents             list sessions
  claud
- 2026-10-02 04:57 watchdog: whip missing, resumed a2cf0157: backgrounded · ec903d88 · whip
  claude agents             list sessions
  claud
- 2026-10-02 05:07 watchdog: whip missing, resumed a2cf0157: backgrounded · 676e4adf · whip
  claude agents             list sessions
  claud
- 2026-10-02 05:18 watchdog: whip missing, resumed a2cf0157: backgrounded · 024d7f0d · whip
  claude agents             list sessions
  claud
- 2026-10-02 05:29 watchdog: whip missing, resumed a2cf0157: backgrounded · 99b05023 · whip
  claude agents             list sessions
  claud
- 2026-10-02 05:40 watchdog: whip missing, resumed a2cf0157: backgrounded · 744f58e3 · whip
  claude agents             list sessions
  claud
- 2026-10-02 05:51 watchdog: whip missing, resumed a2cf0157: backgrounded · b51d8696 · whip
  claude agents             list sessions
  claud
- 2026-10-02 06:02 watchdog: whip missing, resumed a2cf0157: backgrounded · bb66e586 · whip
  claude agents             list sessions
  claud
- 2026-10-02 06:13 watchdog: whip missing, resumed a2cf0157: backgrounded · db8cc4b8 · whip
  claude agents             list sessions
  claud
- 2026-10-02 06:24 watchdog: whip missing, resumed a2cf0157: backgrounded · 6d716c3f · whip
  claude agents             list sessions
  claud
- 2026-10-02 06:35 watchdog: whip missing, resumed a2cf0157: backgrounded · 956b36bf · whip
  claude agents             list sessions
  claud
- 2026-10-02 06:46 watchdog: whip missing, resumed a2cf0157: backgrounded · 5282bdee · whip
  claude agents             list sessions
  claud
- 2026-10-02 06:57 watchdog: whip missing, resumed a2cf0157: backgrounded · 63f37ef0 · whip
  claude agents             list sessions
  claud
- 2026-10-02 07:08 watchdog: whip missing, resumed a2cf0157: backgrounded · f773550c · whip
  claude agents             list sessions
  claud
- 2026-10-02 07:19 watchdog: whip missing, resumed a2cf0157: backgrounded · 317b9834 · whip
  claude agents             list sessions
  claud
- 2026-10-02 07:30 watchdog: whip missing, resumed a2cf0157: backgrounded · 88d08119 · whip
  claude agents             list sessions
  claud
- 2026-10-02 07:41 watchdog: whip missing, resumed a2cf0157: backgrounded · ef94f324 · whip
  claude agents             list sessions
  claud
- 2026-10-02 07:52 watchdog: whip missing, resumed a2cf0157: backgrounded · 0af9091f · whip
  claude agents             list sessions
  claud
- 2026-10-02 08:03 watchdog: whip missing, resumed a2cf0157: backgrounded · 108dbafe · whip
  claude agents             list sessions
  claud
- 2026-10-02 08:14 watchdog: whip missing, resumed a2cf0157: backgrounded · a47e5ae5 · whip
  claude agents             list sessions
  claud
- 2026-10-02 08:25 watchdog: whip missing, resumed a2cf0157: backgrounded · edc994b9 · whip
  claude agents             list sessions
  claud
- 2026-10-02 08:36 watchdog: whip missing, resumed a2cf0157: backgrounded · 6ec08fa6 · whip
  claude agents             list sessions
  claud
- 2026-10-02 08:47 watchdog: whip missing, resumed a2cf0157: backgrounded · fe9ad635 · whip
  claude agents             list sessions
  claud
- 2026-10-02 08:58 watchdog: whip missing, resumed a2cf0157: backgrounded · 5c18cce0 · whip
  claude agents             list sessions
  claud
- 2026-10-02 09:09 watchdog: whip missing, resumed a2cf0157: backgrounded · 30eda91c · whip
  claude agents             list sessions
  claud
- 2026-10-02 09:20 watchdog: whip missing, resumed a2cf0157: backgrounded · f6bfd6e3 · whip
  claude agents             list sessions
  claud
- 2026-10-02 09:31 watchdog: whip missing, resumed a2cf0157: backgrounded · d97eef72 · whip
  claude agents             list sessions
  claud
- 2026-10-02 09:42 watchdog: whip missing, resumed a2cf0157: backgrounded · 4c0cf505 · whip
  claude agents             list sessions
  claud

## Cost (agent-cost, latest 20)
```
agent     model        turns calls  final   peak    Σctx     eff  priced   out  wall  top tools / hints
awhip-re  fable-5-1       33    61   206k   400k   5.29M    813k   7.48M   85k   27m  Bash 45, Read 8, Write 4, advisor 2  #1319
ab410ecb  haiku-4-5-20    30    29    78k    78k   1.48M    331k    166k   23k    4m  Bash 27, Read 2  #1307
a2afd4ee  haiku-4-5-20    10     9    54k    54k    395k    148k     74k    9k    2m  Bash 7, Read 2
aflake-p  sonnet-5-5      25    25    81k    81k   1.61M    305k    305k   10k    6m  Bash 25
aSageC-0  fable-5-1       24    26    99k    99k   1.69M    256k   1.28M   18k    8m  Bash 21, SendMessage 4, Read 1  #1237
ad1237-5  sonnet-5-5      16    16    55k    55k    764k    168k    168k    8k    7m  Bash 15, SendMessage 1  #1237 wt:wt-d1237
ad1241a-  opus-5-5        27    25    79k    79k   1.69M    319k    796k   16k    6m  Bash 24, SendMessage 1
ad1275b-  opus-5-5        27    25    70k    70k   1.45M    293k    733k   16k    5m  Bash 23, SendMessage 2  #1275
ad1212-1  opus-5-5        44    44   109k   209k   3.79M    609k   3.24M   23k    9m  Bash 40, advisor 2, SendMessage 2  #1212
awhipche  opus-5-5         9    11    57k   113k    514k    165k   1.73M    9k    6m  Bash 8, advisor 3  #1315 wt:wt-whip-selftest
ad1257b-  opus-5-5        19    20    66k   128k   1.05M    228k   1.66M   12k    5m  Bash 18, advisor 2  #1257
a9df487f  haiku-4-5-20     5    15    69k    69k    171k    129k     65k    7k    1m  Read 13, Bash 2  wt:wt-retire-cure-per-hp
ad1291r-  sonnet-5-5       6     5    35k    35k    199k     70k     70k    2k    1m  Bash 4, bash 1  #1291
acb0e609  sonnet-5-5      18    17    85k    85k   1.26M    245k    245k    4k    5m  Bash 17
ace55c8a  sonnet-5-5       6     4    58k    58k    329k     66k     66k    1k    4m  Bash 4
adrone-l  opus-5-5        21    23    80k   149k   1.44M    318k   2.07M   17k    7m  Bash 21, advisor 2  #1307
adrone-b  sonnet-5-5      16    16    54k    54k    718k    176k    446k    8k    2m  Bash 15, advisor 1  #1308
adrone-c  sonnet-5-5      10    10    50k    50k    418k    103k    103k    5k    1m  Bash 10  #1309
ae440261  haiku-4-5-20    26    25    29k    29k    597k    109k     54k    3k    2m  Bash 20, Read 5
ac183706  haiku-4-5-20    32    47   104k   104k   1.61M    286k    143k    1k    2m  Read 26, Bash 21
TOTAL                    404   453                26.47M   5.14M  20.91M  276k
  Σctx = Σ over API calls of context at that call (the cost integral); eff = 1·input + 1.25·cache_creation + 0.1·cache_read + 5·output; priced = eff × model tier (haiku 0.5, sonnet 1, opus 2.5, fable 5, sonnet units) — a best estimate, priced per agent alone, cross-agent chatter not modelled.
```
