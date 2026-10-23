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
  from it — through the `charter` skill** (`/charter <name>`, charter
  [charter.md](charter.md)): the charter is edited, one advisor pass reads
  it, and a fresh Fable subagent briefed with nothing but the charter path
  writes the whole file. Never patch the instruction file with a new lesson
  and leave the charter stale; the charter is the source, the file is the
  build.
- **The instruction file cites the charter once** (a one-line pointer, so a
  reader who wants the why can find it) and otherwise **names no issue
  numbers, no incidents, no dates, no reasoning-behind.** If a line in the
  file needs justifying, the justification goes in the charter next to the law.
- **The charter lists the laws numbered**, so a diff of the charter reads as a
  diff of the contract, and the instruction file can be checked against it
  law by law. Numbers are stable: a law is never renumbered or deleted —
  it reads `retired — <why>` or `superseded by law <M>`, and new laws
  append.
- **A law lives in one charter.** The charter whose skill or agent does
  the thing owns it; another charter that relies on it lists it as
  **foreign** in its `## Foreign laws` section —
  `- [<owner>](<owner>.md) law <N> — <what this skill does with it>` —
  cites it in that form, and keeps only its own side. A pass that changes,
  supersedes or retires a law greps `docs/charters/` for
  `(<name>.md) law`, reads the hits for that number, and brings every
  reader along in the same commit ([charter.md](charter.md) laws 13–14). The builder may read each foreign
  law its charter lists.
- Charters live here, not next to the file: agents are single `.md` files and
  *every* `.md` in `.claude/agents/` is parsed as an agent definition, so a
  companion doc cannot sit there; skills could hold one in their directory,
  but one home for both keeps the convention uniform.

Charters so far: [charter](charter.md) (the skill that revises every other),
[drone](drone.md), [swarmify](swarmify.md), [spec](spec.md), [swarm](swarm.md), [sage](sage.md), [adr](adr.md), [warp](warp.md), [relay](relay.md), [relief](relief.md), [clerk](clerk.md), [whip](whip.md) (retired; corpus only), [swarm-train](swarm-train.md), [archivist](archivist.md), [triage](triage.md).

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
To move a post that already carries its header from one board to another,
`mise run feedback -- post --verbatim <charter> <file>` sends the file
unchanged — no header, no kind.

**The fold pass** is the `charter` skill's board input: a revision of a
charter (a wish, a `/handoff` sweep, a dedicated pass) runs `/charter
<name>`, which works from `mise run feedback -- unanswered [<charter>]`,
folds each post into the charter — a law, a corpus row, a fork, a
follow-up — derives the instruction file, commits, then answers every post
with `mise run feedback -- reply --resolve <comment-id> <file>`, the file
reading `folded in <sha>` or `rejected: <why>` — as a work order to one
Haiku `clerk` ([clerk](clerk.md) law 11), since the answers are pure tool calls.
`--resolve` also minimizes the post as *resolved*, which folds its reply
away with it: the board stays open and reads as its unprocessed posts.
**Unanswered = unprocessed** — the reply is the contract, the resolve is
cosmetic. The
charter keeps a short *Fold digest* section (date · kind → what it became),
so a repo grep still finds the substance without the board.

A skill or agent with no charter yet (`handoff`, `manage-stats`, `pickup`)
gets its first one the first time `/charter` is asked to change it, written
from the file's own imperatives ([charter.md](charter.md) law 9). The
`adr-librarian` agent is covered by the `adr` charter, `swarm-lead` by
`swarm-train`.
