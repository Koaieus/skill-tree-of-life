---
name: charter
description: >-
  revise one or more skill or agent files through their charters — edit each
  charter (a wish, or fold its feedback board with
  `mise run feedback -- unanswered <charter>`), keep foreign laws in sync
  across charters, one advisor pass for the whole pass, one fresh Fable (or,
  for a small charter, Opus) subagent per touched charter re-derives its files
  from the charter alone — or, for a pass that moves only a few laws, an Opus
  subagent patches just those laws' lines — rules-hygiene, one commit, the
  folded posts answered through a Haiku clerk. Use when the user says "revise a skill", "update the
  charter", "fold the feedback board", "re-derive <skill>", "change the <agent>
  agent", "/charter <name> [<name>…]", or when a session is about to patch a
  `SKILL.md` or an agent file directly.
---

# /charter <name> [<name>…]

Why each step reads as it does: `docs/charters/charter.md`.

A pass takes one input — a wish (the owner's words, or a lesson from a
session) and/or a charter's feedback board — and produces one commit holding
every named charter and every file derived from it, plus the board's posts
answered. It writes no design. Several names may be given; each gets its own
charter edit and its own builder, the advisor reads them all once, and one
commit holds them all.

## 1. One door

Every change to a `.claude/skills/<name>/SKILL.md` or a
`.claude/agents/<name>.md` goes through these steps: the charter changes
first, the file is derived from it. If you are about to patch an instruction
file directly, stop and run this skill instead. A diff that touches an
instruction file and not its charter is the bug. This skill's own charter is
changed the same way — through this skill.

## 2. Find the charter; write a first one if there is none

For each name, the charter is the one whose first paragraph names the file —
usually `docs/charters/<name>.md`, but an agent may be built by a skill's
charter, so check the index in `docs/charters/README.md` before concluding
there is none.

A file with no charter gets its first one in this pass, before anything else:
write `docs/charters/<name>.md` from the file's own imperatives — each
must/never becomes a numbered law with the why the file or the rule it points
at gives — plus *What it is for*, a cost model, *Frontmatter*, *Revisit when*
and an empty corpus; add it to the README index; then continue with the wish.
Never patch a charterless file.

## 3. Read the board, for every charter named

Run `mise run feedback -- unanswered <charter>` for each named charter, every
pass, before anything is derived — a wish never lands on top of an unfolded
post. Keep each post's comment id for step 12.

If `unanswered` fails (Discussions not set up, the GraphQL hour spent), the
pass continues on the wish and the failure goes under `Not done` in the
report.

## 4. Check the charter carries what the build needs

Each charter's first paragraph lists the file or files it builds (a charter
may build more than one — a skill and its agent). It carries a *Frontmatter*
section — the `description` with its trigger phrases, and for an agent the
`model` and `tools` — or states them in its laws. Anything missing is added
now, lifted from the current file.

Then read the current derived file once, against the laws: every imperative
line — each must and never, each command, brief and order — must have its
law. One that has none is lifted into the charter at the law it belongs to.
This read, the frontmatter lift above, and step 2's first charter are the
only times a current file is read into a charter.

## 5. Fold the wish and the board into the charter

A wish — the owner's words verbatim and dated, or a session's lesson —
becomes one of: a numbered law (with its why), a row in the incident corpus,
an entry under *Revisit when*, or a fork noted there as open.

Each board post becomes one of those or a rejection, and gets a row in the
charter's *Fold digest* (date · kind → what it became). Record its verdict
text now — `folded in <sha>: <law or digest row>` or `rejected: <why>` — for
step 12. A post that belongs to another charter is moved with
`mise run feedback -- post --verbatim <other> <file>`, not folded here.

Law numbers are stable: never renumber or delete a law — it stays, reading
`retired — <why>` or `superseded by law <M>`, and new laws append.

## 6. Keep foreign laws in sync

A law lives in the one charter whose skill or agent does the thing. A charter
that relies on another's law does not restate it as a numbered law of its
own: it lists it in its `## Foreign laws` section, one line each, exactly as
`- [<owner>](<owner>.md) law <N> — <what this skill does with it>`, and its
own laws cite it in that same `[<owner>](<owner>.md) law <N>` form, keeping
only its own side — what it hands over, what it expects back. A law found
duplicated across two charters is merged into the one that does the thing,
the other's copy turned into its foreign line, in this pass.

For each law this pass changed, superseded, retired or renumbered: grep
`docs/charters/` for `(<name>.md) law` and read the hits for that number (a
citation may name a range, `laws 13–14`); also grep for the charter's bare
name near `law`, for older references. Update each reader's foreign line and
citing laws in this pass. A reader whose derived file states what the law
changed joins the pass as a touched charter (it gets its own builder in step
8).

## 7. One advisor pass

After every named charter is edited and before anything is derived, call
`advisor` once — one call however many charters the pass names. Apply each
point to its charter or decline it; name the declined points in the commit
body. One pass, not a loop.

## 8. Derive: one fresh subagent per touched charter

For each charter the pass edited, spawn one `general-purpose` subagent with
a `name` (step 9 sends gaps back to it) and `run_in_background: false`. It
writes every file that charter builds — a skill and its agent in one
context. A multi-charter pass spawns all its builders in one message so they
run side by side.

Tier: `model: "fable"`. A *small* charter — under about 200 lines, building
one file of under about 150 — may take `model: "opus"`; that is your call,
named in the report.

The brief is the text below, verbatim, with only the paths and the
foreign-law lines filled — no summary of what changed, no diff, no paste of
the old file. Use the bracketed alternative for a charter that builds more
than one file, and the agent clause when a target is an agent:

```
Repo: <absolute repo path> (a shared checkout; do not commit, do not run
git write commands).

Write the file `<absolute target path>` [or: the files `<path 1>` and
`<path 2>`] (create the directory if it does not exist) from the charter
at `<absolute charter path>`, following the protocol in
`<absolute README path>`.

Read the charter with `sed -n 'a,bp'` in ranges of about 250 lines, from
your first call (a whole-file Read of a long file is refused), and the
README with one Read. You may also read, and only these: the text of each
foreign law below, from its owning charter, with a `sed -n` range or
`grep -n -A` on its number —
<the charter's *Foreign laws* lines, or "none">
— and you may spawn at most ONE `Explore` subagent with `model: "sonnet"`,
its prompt ending "Answer in under 5k tokens.", for context the charter
does not carry (what a named tool or file is for, how a sibling skill is
shaped) — never about the target file itself or an earlier version of
it. Open no other file — not the current version of the target, not any
other skill or agent file. Run no command but those reads, a `mkdir`
and your writes. Do not call advisor. Budget: about eight tool calls.

A string the file must state exactly — a command line, a verb, a path, a
brief, an order or a report shape — that the charter does not give is
never invented. If your Explore found it verbatim, use it and list
`grounded: law N — <string> — <source>` in your handback; otherwise write
`<gap: law N — what is missing>` in its place and list it. The lead
closes gaps in the charter and sends you the lines to re-read.

Of a foreign law, the file states only what this skill does with it, never
the owning skill's side.

The file's frontmatter is `name:` and `description:` as the charter's
*Frontmatter* section states them. [Agent: and `model:` and `tools:` as
the charter states them.] The body is steps only — the pipeline a fresh
session follows, with the exact briefs and orders it uses, taken from the
charter — with one one-line pointer to the charter and nothing the
charter's *What the skill file must not contain* section forbids (no
dates, issue numbers, owner quotes, or reasoning-behind). Every numbered
law in the charter must be recognisable as a step or a line in the file.

When done, report each path, the gap list (or "no gaps") and the
grounded list (or "none") via SubagentHandback.
```

### A small pass patches instead

A charter whose file exists is *patched*, not rebuilt, when the pass moved
about three laws or fewer (changed, added, retired) and changed no existing
brief, order, report shape or step order — a new law with a new brief of its
own is still additive. Everything else is a full rebuild as above: a first
charter (step 2), a step-4 first read that lifted anything, a structural
change, a patch that fails the step-9 check, or the owner asking for one.

The patch builder is one fresh subagent per charter, as above — a `name`,
`run_in_background: false`, the same foreign-law reads and the one capped
Explore — but `model: "opus"` (Fable when a moved law is subtle; your call)
and the brief below, verbatim, listing the moved laws by number and nothing
more — no summary of the change, no diff:

```
Repo: <absolute repo path> (a shared checkout; do not commit, do not run
git write commands).

Patch the file `<absolute target path>` [or: the files `<path 1>` and
`<path 2>`] so it carries laws <N, M, …> of the charter at
`<absolute charter path>` as they now read, following the protocol in
`<absolute README path>`.

Read the charter with `sed -n 'a,bp'` in ranges of about 250 lines, from
your first call (a whole-file Read of a long file is refused), the README
with one Read, and the current target file (`sed -n` ranges past 400
lines). You may also read, and only
these: the text of each foreign law below, from its owning charter, with
a `sed -n` range or `grep -n -A` on its number —
<the charter's *Foreign laws* lines, or "none">
— and you may spawn at most ONE `Explore` subagent with `model: "sonnet"`,
its prompt ending "Answer in under 5k tokens.", for context the charter
does not carry — never about the target file. Open no other file. Run no
command but those reads and your edits. Do not call advisor. Budget:
about eight tool calls.

Edit only the lines that carry the listed laws — add, change or remove
them — and the frontmatter if the charter's *Frontmatter* section no
longer matches it. Leave every other line byte for byte. A listed law
whose change reaches lines that carry an unlisted law is not patched:
say so in your handback and stop.

A string the file must state exactly that the charter does not give is
never invented. If your Explore found it verbatim, use it and list
`grounded: law N — <string> — <source>`; otherwise write
`<gap: law N — what is missing>` in its place and list it. Nothing the
charter's *What the skill file must not contain* section forbids.

When done, report each path, the laws patched, the gap list (or "no
gaps") and the grounded list (or "none") via SubagentHandback.
```

For a patch, step 9's law-by-law check runs on the moved laws and its
mechanical greps on the whole file; step 10's diff read confirms the diff
stays inside the moved laws. The report names which mode — rebuild or patch
— each charter took.

## 9. Check the build law by law; fix gaps through the builder

For each derived file:

- Every numbered law of the charter has its line in the file.
- The file cites the charter exactly once.
- It holds no date, no issue number, no owner quote, no "was:". The
  mechanical half: grep the file for `20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]`
  and `#[0-9]{3,}` — only template placeholders may match. A quote or a
  reasoning-behind is caught by the law-by-law read.
- Grep for `<gap: law` — every hit (a template placeholder aside) is a gap
  the builder marked.

A gap is closed in the charter at its law, then sent back to the same
builder by `SendMessage`, naming the law and the charter lines to re-read.
Never hand-patch the file. A law the builder could not place is a law
written unclearly — fix the charter and re-derive.

Each `grounded:` line the builder handed back is lifted into the charter at
its law before the commit; the file already holds the string, so no
re-derive is needed.

## 10. Read the diff as a loss list

Before the commit, every pass, read `git diff` of each derived file. Each
removed instruction is either a law that moved on purpose, or a gap: closed
as in step 9 — lifted into the charter, the builder sent the lines to
re-read — never re-added by hand.

## 11. Hygiene, then one commit

`mise run rules-hygiene` must add no violation. Then one commit holds every
charter and every derived file of the pass, plus the README index when a
charter is new:

```
docs(skill): <name> — <what moved>
```

`docs(agent):` for an agent; several names joined with `, ` for a
multi-charter pass. The declined advisor points go in the body. A charter
and its file never commit apart.

## 12. Answer the folded posts through one Haiku clerk

After the commit, spawn one `clerk` subagent, `model: "haiku"`, with the
order below as its whole prompt, written inline in the `Agent` call — no
scratch file, no path, no turn spent writing it out first. The order is
replies only, one line per post: its comment id and the verdict,
`folded in <sha>: <law or digest row>` or `rejected: <why>`. A
multi-charter pass sends one clerk, the order carrying one block per board.

```
Reply to and resolve each feedback post below. For each: write the
verdict text to a file, run
`mise run feedback -- reply --resolve <comment-id> <file>`, and report one
line per post (comment id, verdict, done or the error).

`<charter>` board:
- <comment-id>: folded in <sha>: <law N | digest row: <date · kind → what>>
- <comment-id>: rejected: <why>
```

The clerk reports one line per post. Check that every post the pass folded
or rejected has a line; one that does not goes under `Not done`.

## 13. Scope

The pass touches the charters, their derived files, the README (its protocol
bullets are this skill's laws in prose and move with them; its index moves
when a charter is new), and the foreign lines step 6 updates. Nothing else:
a rule, a doc, a mise task or a code change the wish implies is named in the
report, not made here. `.claude/rules/charters.md` is a rule and follows
`writing-rules.md`.

## 14. Report

The session-report shape (`docs/domain/session-report.md`):

- `Landed` — the commit sha and the laws that moved; the derive tier chosen
  for each charter.
- `Not done` — posts not answered, advisor points declined, a failed
  `unanswered`, and each rule, doc, mise or code change the wish implies.
- `Needs the owner` — a fork the wish opened and did not close.
