The pair rules of the #1716 split (design home `docs/design/elements.md` § Pair rules): what needs two elements at once and so cannot sit in Fire, Lightning or Ice while those run in parallel — Frozen muting a node's own go-offs until the break releases them, Frozen ending an arc or a disc's copy, dual reach concatenated with its dedupe switch, Catalyst under a Frozen node, and the cross-element pins. Mostly pins on what the three element units built, plus one branch and one switch.
Blocked by: #{fire}, #{lightning}, #{ice}
Blocks: none

## Acceptance spec

**Decisions**
- Pair rules are their own unit after Fire / Lightning / Ice: *"option 1. or whichever fits a DAG."* (owner, 2026-11-10).
- **Frozen mutes the node's own go-offs; the break releases what it trapped** (owner, 2026-11-08: *ice wins — frozen solid*, then *trapped until broken*; `docs/design/elements.md:803-812`; ADR 0081 §4): a node both Frozen and Shocked neither receives nor emits; the hit that breaks the ice sets off the Shocked state in the same settle, plus the shatter burst. Primed-ness and the Frozen check read pre-hit; the breaking hit's crit and damage are its own facts. The released arc reads its power **after the breaking hit lands** (owner, 2026-11-10; the spend law, `docs/design/elements.md:93-96`), so a breaker carrying Charge feeds the arc it releases.
- **Frozen ends a path**: *"a path **ends**: hops, chains and arcs stop here"* (owner, 2026-11-06; l.850-859); a copy under the break threshold is absorbed whole, a breaking copy lands, a direct hit lands (owner, 2026-11-09; l.77, ADR 0082 §3).
- **Dual reach** concatenates: *"the double counting might be a feature! tentative option 2, where union is kept as an easily switched to option if we change our minds. after all it's just a "do you dedupe the list or not" after gathering each reach medium's additional targets"* (owner, 2026-11-05; l.744-753) — every primed state present at read fires, each spending its own stacks; the dedupe is one switch at the gather step, kept as a knob (tentative). Then, on a node gathered by two reaches: *"riders twice, payload twice. charged burning nodes sounds like a dangerous concept"* (owner, 2026-11-10). It is two gathered entries, and each entry lands everything (every rider, element riders included, and the damage) at its share. On the same call: the node's own go-off fires once per hit (owner, 2026-11-10, picked over once per gathered entry), through the once-per-node set; the dedupe stays a one-line switch (l.748-752).
- Catalyst and Cold coexist: *"Catalyst under a Frozen node is colourless until a hit's element lands; a direct Cold hit deepens the freeze (a Cold copy is absorbed), a Heat hit thaws harder"* (l.943-948) — reviewed, taken as settled.
- *"Heat & Cold don't make sense together. frostBITE is an ailment"* (owner, 2026-11-04; l.945-947) — Heat never touches a Frostbite pack; carried by #1444, not here (NOTES).

**Knobs** (tentative defaults)
- `dedupe_dual_reach: bool = false` — `@export` on the resource #{resolver} hosts the gather's tunables on (#{refresh} names the file). `false` = concatenate (the owner's tentative option 2). Editor feedback: the blast sandbox tab (or its Catalyst-era successor)'s reach readout shows the doubled entries. Tests pin both settings, never assume the default.

**Composition**
- Burning and Frozen cannot coexist on a node: Heat and Cold net into one signed `t` (#{terrain}). So "Frozen mutes the node's own go-offs" is Frozen + Shocked in practice; build no Frozen + Burning branch.
- **The mute** is one branch in the gather's read step (#{resolver}): when the node's temperature band is Frozen and Ice's breaker answer (#{ice}) says this hit does not break it, the node's other bands' go-offs are dropped from the read. When it does break, the shatter (#{ice}) and the released Shocked go-off (#{lightning}) commit in the same generation, each spending its own stacks; the arc's power is the Charge after the breaking hit's riders land (owner, 2026-11-10). If the gather's shape makes this more than one branch reading two existing answers, stop and say so (a fork, not a refactor).
- **Frozen ending an arc / a disc copy** needs no new code: Ice's `admits` on the Frozen band answers every arriving copy, whoever's go-off sent it. This unit pins it across elements.
- **Dual reach**: each go-off gathers its own list; the gather concatenates them, or dedupes when the switch is on. A node reached twice is two entries (owner, 2026-11-10). Each entry lands its element riders on terrain and its payload, at its share, so the node takes the riders twice, takes damage twice and has two rows in the blast table. Its own go-off fires once per hit (owner, 2026-11-10). This supersedes the "under the once-per-node cap" phrasing at l.646-649 for element riders; the drone corrects that doc line.
- Owns nothing new beyond the switch. Readers: the record's blast table, the blast VFX path.

**Files touched**
- #{resolver}'s gather (read step) — the mute branch and the dedupe switch.
- `test/unit/attack/test_element_pairs.gd` — new, the cross-element pins.
- #{terrain-ui}'s terrain bar and tooltip — the trapped-Charge styling (#{refresh} names the files).
- `docs/domain/` — the element domain doc #{defs}…#{ice} created gains a "Pair rules" section (the table at l.796-801 as built).

**Acceptance** (all in `test/unit/attack/test_element_pairs.gd`; exact `CombatWorld` fixtures, `crit_chance` zeroed except where a crit is the breaker)
1. Frozen + Shocked, a direct hit under the break threshold: the hit lands on the node; no arc; no Charge spent; neighbours untouched.
2. Frozen + Shocked, a breaking direct hit (damage ≥ the ice break threshold, and separately a crit): the shatter burst lands, the node arcs to every neighbour in the same settle, both spends commit. Run it twice: with a breaker carrying no Charge rider the arc's power is the trapped Charge's excess; with a breaker carrying Charge the power includes what it landed (post-land), and on a node sitting one stack under the next ladder level that rider lifts the arc a level.
3. Frozen + Shocked, an arriving copy under the threshold: absorbed whole, nothing lands, no arc; a breaking copy lands and releases the arc.
4. A Shocked node's arc whose neighbour is Frozen: that neighbour absorbs the under-threshold copy and no hop continues past it; other neighbours land normally. Same for a Burning disc's copy onto a Frozen node.
5. A Cold arrow onto a Shocked node lays Cold on every arc target (`ceil(r × s)`), and onto a Burning node lays Cold over the disc (l.512-516).
6. Burning + Shocked on one node, a single hit: both go off, each spending its own stacks; a neighbour inside both the disc and the arc appears twice in the blast table with `dedupe_dual_reach = false` and once with `true`. With `false` it receives the hit's element riders twice (its terrain int moves by both shares), every other rider twice and damage twice. In both settings it sets off at most once.
7. Catalyst under Frozen: 3 Catalyst + a Heat hit of 1 converts to 4 Heat netted against the Cold (a bigger thaw than the Heat alone); a direct Cold hit converts into Cold and deepens; a Cold copy is absorbed and leaves the Catalyst untouched.
8. Visual, the trapped Charge (handed over from #{terrain-ui}, which already draws both bars on a Frozen node): the player can tell that the Charge on a Frozen + Shocked node is trapped. It is held under the ice and will go off when the ice breaks, which looks different from Charge on an unfrozen node. The read comes from the band function alone, on the node's bars and tooltip; no stored flag.
9. Visual: a release beat shows the shatter and the arcs on the same beat, played from the record; a dual reach draws both marks (disc and arcs) at one node. Checked in the blast sandbox tab, screenshot attached to the report.
10. Every surviving test of #{fire}, #{lightning}, #{ice} stays green unedited.

**NOTES**
- Reading list and seam map were cut before #{defs}…#{catalyst} landed; #{refresh} re-cuts the stamp. If `mise run issue-drift` still flags this issue at dispatch, stop and say so.
- The look may be handed to a sub-agent working in this same worktree once the hook it draws from (signal, record field, scene stub) exists; the unit's drone stays the owner and reviewer of the result.
- The bars themselves are #{terrain-ui}'s, and this unit adds only the trapped styling. The shatter and arc VFX are #{ice}'s and #{lightning}'s; this unit only checks they compose.
- Frostbite (#1444): cold passage through Frozen (no shed) and "Heat never touches a Frostbite pack" ride #1444, which is blocked by #{ice}; no Frostbite code here.
- The no-parent go-off ("terrain hit") has no caller (`docs/design/elements.md:498-503`); not built here.
- The next element ADR's corrections (0081 §5-§7, §9; 0082's Context) are a sibling issue.
- "A wire evens itself out" stays parked (handoff § 3).

**Stubs on master** — none — shapes are named in Composition; the drone adds them.

```drift-stamp bd800181
docs/design/elements.md:70-108 — the trigger table; what a go-off pays; copies carry everything
docs/design/elements.md:196-207 — what breaks the ice; every check reads pre-hit
docs/design/elements.md:512-524 — a copy carries everything, terrain riders included
docs/design/elements.md:640-661 — stage one per node under the once-per-node cap; stage two per entry
docs/design/elements.md:693-707 — one snapshot per beat; spends committed together
docs/design/elements.md:744-753 — dual reach concatenated; the dedupe switch
docs/design/elements.md:791-821 — pair rules table; Frozen mutes, the break releases
docs/design/elements.md:850-865 — travel verbs: Frozen ends a path
docs/design/elements.md:943-948 — Catalyst under Frozen; Heat never touches Frostbite
docs/adr/0081-a-go-off-pays-one-per-node-reached-catalyst-replaces-fuel-and-a-cast-carries-one-element.md:26-33 — §2-§4: shatter, breakers, Frozen mutes Shocked
docs/adr/0082-a-hit-resolves-in-two-stages-terrain-gathers-the-target-set-then-payload-lands-per-target.md:25-37 — two stages; absorption; the dedupe knob at the gather
attack/outcome/attack_record.gd:209-218 — the blast table columns a doubled entry lands in
attack/outcome/attack_record.gd:698-730 — _capture_blast / _rebuild_blasts
attack/outcome/hit_landing.gd:80-85 — today's per-landing `detonated` dedupe scope (the gather's once-per-node set replaces it)
graph/graph_mirror.gd:225-260 — nodes_within, the one hop BFS
attack/outcome/attack_record.gd — seam: blast table rows for doubled entries
ui/vfx/blast_vfx.gd — seam: draws each blast mark on Events.blast_landed
addons/sandbox_host/tabs/71_blast_panel.gd — seam: the blast sandbox tab for the visual check
effects/status/corruption.gd — seam: the shared burst path the shatter rides (27-28)
```
