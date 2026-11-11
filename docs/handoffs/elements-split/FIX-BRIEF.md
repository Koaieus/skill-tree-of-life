# Fix-round brief — elements split issues (#1716)

You are one writer in the fix round over the elements-split issues. The GitHub issues #1793-#1816 are the source of truth; the body files that used to sit in this folder are gone and any copy in git history is stale. Your prompt names your issue, its unit name and your task list.

## Workflow
1. Pull your body: `gh issue view <n> --json body -q .body > <scratch file>` (your prompt names the scratch path). Edit that file.
2. Push it: `gh issue edit <n> --body-file <scratch file>`. Read it back: `gh issue view <n> --json body -q .body | diff - <scratch file>` must print nothing (a trailing-newline difference is fine).
3. Edit ONLY your issue's body. Do not change its title, labels, status, relations or comments, and never edit another issue. Read a sibling's body with `gh issue view <m> --json body -q .body`.
4. Edit no repo file and run no git command that changes state (no add, commit, stash, checkout, restore). Other writers run in parallel in this checkout.

## Read
- `docs/handoffs/elements-split/REVIEW-2.md`: findings R1-R23 by body, S1-S19 for the smaller bodies. Line numbers point into the bodies as re-posted, where placeholders like `{resolver}` became `#1798`; find each passage by its quoted text. R19-R23 are answered (STATE batches 1-2; ADRs 0086, 0087).
- `docs/handoffs/elements-split/REVIEW-rulings.md`: the ownership rulings, still in force.
- `docs/handoffs/elements-split/DOC-REVIEW.md`: a review of `docs/design/elements.md` against the owner's answers; read the findings on the passages your issue cites.
- `docs/handoffs/elements-split/STATE.md` lines 70-147: owner batches 1-7 and the 02:43 input, verbatim. Read them to understand the calls; what is settled is in the doc and the ADRs. Lines 108-114: lead readings that stay tentative.
- The ADRs your task names (`docs/adr/0083*` through `docs/adr/0091*`), and in `docs/design/elements.md` only the sections your issue cites (`grep -n '^#' docs/design/elements.md`).
- `.claude/skills/spec/SKILL.md`: the body format. Your body keeps it.

## Rules
- Change content only. Do NOT touch `elements.md` line ranges or drift stamps, even where they are now wrong; a restamp pass follows.
- Quote the owner verbatim, only from `docs/design/elements.md` or an ADR, with the date it gives. A quote that lives only in a handoff file or another design doc is not quotable here: drop the quote marks, state the rule, cite the doc section or ADR.
- Cite a settled call by the ADR that carries it, with its §. ADRs 0086-0091 now carry what bodies cited as "the doc paragraph, no ADR yet". A call no ADR carries: cite the `elements.md` section.
- Pass and lead readings stay marked "(tentative, not the owner's)": STATE lines 108-114, and whatever the doc marks tentative (`grep -n tentative docs/design/elements.md`). ADR 0087 lists an absorbed Heat copy that thaws and walks on as not decided: never cite 0087 for it.
- One decision has one owner. Point at the owning issue as `#<n>` (placeholder → number map: `NUMBERS.md`). Blocked-by and Blocks lines follow `ORDER.md`.
- Every acceptance item is testable by a cold implementer with only the body and its reading list: name the observable, the numbers, the test seam.
- What the doc leaves open stays open: a knob with its tentative default, or a NOTES line. Do not decide it; report it.
- No save migration and no save-version item anywhere (owner: no saves exist). No "Closes" for #1660, #1695, #1696, #1765.

## The shared arithmetic (state it in these terms where your unit tests it)
- ADR 0086: every landing is a whole hit. The go-off share defaults to 1. The hit node takes 1 + 1 per channel that goes off from it; a node one channel reaches takes 1. With the dedupe switch off, a node two channels reach takes 2 landings; with it on, one landing at share × channels. The dedupe never merges the hit node. A cast's shape alone is not a channel for the seed. The centre copy carries the go-off's own damage.
- ADR 0090 §1: a break of Frozen counts as 2 channels (a knob or const, default 2), plus the burst.
- ADR 0087: Heat / Cold / Charge land at the tip of every arrival, absorbed or not, once per node per hit; Frozen's admit gates damage and aspect riders only. Transferred Charge commits with the spend, before the admit. An arrival that breaks the ice walks on.
- ADR 0091: a beat lands in generations (the beat's own arrivals, then each go-off's copies one generation later). Within a generation every arrival lands its terrain riders, then the node is read once over all its arrivals (primed state, Frozen, whether it breaks), then paths leave. If any arrival breaks the ice it shatters once, one burst, every path through walks on; only the breakers take the 2 extra landings. The damage breaker reads each arrival's raw amount (stamped, crit included, × its load multiplier; armor plays no part) alone. Tentative: the shatter is Ice's go-off read in stage one; a multi-hop arc advances one hop per generation.
- Every blade contact lands (ADR 0088 §5 for a breaking touch, 0090 §2 for a light vertex); weight decides only the break.

## The 02:43 fork: the NOTE (added by ele 2's overnight lead)
The owner reopened the damage breaker at 02:43 (STATE, "Owner input, 2026-11-11 02:43"; `docs/design/elements.md` § Open, first bullet). ADR 0091 is NOT edited and your body follows it as it stands. If your body cites the flat damage breaker or the break threshold (the 10% max-HP read, "under the break threshold", "clears the threshold", the raw amount as thrown), before or after your edit, its first lines are this NOTE, verbatim, followed by a blank line (skip if it is already there):

> **NOTE (2026-11-11, open fork, the owner's call pending):** the damage breaker is reopened. The owner (02:43): the break must read the number the player sees, and ADR 0091 §3's raw amount as thrown does not (the floater shows `max(min_damage_taken, raw − armor)` after the hit's own aspect riders land). Three shapes, none picked: crit and blade only, which drops the flat breaker (the lead's tentative lean); the arrival's own aspect riders land before the read; Frozen takes damage unmitigated (`docs/design/elements.md` § Open, first bullet). This body follows ADR 0091 as it stands. Every line that cites the flat damage breaker or the break threshold may change with the ruling. The issue stays out of Ready until the fork is settled.

Do not choose a shape, and do not rewrite the breaker lines toward one. Where a line's meaning would change under the lead's lean, leave the line as ADR 0091 has it; the NOTE covers it. Report "NOTE: added / already there / not needed".

## Final message
Under 200 words: issue edited and read back clean (yes / no); findings fixed, by number; acceptance items added, moved or whose numbers changed; anything you could not fix and why; any contradiction with another issue; each tentative reading you carried, one line. Nothing else.
