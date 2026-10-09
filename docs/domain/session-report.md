# The session report — how a skill run ends

Every user-facing skill run (`warp`, `swarm`, `relay`, `relief`, `swarmify`;
`whip` renders its own file) ends with **one message in this shape**. Same
sections, same order, every section present even when it says `none`, so the
owner — usually on a phone — can ingest a run without re-reading it, and a
later scan (`mise run transcripts -- final --skill <s>`) can diff runs.

Measured before this existed (208 last-long-messages — in most sessions a
post-report exchange rather than the report itself, so directional —
2026-08-10 → 2026-10-09,
[corpus scan](../corpus/2026-10-09-skill-endings.md)): endings were 130–260
words of prose with bold-lead bullets, 5 % had headers, 12 % a table, and
the one thing nearly every ending carried was *what landed + SHA + test
verdict*. What was **not** done appeared in ~40 %, follow-ups in 30 %, and
questions for the owner in under 10 % — the three things the owner most
needs, and the three least often present.

## The shape

```
**<skill> <issues> · landed <k>/<m> · `<base>..<tip>` · suite <verdict> · ~<N>k ctx**

**Landed**
| # · sha | what | tests |
|---|---|---|
| #1234 · `abc1234` | one clause | dir 41/41 |

**Not done** — none | one line each: what was in scope and is not on master, and why

**Follow-ups**
| what | disposition |
|---|---|
| one clause | fixed now · `abc1235` |
| one clause | sub `drone-x` did it · `abc1236` |
| one clause | filed #1240 — needs an owner design call |
| one clause | dropped — cosmetic, not worth an issue |

**Needs the owner** — none | a question or approval, one line each

**Touched** — none | docs/rules/charters edited, feedback posts, board moves

**Cost** — ~<N>k ctx · <n> tool calls · <k> subagents (<model> × n)
```

Prose outside the sections: three sentences at most, and never a diff. The
headline line alone must let the owner decide whether to read on.

Tables are read on a phone: three or four columns, the identifier and its
SHA share the first cell. A cell cannot hold a newline; `<br>` renders on
GitHub and in the claude.ai app but not reliably in a terminal, so ` · ` is
the separator and `<br>` only when the message is posted to GitHub.

### Per-skill columns

The `Landed` table carries what that skill lands:

| skill | `Landed` columns |
|---|---|
| warp, swarm, relay, relief | `# · sha` · `what` · `tests` |
| swarmify | `#` · `now in` · `settled` · `left` — the lane after the pass (`Ready` is the goal), the decision direction or fork settled in one clause, and what is still open: stubs, children created, a fork the owner kept |
| whip | its renderer's file (`docs/handoffs/whip-report-<date>.md`): `Landed / Back to Needs design / Still Ready / … / Filed since start / Needs the owner / Incidents / Cost` — the same vocabulary, more lanes |

A `relief` ending adds one line under `Needs the owner` when it hands off:
`next relief: <what it takes>`.

A launch does not always name issues — a swarmify or warp is often asked for
by content ("the bruiser retarget bug"). `Landed` then lists the issues the
run created or resolved for that content, and the headline says `<skill>
<content, five words>` instead of numbers.

## The addendum — the report is rarely the last message

The owner usually keeps going after the report: a question on a loose end,
"do the second follow-up too", "push". Measured on the same window, that
happened after most swarm, warp and swarmify runs. So the report is rendered
when the *work* ends, and every later closing message is an **addendum**:
the same sections, only the ones that changed, under one bold `Addendum`
line — a `Landed` row for the follow-up that got done, a `Follow-ups` row
whose disposition moved, `Not done` cleared. Never a second full report, and
never prose that forgets the sections: the last message of a session must
still be ingestible on its own, and `mise run transcripts -- final` reads
exactly that message (`--tail 3` shows the report before it).

## The follow-up rule

The `Follow-ups` table exists to stop the backlog rot: a 20-issue milestone
ground out over five weeks grew the `Needs design` lane past 80, mostly from
small optional work filed "for later" by sessions that could have done it on
the spot. So every loose end gets a **disposition**, chosen in this order,
and the table shows the choice:

1. **fixed now** — the default for anything under ~20 minutes inside the
   run's fence. Cite the SHA.
2. **sub did it** — delegated to a subagent this session (an `Explore` for a
   lookup, a `drone` for a fenced fix). Cite the SHA.
3. **filed #n — <why not now>** — only with a reason from this list: *needs
   an owner design call*, *outside this run's fence and more than ~20
   minutes*, *blocked on another issue*. A filed issue names its milestone,
   or it is `Backlog`, which the owner reads as "basically never" — say so
   in the reason if that is what you mean.
4. **dropped — <why>** — honest and cheap: cosmetic, speculative, or nobody
   asked. A dropped item costs one line here and nothing later.

`Not done` is different from a follow-up: it is scope the run **promised**
and did not deliver, and it is never silent.

## Where this binds

Each skill's closing step points here with one line; the law behind it is in
the skill's charter (`docs/charters/<skill>.md`). The `drone` agent's
six-line report (`BRANCH/FILES/TESTS/DID/COST/NOTES`) is the subagent-side
sibling and keeps its own shape — this format is what the orchestrator
renders *from* those.
