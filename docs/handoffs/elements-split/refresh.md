Re-cut the specs of the eight late element children once the spine (#{defs} → #{catalyst-blade}) has landed. No code lands: this unit is a board pass that makes every late issue true against the new master before a drone picks it up. Parent hub #1716; design home `docs/design/elements.md`.

Blocked by: #{catalyst-blade}
Blocks: #{blade-elements} (the other seven late units are blocked through it)

## Acceptance spec

**Decisions** (owner, 2026-11-10)
- *"all children ready, but add 1 extra issue … make it be blocking later ones. and that issue just tells to update the specs?"* — this issue is that one (owner, 2026-11-10).
- Pair rules are their own unit after Fire / Lightning / Ice: *"option 1. or whichever fits a DAG."* (owner, 2026-11-10) — so #{pairs} is one of the eight, not folded into #{fire}/#{lightning}/#{ice}.
- A late spec that turns out to need a *design* decision is not guessed at here: it moves to `Needs design` with the fork written as a menu (pass ruling, 2026-11-10, from the spec fence: "You write what was decided; you never decide a design fork").

**Knobs** — none (written call: no code, no tunables).

**Composition**
The eight late issues each carry an `## Acceptance spec` and a `drift-stamp bd800181` block cut before the spine landed. `mise run issue-drift` reads the **last** stamp on an issue (body, then comments, in order), so a fresh stamp posted as a comment supersedes the old one without editing the body. This issue owns nothing in the tree; it owns the truth of eight issue texts. Order of the pass: #{blade-elements} first (the other seven build on it), then #{fire}, #{lightning}, #{ice}, then #{pairs}, #{forge}, #{quiver}, #{forge-ui}. #{ice-cast} is `Needs design` and is not re-cut here.

Per issue, the pass is:
1. `mise run issue-drift -- <n>` (add `--json` for the per-entry `{path, start, end, drifted, reason, ins, del, hunk}` list). Silent + exit 0 means no stamped entry was touched; one line per drifted entry otherwise. `missing-at-stamp` = a typo or a never-built path; `created-since-stamp` = a file a spine unit built (real information: the spec may now cite it).
2. Re-open every reading-list range on current master and move each to the lines that now teach the same thing; drop an entry whose subject is gone.
3. Re-grep every seam-map entry on current master (`git grep`, never recall) and add the files the spine created that the unit now touches (e.g. the `Element` def and roster from #{defs}, the `NodeState` terrain ints and band function from #{terrain}, the settle routine from #{flow}, the gather from #{resolver}, the `GoOff` disc from #{go-off-zero}, Burning's band and Heat row from #{burning}, the Catalyst status from #{catalyst}).
4. Grep the issue body for symbols the spine renamed or deleted and correct each sentence that names one (list below). The correction states the new symbol and where it lives; it never changes a decision.
5. Post one comment holding the corrected sentences (if any) and one fresh fenced block, info string `drift-stamp <current master sha>`, with the full re-verified reading list and seam map — 5-15 reading entries, every `docs/design/elements.md` citation with a line range, never a path that does not exist yet.
6. Re-run `mise run issue-drift -- <n>`: it must be silent against the new stamp.
7. If step 4 finds a sentence that cannot be corrected without choosing between two shapes (the spine built something the late spec did not foresee), stop on that issue: write the fork as a menu (title names the fork, problem in two lines, each option described by what it *is*, your tentative pick marked) as a comment, and move the issue to `Needs design`. Do not stamp it.

Symbols to grep for in each late body (all renamed or deleted by the spine; confirm against master, the spine's merged commits are the truth):
`Role.ASPECT` / `_aspect` facet naming (→ `COUNT`, #{defs}) · `SPENT_KEY`, `_node_spent` (both spend ledgers, deleted by #{go-off-zero}) · `detonated` per-wave scope, `HitLanding.detonated` (#{go-off-zero}) · `stamp_landing`, `DetonateEffect._spend`, `PairedDamageEffect` stamping (the three stampers, folded by #{applier}) · `DetonateEffect`, `DetonateUse`, `detonate_load`, `default_face`, `use_for_status` (#{go-off-zero} / #{catalyst}) · `ExplosiveSpread`, `explosive`, `explosive_aspect`, `explosive_stacks_per_hit`, the `charge` tag, `ExplosiveBarrelAddon` (#{catalyst}) · `vertex_charges`, `piece_charges`, `BladeChargeBand`, `_admit_explosive` (#{catalyst-blade}) · `FuelUse`, `FuelBlastReach` (deleted by #{catalyst}; Firecracker now plants Heat) · the world-turn period `_note_played_turn_end` (#{flow}).

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
9. Any issue that hit step 7 is in `Needs design` with its menu comment, and is reported as such instead of a stamp URL.
10. Deliverable, as the final report: one line per issue — `#<n> — <comment URL> — clean | corrected (<k> sentences) | Needs design (<fork in five words>)`.

**NOTES**
- No code, no commit, no stub. A defect found in spine code is a new issue linking back to the spine unit, never a fix here.
- Do not re-scope a late unit (move work between them) — that is a design call; write it as step 7's menu.
- #{ice-cast} is a `Needs design` menu, not a spec: it carries no stamp to re-cut. If a spine rename touches its menu text, correct the sentence in a comment, nothing more.
- Not specced anywhere and not to be pulled in: the next element ADR's corrections (ADR 0081 §5-§7 and §9, ADR 0082's Context), the inner-tree shape for elements, generator keystones #1787, melee crit condition #1786, the Cold spell #1789, Greed's own spec.
- Lane rules for the move to `Needs design`: `docs/domain/issue-workflow.md`.

**Stubs on master** — none — shapes are named in Composition; the drone adds them.

```drift-stamp bd800181
.mise/tasks/issue-drift:1-40 — the command, the last-stamp-wins rule, drift rules per entry, the flags
.claude/skills/spec/SKILL.md:82-104 — what a reading list, seam map and drift stamp must hold
.claude/skills/spec/SKILL.md:26-34 — the Needs design menu shape for an unresolvable fork
docs/handoffs/elements.md:227-275 — the child list and order the late units come from
docs/handoffs/elements.md:276-386 — the coverage audit and knobs each late spec folded in
docs/design/elements.md:682-726 — the resolver's five build calls: the spine's renames and deletions in the doc's words
docs/design/elements.md:1021-1048 — the Catalyst retag list the late specs were cut against
docs/domain/issue-workflow.md — lanes and the Needs design move
```
