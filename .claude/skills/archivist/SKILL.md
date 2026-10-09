---
name: archivist
description: Ask the project's own session transcripts a question — "how do swarm runs end", "how often did a drone blow its budget this month", "find the session that changed X" — by spawning the `archivist` agent at the right tier and, for a scan that will back a law or a retrospective, filing its evidence under docs/corpus/. Use when the user says "archivist", "scour the transcripts", "let haiku/sonnet trawl the logs", "what did past sessions do about…", or any retrospective that needs counts or quotes from earlier runs.
---

# Archivist — ask the transcripts

Design and laws: `docs/charters/archivist.md`. One spawn, one reply; you
never read a transcript yourself.

1. **Pick the tier from the question.** Counting, grepping, finding a
   session → the agent's default (Haiku). Labelling, classifying, judging
   what recurs, quoting representatively → `model: "sonnet"`. Never higher.
2. **Spawn with the question and the window, nothing else.**
   `Agent(subagent_type: "archivist", model: …, prompt: "<question>. Window:
   <--days N | since YYYY-MM-DD>. <scan | answer only>.")` — the agent knows
   where the transcripts are, how to read them and which `mise run
   transcripts` verb fits; restating any of that wastes your tier. Say
   `scan` when the result should back a charter law, a rule or a
   retrospective: it then writes `docs/corpus/<date>-<slug>.md` + rows.
   Say `answer only` for a one-off question.
3. **Relay the reply in the session-report shape** (`docs/domain/session-report.md`):
   the table or list, what recurs, exclusions; the corpus path under
   `Touched` when one was written. Ratios are directional, quotes exact —
   keep the agent's caveats.
4. **Act on it where you are.** A finding that changes a charter is folded
   in by *this* session (charter first, then the derived file) or posted
   with `mise run feedback -- post <charter> probe <file>`; never left in
   the transcript it came from.
