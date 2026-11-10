Re-cut the specs of the late element children (every unit this one blocks, directly or through another; the list is in Composition) once the spine (#{defs} → #{catalyst-blade}) has landed. No code lands: this unit is a board pass that makes every late issue true against the new master before a drone picks it up. Parent hub #1716; design home `docs/design/elements.md`.

Blocked by: #{catalyst-blade}
Blocks: #{blade-elements} (every other late unit is blocked through it)

## Acceptance spec

**Decisions** (owner, 2026-11-10)
- *"all children ready, but add 1 extra issue … make it be blocking later ones. and that issue just tells to update the specs?"* — this issue is that one (owner, 2026-11-10).
- Pair rules are their own unit after Fire / Lightning / Ice: *"option 1. or whichever fits a DAG."* (owner, 2026-11-10) — so #{pairs} is one of the late units, not folded into #{fire}/#{lightning}/#{ice}.
- A late spec that turns out to need a *design* decision is not guessed at here: it moves to `Needs design` with the fork written as a menu (pass ruling, 2026-11-10, from the spec fence: "You write what was decided; you never decide a design fork").

**Knobs** — none (written call: no code, no tunables).

**Composition**
The late set is named by rule: every unit this one blocks, directly or through another. Each carries an `## Acceptance spec` and a drift-stamp block cut before the spine landed (a unit with no stamp, such as a `Needs design` menu, has nothing to re-cut). `mise run issue-drift` reads the **last** stamp on an issue (body, then comments, in order), so a fresh stamp posted as a comment supersedes the old one without editing the body. This issue owns nothing in the tree; it owns the truth of the late issue texts. The set, by placeholder: #{blade-elements}, #{fire}, #{lightning}, #{ice}, #{pairs}, #{forge}, #{quiver}, #{forge-ui}, and, if filed behind this unit (blocked by it directly or through #{forge} / #{forge-ui}), the cast shapes spec #{cast-shapes} (Fire's disc and Lightning's levels on a cast), the Ice concentrate #{ice-cast} and #{overqualified-casting}. Check the board for what this unit blocks when the pass starts, and re-cut that set; a unit not filed behind this one is not part of the pass. Order of the pass: #{blade-elements} first (the rest build on it), then #{fire}, #{lightning}, #{ice}, then #{pairs}, #{forge}, #{quiver}, #{forge-ui}, then the cast shapes, Ice concentrate and overqualified casting specs if they are in the set.

Per issue, the pass is:
1. `mise run issue-drift -- <n>` (add `--json` for the per-entry `{path, start, end, drifted, reason, ins, del, hunk}` list). Silent + exit 0 means no stamped entry was touched; one line per drifted entry otherwise. `missing-at-stamp` = a typo or a never-built path; `created-since-stamp` = a file a spine unit built (real information: the spec may now cite it).
2. Re-open every reading-list range on current master and move each to the lines that now teach the same thing; drop an entry whose subject is gone.
3. Re-grep every seam-map entry on current master (`git grep`, never recall) and add the files the spine created that the unit now touches (e.g. the `Element` def and roster from #{defs}, the `NodeState` terrain ints and band function from #{terrain}, the settle routine from #{flow}, the gather from #{resolver}, the `GoOff` disc from #{go-off-zero}, Burning's band and Heat row from #{burning}, the Catalyst status from #{catalyst}).
4. Grep the issue body for symbols the spine renamed or deleted and correct each sentence that names one (list below). The correction states the new symbol and where it lives; it never changes a decision.
5. Post one comment holding the corrected sentences (if any) and one fresh fenced block, info string `drift-stamp <current master sha>`, with the full re-verified reading list and seam map — 5-15 reading entries, every `docs/design/elements.md` citation with a line range, never a path that does not exist yet.
6. Re-run `mise run issue-drift -- <n>`: it must be silent against the new stamp.
7. If step 4 finds a sentence that cannot be corrected without choosing between two shapes (the spine built something the late spec did not foresee), stop on that issue: write the fork as a menu (title names the fork, problem in two lines, each option described by what it *is*, your tentative pick marked) as a comment, and move the issue to `Needs design`. Do not stamp it.

Symbols to grep for in each late body (all renamed or deleted by the spine; confirm against master, the spine's merged commits are the truth):
`Role.ASPECT` / `_aspect` facet naming (→ `COUNT`, #{defs}) · `SPENT_KEY`, `_node_spent` (both spend ledgers, deleted by #{go-off-zero}) · `detonated` per-wave scope, `HitLanding.detonated` (#{go-off-zero}) · `stamp_landing`, `DetonateEffect._spend`, `PairedDamageEffect` stamping (three of the five landing-to-hit stampers, the ones #{applier} folds; `haul_effect.gd:47-54` and `splash_effect.gd:128-146` are not folded) · `DetonateEffect`, `DetonateUse`, `detonate_load`, `default_face`, `use_for_status` (#{go-off-zero} / #{catalyst}) · `ExplosiveSpread`, `explosive`, `explosive_aspect`, `explosive_stacks_per_hit`, the `charge` tag, `ExplosiveBarrelAddon` (#{catalyst}) · `vertex_charges`, `piece_charges`, `BladeChargeBand`, `_admit_explosive` (#{catalyst-blade}) · `FuelUse`, `FuelBlastReach` (deleted by #{catalyst}; Firecracker now plants Heat) · the world-turn period `_note_played_turn_end` (#{flow}).

**Files touched** — none (board only).

**Acceptance**
1. #{blade-elements}: `mise run issue-drift -- <n>` silent against a fresh stamp comment; no sentence names a symbol from the list above that master no longer has.
2. #{fire}: same as 1.
3. #{lightning}: same as 1.
4. #{ice}: same as 1.
5. #{pairs}: same as 1.
6. #{forge}: same as 1; its Catalyst starter line names the status id #{catalyst} landed.
7. #{quiver}: same as 1.
8. #{forge-ui}: same as 1.
9. If filed behind this unit: #{cast-shapes}, #{ice-cast} and #{overqualified-casting}: same as 1 (a `Needs design` one with no stamp follows NOTES instead).
10. Any issue that hit step 7 is in `Needs design` with its menu comment, and is reported as such instead of a stamp URL.
11. Deliverable, as the final report: one line per issue — `#<n> — <comment URL> — clean | corrected (<k> sentences) | Needs design (<fork in five words>)`.

**NOTES**
- No code, no commit, no stub. A defect found in spine code is a new issue linking back to the spine unit, never a fix here.
- Do not re-scope a late unit (move work between them) — that is a design call; write it as step 7's menu.
- #{cast-shapes} is the cast shapes spec (Fire and Lightning on a cast) and #{ice-cast} the Ice concentrate. If it is filed behind this unit and carries a stamp, re-cut it like any late unit; if it is still a `Needs design` menu with no stamp, there is nothing to re-cut, and a spine rename that touches its text is corrected in a comment, nothing more.
- Not specced anywhere and not to be pulled in: the next element ADR's corrections (ADR 0081 §1, §3, §5, §6, §7 and §9, ADR 0082's Context), the inner-tree shape for elements, generator keystones #1787, melee crit condition #1786, the Cold spell #1789, Greed's own spec.
- Lane rules for the move to `Needs design`: `docs/domain/issue-workflow.md`.

**Stubs on master** — none — shapes are named in Composition; the drone adds them.

```drift-stamp efba0bc3
.mise/tasks/issue-drift:1-40 — the command, the last-stamp-wins rule, drift rules per entry, the flags
.claude/skills/spec/SKILL.md:82-104 — what a reading list, seam map and drift stamp must hold
.claude/skills/spec/SKILL.md:26-34 — the Needs design menu shape for an unresolvable fork
docs/design/elements.md:703-752 — the resolver's five build calls: the spine's renames and deletions in the doc's words
docs/design/elements.md:1074-1101 — the Catalyst retag list the late specs were cut against
docs/domain/issue-workflow.md — lanes and the Needs design move
```
