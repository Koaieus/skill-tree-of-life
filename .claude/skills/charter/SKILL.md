---
name: charter
description: 'revise one or more skill or agent files through their charters — read the invocation''s arguments first (charter names, then the wish; none: sweep every feedback board, list the charter-less files and offer which to take), edit each charter (a wish, or fold its feedback board with `mise run feedback -- unanswered <charter>`), keep foreign laws in sync across charters, one advisor pass for the whole pass, one fresh Fable (or, for a small charter, Opus) subagent per touched charter re-derives its files from the charter alone — or, for a pass that moves only a few laws, an Opus subagent patches just those laws'' lines — rules-hygiene, one commit, the folded posts answered through a Haiku clerk. Use when the user says "revise a skill", "update the charter", "fold the feedback board", "re-derive <skill>", "change the <agent> agent", "any skill feedback?", "check the boards", "/charter", "/charter <name> [<name>…] [<wish>]", or when a session is about to patch a `SKILL.md` or an agent file directly.'
---

# charter

The one way to change a `.claude/skills/<name>/SKILL.md` or a
`.claude/agents/<name>.md`: the charter changes first, the file is derived
from it. Design and laws: `docs/charters/charter.md`.

## Steps

### 1. Read the invocation's arguments

The invocation is `/charter [<name>…] [<wish>]`. Read it before anything
else, the door in step 2 included.

- Leading words that name a charter (`docs/charters/<name>.md`), a skill
  (`.claude/skills/<name>/`) or an agent (`.claude/agents/<name>.md`) are
  the pass's charters. An agent resolves through the `docs/charters/README.md`
  index to the charter that builds it (step 3).
- The text from the first word that names none is the **wish**, verbatim.
- Names and no text: the boards are the pass's only input.
- Text and no leading name: name the charters the wish touches and confirm
  them with one `AskUserQuestion` (headless: name them in the report).
- No arguments at all — the **sweep**: run `mise run feedback -- unanswered`
  with no charter (its usage is `unanswered [<charter>]`) to list every
  board's open posts, and read the README index against `.claude/skills/`
  and `.claude/agents/` to list every file with no charter. Offer the
  charters with open posts and the charter-less files through one
  multi-select `AskUserQuestion` and run the pass on what the owner picks.
  A headless session reports the sweep as that menu and stops. A failing
  `unanswered` is handled as in step 4.

### 2. One door

Every change to a skill or agent file goes through this skill. A session
that finds itself patching an instruction file directly stops and runs
this skill instead. A diff that touches a file and not its charter is the
bug. This skill's own charter is changed the same way as any other —
through this skill.

### 3. Resolve each charter; a file with none gets its first one

- The charter is the one whose first paragraph names the file — usually
  `docs/charters/<name>.md`, but an agent may be built by a skill's
  charter, so check the README index before concluding there is none.
- A file with no charter: write `docs/charters/<name>.md` from the file's
  own imperatives — each must/never becomes a numbered law with the why
  the file or the rule it points at gives — plus *What it is for*, a cost
  model, *Frontmatter*, *Revisit when* and an empty corpus; add it to the
  README index; then apply the wish and derive. Never patch a charterless
  file.
- A charter names what it builds and carries everything the build needs:
  its first paragraph lists the derived file or files (a charter may build
  more than one), and it carries a *Frontmatter* section — the
  `description` with its trigger phrases, and for an agent the `model` and
  `tools` — or states them in its laws. A charter missing any of this gets
  it added now, lifted from the current file, before anything is derived.
  That lift, step 5's first read and step 3's first charter are the only
  times a current file is read into a charter.

### 4. Edit every named charter: the wish and the board, same pass

Run for every named charter before anything is derived.

- Read the board every time: `mise run feedback -- unanswered <charter>`.
  A wish never lands on top of an unfolded post.
- A **wish** becomes a law (with its why), a row in the incident corpus,
  an entry under *Revisit when*, or a fork noted there as open.
- Each **post** becomes one of those or a rejection, with a row in the
  charter's *Fold digest* (date · kind → what it became). Keep each
  post's comment id and verdict text for step 12. A post that belongs to
  another charter is moved with
  `mise run feedback -- post --verbatim <other> <file>`, not folded here.
- `unanswered` failing does not stop the pass: continue on the wish and
  put the failure under `Not done` in the report.

### 5. Read the current file against the laws (first loss-list read)

Before deriving, read each charter's current file and confirm every
imperative line — each must and never, each command, brief and order —
has its law. One that has none is lifted into the charter at the law it
belongs to.

### 6. Keep laws in one place; take a changed law's readers with it

- A law lives in the charter whose skill or agent *does* the thing. A
  charter that relies on another's law does not restate it as a numbered
  law of its own: it lists it in its `## Foreign laws` section, one line
  each, exactly as `- [<owner>](<owner>.md) law <N> — <what this skill does
  with it>`, cites it in its own laws in the same `[<owner>](<owner>.md)
  law <N>` form, and keeps only its own side — what it hands over, what it
  expects back. A law found duplicated across two charters is merged into
  the one that does the thing, the other's copy turned into its foreign
  line, in this pass.
- For each law the pass changed, superseded, retired or renumbered: grep
  `docs/charters/` for `(<name>.md) law` and read the hits for <N> (a
  citation may name a range, `laws 13–14`), plus the charter's bare name
  near `law`. Update each reader's foreign line and citing laws in this
  pass; a reader whose derived file states what the law changed joins the
  pass as a touched charter (step 9).
- Law numbers are stable: never renumber or delete a law — it stays,
  reading `retired — <why>` or `superseded by law <M>`, and new laws
  append.

### 7. One advisor pass for the whole pass

After every charter is edited and before anything is derived: one
`advisor` call, however many charters the pass names. Apply each point to
its charter or decline it; name the declined ones in the commit body. One
pass, not a loop.

### 8. Choose the mode per charter: patch or rebuild

- **Patch** when the charter's file exists, the pass moved about three
  laws or fewer (changed, added, retired) and changed no existing brief,
  order, report shape or step order — a new law with a new brief of its
  own is still additive.
- **Rebuild** otherwise: a first charter (step 3), a step-5 read that
  lifted anything, a structural change, a patch that fails the step-10
  check, or the owner asking for one.
- Name the mode each charter took in the report.

### 9. Derive: one fresh, bounded builder per touched charter

- One `general-purpose` subagent per charter the pass edited, with a
  `name` (step 10 sends gaps back to it) and `run_in_background: false`.
  It writes every file that charter builds — a skill and its agent in one
  context. A multi-charter pass spawns its builders in one message.
- **Tier (rebuild):** `model: "fable"`; a *small* charter — under about
  200 lines, building one file of under about 150 — may take
  `model: "opus"`, the lead's call, named in the report. Its brief is the
  **derive brief** below, verbatim, with only the paths and the foreign-law
  lines filled: no summary of what changed, no diff, no paste of the old
  file.
- **Tier (patch):** `model: "opus"` (Fable when a moved law is subtle, the
  lead's call), the **patch brief** below, listing the moved laws by
  number and nothing more — no summary of the change, no diff.
- The builder reads the charter (`sed -n` ranges of about 250 lines from
  its first call), the short README whole, the text of each law the
  charter's *Foreign laws* section cites from the owning charter, and may
  spawn at most one `Explore` with `model: "sonnet"` capped at about 5k
  tokens — never about the target file or an earlier version of it. A
  patch builder also reads the current target file. Nothing else; no
  advisor; about eight tool calls.
- An exact string the file needs that the charter does not give is never
  invented: the builder writes `<gap: law N — what is missing>` or, when
  its Explore found it verbatim, uses it and lists
  `grounded: law N — <string> — <source>`; both come back in its handback.

**Derive brief** — the bracketed alternative for a charter that builds
more than one file, the agent clause when one target is an agent:

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
*Frontmatter* section states them, the description on one line as a
single-quoted YAML scalar — `description: '<text>'`, each `'` inside the
text doubled (`''`). [Agent: and `model:` and `tools:` as the charter
states them.] The body is steps only — the pipeline a fresh
session follows, with the exact briefs and orders it uses, taken from the
charter — with one one-line pointer to the charter and nothing the
charter's *What the skill file must not contain* section forbids (no
dates, issue numbers, owner quotes, or reasoning-behind). Every numbered
law in the charter must be recognisable as a step or a line in the file.

When done, report each path, the gap list (or "no gaps") and the
grounded list (or "none") via SubagentHandback.
```

**Patch brief** — the same alternatives as the derive brief:

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
longer matches it or its description is not one single-quoted line
(`description: '<text>'`, each `'` inside the text doubled). Leave every other line byte for byte. A listed law
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

### 10. Check the build law by law; fix gaps through the builder

- Every numbered law has its line in the file; the file cites the charter
  once; it holds no date, no issue number, no owner quote, no "was:". A
  quote or a reasoning-behind is caught by the law-by-law read.
- Mechanical greps on the whole file: `20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]`
  and `#[0-9]{3,}` find only template placeholders; `^description: '.*'$`
  finds exactly one line, in the frontmatter; `<gap: law` finds every gap
  the builder marked (a template placeholder aside).
- A derived file's `description:` is one single-quoted YAML scalar on one
  line — `description: '<text>'`, each `'` inside the text doubled (`''`)
  — never a plain scalar, and not a block (`>-`) or double-quoted one. A
  patch re-quotes a description it finds in another form.
- A gap is closed in the charter at its law, then sent back to the same
  subagent by `SendMessage` naming the law and the charter lines to
  re-read; never hand-patched. A law the subagent cannot place is a law
  written unclearly — fix the charter and re-derive.
- Each `grounded:` line is lifted into the charter at its law before the
  commit; the file already holds the string, so no re-derive is needed.
- For a patch, the law-by-law check runs on the moved laws, the greps on
  the whole file.

### 11. Read the diff as a loss list, then hygiene and one commit

- Before the commit, every pass, read `git diff` of each derived file as a
  loss list: each removed instruction is a law that moved on purpose, or a
  gap closed as step 10 closes one — lifted into the charter, the builder
  sent the lines to re-read — never re-added by hand. For a patch, confirm
  the diff stays inside the moved laws.
- `mise run rules-hygiene` adds no violation.
- One commit holds every charter and derived file of the pass, plus the
  README index when a charter is new: `docs(skill): <name> — <what moved>`
  (`docs(agent):` for an agent; several names joined with `, ` for a
  multi-charter pass). A charter and its file never commit apart.

### 12. Answer the folded posts through one Haiku clerk

After the commit: one `clerk` subagent, `model: "haiku"`, the **clerk
order** below as its whole spawn prompt, written inline in the `Agent`
call — no scratch file for the order. Per post: its comment id and the
verdict, `folded in <sha>: <law or digest row>` or `rejected: <why>`. The
order is replies only, one line per post. The clerk runs
`feedback -- reply --resolve` and reports one line per post; check every
post the pass folded or rejected has a line, and list one that does not
under `Not done`. A multi-charter pass sends one clerk, the order carrying
one block per board.

**Clerk order** — one block per board for a multi-charter pass:

```
Reply to and resolve each feedback post below. For each: write the
verdict text to a file, run
`mise run feedback -- reply --resolve <comment-id> <file>`, and report one
line per post (comment id, verdict, done or the error).

`<charter>` board:
- <comment-id>: folded in <sha>: <law N | digest row: <date · kind → what>>
- <comment-id>: rejected: <why>
```

### 13. Scope and report

- Scope is the charters, their files, the README and the foreign lines
  step 6 updates. The README's protocol bullets are this skill's laws in
  prose and move with them; its index moves when a charter is new. A rule,
  a doc, a mise task or a code change the wish implies is named in the
  report, not made here; `.claude/rules/charters.md` is a rule and follows
  `writing-rules.md`.
- The report is the session-report shape (`docs/domain/session-report.md`):
  `Landed` holds the sha, the laws that moved and the mode and tier each
  charter took; `Not done` the posts not answered, the advisor points
  declined, a failed `unanswered`, and each rule, doc, mise or code change
  the wish implies; `Needs the owner` a fork the wish opened and did not
  close.
