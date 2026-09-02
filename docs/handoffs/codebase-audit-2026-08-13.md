# Handoff — codebase audit 2026-08-13/14

**The triage doc this file used to point at (`audit-2026-08-13/TRIAGE.md`) was
never committed.** What survives is `00-brief.md` (the original fan-out prompt)
plus the 8 raw slice reports in `audit-2026-08-13/`: `audit-attack.md`,
`audit-devtools.md`, `audit-graph-core.md`, `audit-procgen.md`,
`audit-skill-node.md`, `audit-systems.md`, `audit-test-infra.md`,
`audit-vfx.md`. This file keeps only what does not belong in the triage: the
fan-out budget post-mortem, and the pointer to the raw reports.

Written against `7f03e5e`. Master is green-modulo-6 (the same 6 failures that
were standing before this work; see TRIAGE §A2).

---

## State

- **8 of 11 slice reports** sit in `audit-2026-08-13/`, ~167 findings, each
  `SEVERITY | file:line | title` / **Defect** / **Breaks** / **Fix**. They are
  dense and already filtered for style-only noise. **You should not need to read
  them** — TRIAGE.md consolidates all 167 into apply/ask/file/open buckets with
  citations back.
- **Three slices were never audited** (budget died): `stats_system/` +
  `skill_node/addons/`, `ui/tooltip_fan/` + `ui/spell_tooltip/`, and `ui/hud/`
  + `ui/gauges/`. The last carries an unfulfilled owner ask — an inventory of
  which HUD elements use real emissive vs. faked pre-bloom glow, `pool_gauge` /
  `composite_bar_gauge` / `capacity_pip` named directly. Prompts are
  reconstructable from `00-brief.md`; the vfx report's §A table is the model to
  copy. See TRIAGE §D1.
- **Landed 2026-08-14:** all three of the owner's reported render smells, plus a
  fourth live bug they reported that session. `895fd55` `2945015` `aa31522`
  `07868a5` `7f03e5e`. Details and verification evidence are in TRIAGE §A0/§A1.
- **Open forks are now issues**, not prose here: **#417** (Reverberator spread
  rule), **#418** (should an edge leaving vision fade to zero), **#419**
  (tint_mix swing). TRIAGE §B still lists the ones nobody has been asked about.

---

## Fan-out budget rules — the part worth keeping

The 11-wide all-opus audit consumed **0% → 115% of a 5-hour window in under 10
minutes.** Correct the instinct before repeating it: the work was *not* 20% done
at cutoff. All 8 surviving reports are complete, 20–25 ranked findings each, no
`## Incomplete` sections. The true cost was ~115–130% of one window, not the
400–500% it felt like.

Root causes, in order of size:

1. **Subagents inherited `advisor`.** It forwards the calling agent's *entire
   transcript* to another opus. For an auditor that transcript is every file it
   read — so an auditor that read 4000 lines and called advisor twice paid for
   that corpus three times. The orchestrator already *is* the subagent's
   advisor. **Every subagent prompt must forbid it explicitly**, because the
   tool description tells them to call it before substantive work and again when
   done.
2. **Monotonic context re-send.** An agent's context only grows as it reads, and
   every tool call re-sends all of it. 40 calls averaging 40k ≈ 1.6M input
   tokens for *one* agent, before any advisor call. × 11 × opus rates.
3. **"Read every `.gd` in scope in full" was the wrong instruction** — it
   maximises exactly the quantity that gets re-sent every turn. Scope by symptom
   (churn, size, the named hypotheses) and read selectively.
4. **All-opus at 11-wide was the orchestrator's call and it was wrong.** The
   owner's concern — a Sonnet-written module graded by Sonnet — is legitimate;
   the answer is *fewer opus units*, not eleven.

Rules for any future fan-out here:

- Forbid `advisor` in every subagent prompt, explicitly.
- Ceiling **~6 opus subagents per 5-hour window**, or ~11 if advisor is off
  *and* reading is scoped rather than exhaustive.
- Reports go to **disk**, never into the orchestrator's context as return
  values. This worked and should be kept regardless of budget.
- Commit salvaged artifacts to the **repo**, not the scratchpad — the scratchpad
  is session-scoped and evaporates.
- With a 1M context, the orchestrator's own context is the *cheap* resource and
  subagent spend is the scarce one. **Prefer the orchestrator reading and fixing
  sequentially over another fan-out** — that is how the 2026-08-14 batch was
  done, and it cost a fraction of one window.
- Two haiku subagents dispatched on 2026-08-14 both completed their file edits
  but **returned no report to the orchestrator**. Work was verifiable from the
  diff, but do not assume a report will arrive — spot-check the diff yourself,
  and one of them silently ignored an explicit "keep this comment" instruction.
- "You've hit your monthly spend limit" in this account means the ordinary token
  limit; the monthly spend limit is $0.

---

## Housekeeping

- A pristine `HEAD` worktree may still exist at `<scratchpad>/pristine` —
  `git worktree remove` it when convenient. (Scratchpads are session-scoped, so
  it has probably already evaporated.)
- The owner's WIP is still uncommitted in `attack/spell/defs/bruiser.tres`
  (which also gained an unused `rank_pass.gd` ext_resource — relevant to #417),
  `attack/spell/defs/reverberator.tres`, and `scenes/dev_sandbox.tscn`. The
  dev_sandbox self-loop on `Down_Out` is the repro case for the glow fix and was
  used to verify it; leave it until #417 settles.

**Delete this file and `audit-2026-08-13/` once TRIAGE §C is filed as issues and
§A is applied.** TRIAGE.md tracks that state; nothing here is a decision's only
home.
