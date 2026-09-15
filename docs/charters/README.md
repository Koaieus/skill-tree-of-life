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

Charters so far: [drone](drone.md), [swarmify](swarmify.md), [swarm](swarm.md).
