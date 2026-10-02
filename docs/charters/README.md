# Charters

A **charter** is the design doc behind a skill (`.claude/skills/<name>/SKILL.md`)
or an agent (`.claude/agents/<name>.md`). The instruction file is what a fresh
agent *reads and obeys*; the charter is *why it says that* — the intentions,
the laws it must encode, the cost model, the incident corpus that produced each
law, and what the file must **not** contain.

The split exists because the two audiences want opposite things. A fresh
subagent needs instructions and nothing else — every issue number, "reasoning
behind", or war story in its instruction file is context it pays for on every
turn and cannot act on. The owner changing their mind needs exactly that
history, or the next rewrite re-learns it.

## Protocol

- **Changing a wish → edit the charter, then re-derive the instruction file
  from it** — a full rewrite if the laws moved, a patch if one line did. Never
  patch the instruction file with a new lesson and leave the charter stale;
  the charter is the source, the file is the build.
- **The instruction file cites the charter once** (a one-line pointer, so a
  reader who wants the why can find it) and otherwise **names no issue
  numbers, no incidents, no dates, no reasoning-behind.** If a line in the
  file needs justifying, the justification goes in the charter next to the law.
- **The charter lists the laws numbered**, so a diff of the charter reads as a
  diff of the contract, and the instruction file can be checked against it
  law by law.
- Charters live here, not next to the file: agents are single `.md` files and
  *every* `.md` in `.claude/agents/` is parsed as an agent definition, so a
  companion doc cannot sit there; skills could hold one in their directory,
  but one home for both keeps the convention uniform.

Charters so far: [drone](drone.md), [swarmify](swarmify.md), [swarm](swarm.md), [sage](sage.md), [adr](adr.md), [warp](warp.md), [relay](relay.md), [relief](relief.md), [clerk](clerk.md), [whip](whip.md).

## Feedback boards

A charter's incident corpus used to grow only when someone edited the
charter — a commit on the shared master, impossible for a `--bg` session
mid-run and forgotten by everyone else. So **each charter gets one GitHub
Discussion as its board**, in the `Skill feedback` category, titled
`<charter> — skill feedback board` and created by the first post. Skills
point at `mise run feedback`, never at a board number; one unscoped
breadcrule (`.claude/rules/skill-feedback.md`) carries the "where to post"
line for every skill.

**When to post** — any session that, while *using* the skill, learns
something the skill or charter does not say: a gotcha, a friction, a probe
result, a law candidate, an autopsy. Post it where you are, when you learn
it; a finding that waits for a handoff is usually lost. Nothing is too
small; a line that turns out to be noise is rejected in the fold, at no cost.

**The post** — write the finding to a file, then
`mise run feedback -- post <charter> <kind> <file>` with the kind one of
`gotcha | friction | probe | law-candidate | autopsy`. The verb prepends the
header line `**<YYYY-MM-DD> · <kind> · session <id8>**` (id8 = the first
eight characters of `$CLAUDE_CODE_SESSION_ID`) — do not type it; the file is
just the finding, with what was observed kept apart from what is proposed.

**The fold pass** — whoever revises the charter (a rewrite, a `/handoff`
sweep, a dedicated pass) works from
`mise run feedback -- unanswered [<charter>]`, folds each post into the
charter — a law, a corpus row, a fork, a follow-up — and from there into the
derived instruction file, commits, then answers with
`mise run feedback -- reply <comment-id> <file>`, the file reading
`folded in <sha>` or `rejected: <why>`. **Unanswered = unprocessed.** The
charter keeps a short *Fold digest* section (date · kind → what it became),
so a repo grep still finds the substance without the board.

Checklist skills (`manage-stats`) have no charter: a checklist carries no
laws and no incident corpus, and its *why* is the rule it points at.
