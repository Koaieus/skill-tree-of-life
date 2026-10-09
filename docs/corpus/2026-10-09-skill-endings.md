# Skill endings — how user-facing skill runs closed, 2026-08-10 → 2026-10-09

Scan behind `docs/domain/session-report.md`. Sonnet-labelled, keyword
heuristics for the content kinds (directional), structural detection for
tables/headers (reliable). Rows: `2026-10-09-skill-endings-rows.jsonl`
(id8, date, skill, labels, a 200-char quote per final message). Method: for
each session launched as a skill (`<command-name>` in the first user
record, or free text `<skill> #…`), take the last assistant text ≥ 300 chars.
Caveats added after review: (1) free-text launches that name content rather
than issue numbers were missed by the `#` rule; (2) the owner extends most
runs past the report, so the sampled text is usually a post-report exchange
— directional for structure, not a census of reports.


## 1. Per-skill table (% of final messages)

| skill | n | landed | shas | tests | notdone | followups | issues_filed | board | cost | next | questions | docs | feedback | table | bullets | numbered | boldlead | headers | med words |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| warp | 23 | 82 | 86 | 69 | 47 | 26 | 4 | 65 | 34 | 13 | 4 | 56 | 0 | 17 | 73 | 8 | 39 | 8 | 261 |
| swarmify | 95 | 49 | 29 | 64 | 31 | 31 | 14 | 56 | 38 | 15 | 4 | 54 | 6 | 14 | 67 | 9 | 63 | 6 | 253 |
| relay | 4 | 75 | 75 | 50 | 50 | 25 | 0 | 25 | 25 | 0 | 0 | 25 | 0 | 0 | 25 | 0 | 0 | 0 | 138 |
| whip | 24 | 8 | 95 | 4 | 95 | 0 | 0 | 8 | 0 | 8 | 0 | 12 | 0 | 0 | 8 | 0 | 4 | 0 | 130 |
| relief | 20 | 95 | 80 | 85 | 40 | 40 | 25 | 60 | 45 | 10 | 10 | 60 | 5 | 5 | 80 | 10 | 75 | 0 | 254 |
| swarm | 42 | 73 | 59 | 71 | 35 | 45 | 14 | 35 | 45 | 19 | 7 | 57 | 9 | 16 | 57 | 11 | 50 | 7 | 213 |
| ALL | 208 | 58 | 55 | 61 | 42 | 30 | 12 | 47 | 35 | 14 | 4 | 50 | 5 | 12 | 59 | 8 | 50 | 5 | 218 |

## 2. Top headers

- 'frame': 1
- 'the flow: a tiny state machine with three states': 1
- 'configured view, top to bottom': 1
- 'picker panel': 1
- 'sample data': 1
- 'deliverable': 1
- 'final state': 1
- 'swarm 2026-09-16 — done, pushed (`96208a7` → `origin/master`)': 1
- 'performance, both runs (8 units, all single-opus-stamped)': 1
- 'landed': 1

## 3. Samples

### most structured warp -- warp 2026-10-07 06748516 (issues [])
```
The kit lets you build an arrow look by putting parts in a scene, with no new script. Every look is an inherited scene of `status_arrow.tscn`. It changes the parts the base already has or adds more from `ui/vfx/projectile/visual/arrow_parts/`.

## How a look works

The base arrow scene has three parts:

| Node | Part | Role |
|---|---|---|
| `Trail` | shed emitter | streak behind the flight |
| `Tip` | tip | status-coloured head over the arrowhead |
| `Burst` | impact emitter | one-shot spray when the hit counts |

`StatusArrow` finds every part under it and calls each one at the same moments:

1. **paint**: the shot's status colour, or a dud or absorbed result.
2. **launch**: the arrow leaves the string. Only arrows that carry a status do anything.
3. **stop**: the arrow struck or was spent.
4. **arrive**: the landing counted, so the part plays its impact effect at the context the coordinator passed in.
5. **drain_seconds**: how long the part outlives its stop. The arrow waits for its longest part before reporting finished.

Your existing calls are unchanged: one status colour per shot, stamped by the coordinator. Each part lifts that colour to its own named glow level (`Emissive` tier); nothing uses a hand-picked brightness. With no status, every part hides and you get a plain light arrow.

## Shared settings on every part

| Setting | Default | Meaning |
|---|---|---|
| `show_on_dud` | off | Stays visible (greyed) when the shot lands as a dud. |
| `show_on_absorbed` | off | Stays visible when the defender absorbed the shot. Status parts normally step aside so the arrow can show the defender's result. |
| `fades_with_shaft` | off | Fades out with the shaft after the hit. |

These rules live in one place, so no look has to code dud or absorbed handling.

## The four parts

**Tip** (`arrow_tip.tscn`): visible on duds, fades with the shaft.
- `shape`:
  - pointed: triangle
  - blunt: flat nose
  - club: round knob
- `length` and `width` in pixels. The default 12×10 matches today's tip.
```

### most structured swarm -- swarm 2026-09-15 864fd37e (issues [])
```
## Swarm 2026-09-16 — done, pushed (`96208a7` → `origin/master`)

**Landed (5/5):** #899 `0493e16` · #437 `7055bdc` · #880 `1f70b71` · #881 `0ccddbf` · #898 `48990ff`, plus three test re-points of mine. Hub #868 auto-closed (all 9 children done). Push carried the previous lead's 19 unpushed landings too.

**Suite verdict, exactly:** run 1 on `48990ff` → 3 red (all `panel_scene` readers #881 orphaned); run 2 on `3c60ac7` → 1 red (a fourth such test, hidden behind the first three). Fixed, verified by `test:one` + `check` only; the final tip never had a fully-green full run, but the delta since run 2 is one test file. 483 scripts = 483 tracked, nothing skipped. **#908** (filed, Needs design): `85_frontmatter_tab` trips a shader-compiler condition — pre-existing on `9c5a5aa`, order-dependent (fires under `test:one`, not in either full run).

**Owner-eyeball outstanding:** #880 tint in the node-visuals tab (drone's screenshot was an unallocated node — pixels unverified); #898 acceptance 3 in `first_level_sandbox` (aura faint at default intensity); #899 red vs blue in `dev_sandbox` (if red still reads dimmer it's chroma, not luminance).

**Leftovers:** #907 (DDA bucketing) is `blocked-by #898`, now spent — #898's harness table on the issue is its input. Four foreign worktrees untouched. Both ledgers deleted.

### Performance, both runs (8 units, all single-Opus-stamped)

| unit | tier | ctx@report | calls | advisor | priced |
|---|---|---|---|---|---|
| #897 | opus | 84k | 42 | 1 | 1.21M |
| #898 | opus | 125k | 46 | 1 | 1.94M |
| #874 | sonnet | 108k | 64 | 1 | 803k |
| #729 | sonnet | 130k | 77 | 0 | 839k |
| #899 | sonnet | 67k | 31 | 1 | 295k |
| #437 | sonnet | 71k | 34 | 0 | 393k |
| #880 | sonnet | 130k | 87 | 1 | 1.00M |
| #881 | sonnet | 90k | 44 | 0 | 502k |

Sonnet mean ≈ 640k (3.4× spread), opus ≈ 1.6M; this wave 4.13M vs the 4.5M estimate. Lead (me): hook marker 155k at 02:05 after 3 dispatches, 327k at close — ~1.7× over-report, so ~90k → ~190k actual, plus 3 Fable advisor calls. `agent-cost` doesn't price the lead; that's the missing line for sizing the next one.

**Headline process finding:** #881's stamp said "no GUT coverage, no red test". Four tests read `panel_scene`; the drone trusted the stamp, I trusted the report, and `land` ran zero tests because the branch touched no test dir — three layers on one false premise. Same class as 09-15's #874 fence gaps: **stamps under-enumerate consumers of the changed thing.** Two possible homes, your pick: (a) swarmify's "no coverage" claim must carry `grep -rln <symbol> test/` as evidence; (b) `land` runs `test:dir res://test/unit/` when a branch deletes a public symbol or touches no test dir.

Smaller data points: the drone hard-stop is self-counted (#880 took 87 of 80 and ran all of `test/unit` against "never the full suite"); both opus units finished under 50 calls and hit their advisor once, at a real fork; my one fence error (#881's `sandbox_host.gd` docstring) cost one commit.

I'm past the context ceiling — ending here.
```

### swarmify -- swarmify 2026-10-07 10eb044c (issues [])
```
Paste this to Designer Claude:

```
Build a quick interactive HTML preview of the "Magic" body of the command tray in a turn-based, skill-tree strategy game (Godot HUD, "Arcane Terminal" style). It's a UX mock: fake data, clickable states, no game logic.

## Frame
- Show a dark game board behind it (a faint graph of glowing nodes and edges is plenty). The command tray is bottom-anchored, about 930px wide, with a tab strip above it (Manage · Melee · Ranged · Magic; Magic is active).
- The Magic body is about 930 × 180px. Hard ceiling: 890px of content width and 230px height. Nothing may grow it past that.
- Style: dark ink-navy panels, thin cool-grey 1px borders, compact monospace-ish UI text at 9–12px, section headers in a Cinzel-style serif. Magic's identity colour is INT blue #4A96FF. Gold is reserved for "this number is yours / caster-scaled" highlights and never means harm. Glow is used sparingly, on the active and armed things only.

## The flow: a tiny state machine with three states
1. Configured (the default when Magic is armed). The current spell is already equipped, so a repeat cast takes no clicks.
2. Picker open. A floating panel opens upward out of the top edge of the body, like a drop-up, and overlaps the board. It does not change the body's size.
3. Targeted. The player has clicked an enemy node on the board, and Launch becomes enabled.

Transitions:
- Clicking the collapsed spell button toggles the picker.
- Picking a spell in the picker equips it and closes the picker.
- Right-click (or Esc in the mock) closes the picker.
- Clicking a board node while the picker is open closes the picker and targets that node in the same click.
- Digit keys 1–9 pick the Nth spell directly.
- On first ever arm, with no spell yet chosen, the picker starts open.
- Changing spell and coming back restores that spell's last infusion.

## Configured view, top to bottom
Top row:
- One collapsed spell tile (about 80–96px square), styled like a picker tile: spell icon/badge, name, tick marks along the top edge for the minimum source-node degree, and a small key-chip in the corner ("1").
- A dim context label ("source degree 3").
- A "⟲ Reset" button.
- A big "Cast <Spell>" launch button, about 150×44, tinted INT blue. It is disabled until a target is set.

Middle: four compact text columns side by side, each about 180px minimum, with a small header and 2–4 lines:
- **Cast**: who it can hit, range ("Enemy node · 4 hops" with 4 in gold).
- **On arrival**: damage and effects ("12 damage" with 12 in gold, "Applies Poison").
- **Then**: propagation ("Bounces to 2 neighbours, −30% each").
- **Crits**: crit behaviour, or empty.

Bottom row:
- **Infusion steppers.** A header "slots 1/2 · points 3/4", then one stepper per aspect the caster holds: a small coloured glyph, a "2 / 5" value and −/+ buttons.
  - A "+" greys out when a cap bites, and its tooltip names the cap.
```

### whip/relay/relief -- relief 2026-10-01 5d313974 (issues ['1199', '1243', '1255', '1263', '1264', '1297', '1298', '1299', '1300', '1301', '2', '3'])
```
All five units are landed and pushed. The full suite passed (5,645 tests, 0 failures) and the two-process `mp:e2e` run agreed, with no divergences. No drones or worktrees are left, and the board is clean.

| Issue | What landed | Status now |
|---|---|---|
| #1291 | `TempUpgradeDef` deleted; the catalog scans `skill_node/addons/defs/` for addon scenes, and temp upgrades are sent over the network by scene path | Needs design |
| #1275 | `StatDef` says whether an entity board or a node may grant a stat, and both entry points reject a wrong grant; a test checks all shipped content | Needs design |
| #1257 | Turn-limit victory: TurnManager counts rounds, and after 15 rounds the camp with the higher summed level wins; it's an option in all three lobbies, and `mp:e2e` now plays with it | Needs design |
| #1274 | The ranged attack camera now frames the leaves that actually fire, so it no longer swings away on launch | Closed; your visual check is still to do |
| #1243 | Keystone scenes moved to `skill_node/keystone/` | Closed |

As you asked, the three issues with open questions are reopened in Needs design, with the landed code kept. The questions are posted on each issue for swarmify:
- **#1291:** a comment in `attack/spell/spell_def.gd` that's attributed to you now says something no longer true.
- **#1275:**
  - It kept the `arrows` stat the spec said to delete, because the quiver still reads it.
  - In a deallocation cascade, stripping a node that grants `dealloc_damage` lowers the damage of the nodes after it.
  - One path for adding a modifier to a single node is still unchecked.
- **#1257:** the second `mp:e2e` run ended in a draw, which is a case for making the camp score a setting. Also, the lobby label repeats the 15-round limit instead of reading it.

The push re-closed #1275 after I'd reopened it, so I reopened it again. That race and your three rules (delete merged worktrees, move stalled hubs to Needs design, "Ready = ready") are now in the swarm skill and the issue-workflow doc.

My context is at about 165k, past the 150k target, so this is my stopping point. The ledger names what's next for a relief session: #1237 (design-doc sweep close-out, sonnet) and #1241 (delete `AttackPlanSlot`, which #1274 no longer blocks).
```

### unstructured/short -- relief 2026-09-18 9e45a89a (issues ['495', '954', '958'])
```
Sage stood down; its final ledger matches mine (3 approved, none rejected, none mis-tiered). Its one "loose end" — the untracked `bench_ranged_geometry.gd.uid` — was already committed on master at 3ebf8ea earlier tonight, so nothing remains.

The swarm is closed. Nothing further in flight on my side.
```


## 5. Exclusions
{'not-skill': 141, 'no final>=300': 10} ; kept 208
## 2b. Top bold-lead pseudo-headers (line-start **X**)
- 'what landed': 5
- 'waiting on you': 3
- 'landed': 3
- 'next': 3
- 'filed': 3
- 'what i checked': 2
- 'for the relief session': 2
- 'loose ends': 2
- 'where things stand': 2
- 'two things to know': 2