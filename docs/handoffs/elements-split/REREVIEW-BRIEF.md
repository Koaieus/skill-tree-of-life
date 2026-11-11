# Re-review brief — elements split (#1716), the prompt for the ONE re-review subagent

You are a fresh reviewer for the elements-split issues (#1716). Repo checkout: /home/bramh/skill-tree-of-life (master). Read-only, except the one findings file named below: never edit an issue, never change git state, never edit another repo file.

**Scope:** the 19 issues edited in tonight's fix round: #1793, #1795, #1796, #1798, #1799, #1800, #1801, #1804, #1805, #1806, #1807, #1808, #1809, #1810, #1811, #1812, #1813, #1814, #1816. Pull each once to a file (`gh issue view <n> --json body -q .body > <scratch>/<n>.md`, scratch = `/tmp/claude-1000/-home-bramh-skill-tree-of-life--claude-worktrees-bridge-cse-01JiczcvyVHXpsNLGqc1tGjQ/c196f62b-8129-5924-94f0-7e702f98674c/scratchpad/rr/`). The bodies are long (10-40k characters each, ~120k tokens together): read them with grep and section reads, not whole, wherever that is enough.

**The bar:**
- `docs/handoffs/elements-split/FIX-BRIEF.md`: the rules the writers followed and its "shared arithmetic". This is what the bodies must say.
- ADRs 0081-0091 (`docs/adr/008*`, `docs/adr/009*`); 0086-0091 are the new ones. ADR 0091 §3 is under an open fork (the NOTE in FIX-BRIEF); bodies follow 0091 as it stands.
- `docs/design/elements.md`: only the sections the bodies cite (`grep -n '^#' docs/design/elements.md`). Lines marked tentative there stay tentative.
- Ownership and order: `docs/handoffs/elements-split/ORDER.md` (`{name}` placeholders map to numbers in `NUMBERS.md`), `REVIEW-rulings.md`.

**Find, per issue:**
A. Contradictions across bodies: one decision stated two ways; a seam one body assumes another ships but the other does not; one decision owned by two issues; Blocked-by / Blocks lines that disagree with ORDER.md.
B. Stale citations: an ADR § that does not say what the body claims; a superseded ADR or § cited for a call a newer ADR makes; an owner quote not found verbatim in elements.md or an ADR.
C. Untestable acceptance: an item a cold implementer can't test from the body and its reading list (no observable, no numbers, no seam).
D. The fork NOTE: a body that cites the flat damage breaker, the break threshold or the raw amount as thrown must open with the NOTE (FIX-BRIEF § The 02:43 fork). List missing and unneeded NOTEs.
E. Arithmetic: every stated landing count against ADR 0086 §1 / §3 and 0090 §1 (the hit node takes 1 + 1 per channel going off from it; a node one channel reaches takes 1; two channels: 2 landings, or one at share × channels with dedupe on; the hit node never merged; a break counts as 2 channels, plus the burst) and against 0091 (generations; one read per node per generation; one shatter; only breakers take the 2 extra landings).
F. Open forks: every design decision a body leaves open ("open", "asked of the owner", "decided nowhere", "not decided"). This is the Ready gate: list per issue, or "none". A tentative reading that is marked tentative and has a default is not a fork; say which you counted.
Do NOT report: wrong `elements.md` line ranges or drift stamps (a restamp pass follows); tentative readings correctly marked tentative.

**Points the writers raised. Check each against the sources; do not assume the writer is right:**
1. Landings of a breaking hit: #1807 says 1 + `break_channels` (3 at default); #1808 says 2 + b (4 at default). One is wrong, or the pair case has an extra channel (a released Shocked go-off).
2. #1806 (acc 3a, "The hop depth and the stagger") says #1798's gather lands a depth-d copy d generations after the arc's arrival; #1798 says it ships no hop seat. Which body must carry the seat, and is it specified enough to build?
3. #1793 acc 2 pins "only Burning has `light`"; #1805 acc 3c says the overflow band lights too.
4. #1801's pointer "the volley order with the goo at 2 is #1810's" against #1810, which no longer states a goo order.
5. #1805 uses `SkillNode.terrain_changed`, owned by #1796, without a blocker on #1796.
6. #1807 acc 3b: a go-off copy's raw amount includes the go-off's own damage (D + d). Consistent with 0086 and #1798?
7. #1814 NOTES (~:77) states #1809's ride-after-aspects clamp order as a fact; #1809 now leaves the order open (the trim order is asked of the owner).
8. #1809 (~:15) "keeps its name (owner, 2026-11-10)" against `elements.md`'s "renamed, not reshaped".
9. #1801 says the settle seat runs "per beat"; #1795 now commits twice per generation (a land batch, then a spend batch).
10. #1799 says #1798's read step (acc 2) treats "0 reached, no go-off" as a gather rule while ADR 0081 §1 makes it the owner's; go-off zero keeps today's spend on a lone node. Do the two bodies agree on who owns the rule and what a lone charged node does?

**Output:** write findings to `/home/bramh/skill-tree-of-life/docs/handoffs/elements-split/REVIEW-3.md` as you go (append per issue, so nothing is lost if you run out of context). Format: a heading per issue; findings numbered T1, T2, … across the file, each with the quoted passage, the source it breaks, and the minimal fix (one sentence; name the issue that should change when it is a cross-body finding). Then a section "Open forks per issue" (F), then "Writer points 1-10" with a verdict each. Final message under 250 words: finding counts per issue, the cross-body contradictions one line each, the open-fork list.
