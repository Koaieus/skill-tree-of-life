# Archivist — charter

The design behind `.claude/agents/archivist.md` and the thin
`.claude/skills/archivist/SKILL.md` that spawns it. The files are derived
from this; change the wish here, then re-derive. See [README](README.md) for
the protocol. Sibling: `mise run transcripts`, the agent's toolbox, whose
docstring is the record-shape reference.

## What the archivist is for

A read-only scout over the project's own Claude Code transcripts — the
evidence base for every retrospective: *how do runs end, how often does a
drone blow its budget, which option does the owner pick on clean-vs-cheap
forks, where is the session that did X.* Three such scans already back
charter laws (warp's suite-cost figure from 248 transcripts, swarmify's
`askq` and `fallsout` corpus scans, the 2026-10-08 rule-trigger audit) and
each was set up from scratch: a Fable or Opus session spending its output
tokens explaining to a subagent where the transcripts are, what a record
looks like, that `ls` is aliased, that a file is megabytes. Owner,
2026-10-09: *"so that i don't need to explain every time 'use a subagent
haiku or sonnet depending on the level of analysis' nor fable/opus needing
to waste output tokens explaining the subagent on how to where to find the
transcripts etc what greps are ideal etc."*

So the agent file carries the layout once, the mise task carries the greps,
and the orchestrator's prompt shrinks to the question and the window.

## The cost model

**The orchestrator's output tokens are the expensive ones.** A paragraph of
"here is how transcripts work" costs more at the lead's tier than the whole
scan costs at Haiku's. Everything reusable lives in the agent file or the
task, never in the spawning prompt.

**Two tiers, chosen by the question, not by habit.** Counting, grepping and
finding a session is Haiku work: deterministic verbs with a regex. Labelling
an ending as "a ship report" vs "a pasted artifact", judging what recurs, or
quoting representatively needs Sonnet. The default is Haiku — the same
pin-the-cheap-model rule CLAUDE.md states for `Explore` — and the
description names the Sonnet trigger so the orchestrator sees it in the
agent listing without reading the file.

**A transcript read whole ends a context.** The directory is ~900 MB; one
session file is single-digit MB. Every verb streams; the agent is told,
twice, never to `cat` or `Read` one.

## Laws

1. **The prompt is the question plus a window.** The agent file owns the
   directory layout, the record shape, the launch-tag convention and the
   shell gotchas; an orchestrator that restates them is wasting its tier.
2. **Verbs before python.** `mise run transcripts -- list|grep|final|show|
   subagents` first; a scratchpad script only when a verb cannot express
   the question, stdlib and streaming.
3. **Haiku default, Sonnet by description.** `model: haiku` in the
   frontmatter; the description says when to pass `sonnet`. Never Opus or
   Fable: the archivist judges text, it does not design.
4. **Counts carry denominators and a window; quotes carry id8 and date.**
   Keyword matches are stated as directional. Exclusions are listed with
   counts.
5. **Subagent transcripts are opt-in.** They are most of the bytes and
   rarely the question; `--subagents` or an explicit ask includes them.
   Costs come from `mise run agent-cost`, never re-derived.
6. **Replies are short; samples go to the file.** Under ~500 words: the
   table or list asked for, recurring/varying bullets, exclusions.
7. **A scan that backs a law lands in `docs/corpus/`** — a dated report plus
   the labelled rows, rows holding id8 + date + labels + a short quote and
   never full texts. The swarmify corpus (`.claude/skills/swarmify/corpus/`)
   predates this home and stays where its charter cites it.
8. **Read-only on the transcripts and the repo**, except the corpus files
   and its scratchpad. It never edits a charter or a rule — it hands the
   evidence to the session that will.

## Incident corpus

| Date | What happened | Law |
|---|---|---|
| 2026-08-27 | Warp's suite-cost figure needed 248 transcripts scanned by a session that first had to discover the layout | 1, 2 |
| 2026-09-22 | Swarmify's two corpus scans each re-derived the first-user-record launch tag and the block-list text shape | 1, 7 |
| 2026-10-08 | Rule-trigger audit: a Sonnet trawl of 8 weeks, prompt explained Read/Write tool-call shape from scratch | 1, 3 |
| 2026-10-09 | The first scan with the new layout knowledge in the prompt (208 endings) still cost a 600-word brief; this charter moves that brief into the agent file | 1 |

## What the agent file must not contain

- Issue numbers, dates, this incident table, the owner's quote.
- Any skill's final-report format — the archivist measures endings, it does
  not define them (`docs/domain/session-report.md` does).
- Token-cost arithmetic — `agent-cost` owns it.

## Open follow-ups

- A `--since-session <id8>` window ("everything after that handoff") if
  retrospectives keep asking for it.
- Whether `final` should strip pasted artifacts (swarmify's "paste this to
  Designer Claude" briefs) — today the Sonnet labels them; a heuristic may
  do.
