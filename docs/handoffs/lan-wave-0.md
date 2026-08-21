# Handoff: LAN milestone, wave 0

Paste the block below to a fresh agent. Delete this file once wave 0 is merged.

---

You are picking up the `LAN 2026-08-31` milestone (hub #456) mid-flight. Read
`docs/FOCUS.md` first, then this whole prompt before touching anything.

## How much to trust what you read

This matters more than usual here, so calibrate before you start.

**Every issue body and almost every issue comment in this repo was written by an
agent.** They are working notes, not scripture. Several of them contradict each
other, and at least three contradict themselves between body and comments —
that is normal and expected, not a sign something is broken. When you hit a
contradiction, do **not** treat it as two equal claims to be argued between.
Resolve it by authority:

1. **The owner's own words, quoted in a comment and attributed as an owner
   call** — highest. These are decisions, and they are final unless the owner
   reverses them themselves.
2. **A later comment beats an earlier body.** Issue bodies rot; the decisions
   land in comments. `CLAUDE.md`'s "RTFC" rule exists for exactly this:
   `gh issue view <n>` prints the body, `gh issue view <n> --comments` prints
   only the comments, and reading an issue is *two* calls.
3. **A doc in `docs/domain/` or a rule in `.claude/rules/`** beats an issue
   body, because those are maintained.
4. **An agent-written issue body with no owner comment on it** — lowest. Treat
   its confident assertions as a previous agent's best guess. If it conflicts
   with code you can read, the code wins.

If a genuine conflict survives all four, **ask the owner**. Do not pick a side
and build on it, and do not write a new comment arguing with an old one. A
second confident agent-written opinion is how this becomes a screaming contest
instead of a record.

Known live examples you will probably hit:

- **#498's body is reversed by its own later comments in two places** (whether
  ownership storage moves into `NodeCombat`; whether `GraphMirror` gets reused
  or a BFS hand-rolled). The comments win. The body also carries a "parked
  behind the LAN milestone" comment that a later comment explicitly marks
  stale.
- **#457's earlier comment demanded the determinism contract cover combat and
  loot RNG.** An owner call of 2026-08-21 removed both from its scope. The
  later comment wins.
- **#507's body lists four open design forks.** All four were settled by an
  owner call the same day, in a comment. Implement the comment.
- **`docs/domain/attack-timeline.md`'s History section** documents its own
  earlier wrong answers. Read it as history, not as instruction.

## Owner decisions made 2026-08-21 that are NOT yet everywhere

These were settled in a session with the owner and written to the issues named.
They are recorded here too because they cut across several issues, and a stale
sentence somewhere else may still say otherwise.

- **The seed is for procgen and nothing else.** Owner: *"we don't care about
  that seed beyond the procgen using it, for now. possibly forever."* Combat
  reproducibility comes from a per-attack seed stamp (`8dc6f77`), not a
  run-level stream. Loot rolls stay host-only per #473. Consequence, and it is
  deliberate: **same seed reproduces the same map, not the same fights.**
- **A hit can crit — every hit, every mode, rolled at land time.** Not per
  swing, not per volley. The owner explicitly accepted that more hits means
  more crit chances. See #507.
- **Melee and ranged currently do not crit at all.** This is a gap in them, not
  a property of magic. Magic's real deviation is only the *extra*
  guaranteed-crit path (`SpellDef.crit_conditions`).
- **Win condition: last camp standing**, with blocker NPCs inert, and the
  condition itself pluggable. See #460.
- **Payload direction for multiplayer is outcome-down, not intent-down**, with
  the per-attack seed posted alongside so a peer can verify by re-resolving.
  Melee is the discriminator — its hit detection is a physics query
  (`blade_hit_scan.gd`) and cannot be replayed from intent alone. See #473 and
  `docs/domain/multiplayer-sync-model.md`.

## Your task: wave 0

Board hygiene and close-out. It is deliberately unglamorous and it unblocks the
next wave, so do it completely rather than partly.

Run `mise gh-project -- hygiene` first and again at the end.

1. **#494, #501, #503 are `In review`.** For each: read the issue *and* its
   comments, verify the work is actually complete against its acceptance list,
   run the suite, and merge + close it. If one is not actually done, say so and
   report what remains — do not close it to make the column tidy.
2. **#300 is `In progress` with all three children closed.** Hygiene flags it.
   Either close it, or file what actually remains as a child. Its body is a
   real remaining scope question — read it before deciding.
3. **#381 is `Ready` with no milestone**, so `roadmap` cannot see it. Give it
   one or move it out of `Ready`.

**Why wave 0 comes first:** #501 and #503 own `attack/spell/spell_resolver.gd`
and the ranged plan. #507 (crits, wave 2) rewrites the crit roller in
`spell_resolver.gd` and calls it from melee and ranged. Landing #507 on top of
unmerged work in those files is the one avoidable conflict in this plan.

## Ground rules

- Run `mise run test` before you claim anything is done. Current baseline is
  **1736 passing, 1 pending** (`#362`, a known run-order test). A parse error
  makes GUT skip a whole file while still reporting green — check the `Scripts`
  and `Tests` totals, per `.claude/rules/testing.md`.
- Commit as you go. Never pass `gh --body` with backticks; heredoc to the
  scratchpad and use `--body-file`.
- Do not pull anything outside wave 0. If you find something, file it and
  report it.
- Report what you merged, what you did not and why, and the final hygiene
  output.
