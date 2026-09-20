---
name: adr
description: Write or supersede an Architecture Decision Record in the house format — gate whether it is an ADR at all, check it is not already decided, collect the owner's verbatim dated quotes, draft with rejected alternatives and a supersede trigger, migrate any domain-doc decision prose, index, run adr-hygiene, commit, link back to the source issue. Use when the user says "make an ADR", "record this decision", "write that up as an ADR", "supersede ADR NNNN", or when a settled architectural call has just been made with the owner and would otherwise live only in the transcript.
---

# ADR

Write the record yourself, in this session — you are the agent that sat with
the owner. The `adr-librarian` agent retrieves and drafts; it never authors.
The format, boundary table and template are in `docs/domain/adr.md`; read it,
do not copy it here. (Design behind this file: `docs/charters/adr.md`.)

## 1. Gate — is this an ADR?

Three questions; any no → stop and name the right home.

- **Was an alternative rejected?** No → domain doc. Nothing to re-argue.
- **Is it engineering, not game design?** No → `docs/design/` or an issue.
- **Has the owner spoken?** No → the issue stays in `Needs design`; do not
  write a `proposed` record to frame it, `/swarmify` is the gate.

## 2. Not already decided?

```bash
grep -i '<topic words>' docs/adr/index.md
```

Smells settled and grep is quiet → ask the librarian
(`Agent(subagent_type: "adr-librarian")`). A hit means **supersede** (§6),
not a sibling.

## 3. Collect the quotes before drafting

Pull every owner sentence that carries the decision — from this transcript
and from the source issue (`gh issue view <n> --comments`). Note the **date
each was said**. Each line of the *Decision* section must trace to one; a
paraphrase is your conclusion, not the owner's.

## 4. Draft

Filename `docs/adr/NNNN-<slug>.md`, `NNNN` = highest existing + 1. Template
and frontmatter: `docs/domain/adr.md` → *Writing one*. Checks the template
does not make for you:

- `date:` is the day the owner decided, not today.
- `title:` is the decision, actionable without opening the file.
- `status: accepted` even when the owner calls it tentative — tentativeness
  goes in *Consequences* as **the named trigger for superseding** (what would
  have to become true for the most-likely-revived alternative to win).
- *Alternatives considered*: one subsection per rejected option, why it lost,
  which grounds are already dead. Mark the alternative most likely to be
  revived.
- `sources:` never empty — the issue, the domain doc, the files.

## 5. Migrate, index, verify, commit, link

If a `docs/domain/` page carries this decision's "we chose X because not Y"
prose, move the verdict *and* its rejected options out in this same commit
and leave a one-line link — never half.

```bash
# add the row after the previous highest id in docs/adr/index.md
mise run adr-hygiene                       # must add no violation
git -C <repo> status --short docs/adr      # shared checkout: look first
git -C <repo> add docs/adr/NNNN-*.md docs/adr/index.md [migrated page]
git -C <repo> commit -m "docs(adr): NNNN <title>"
gh issue comment <n> --body-file <scratch>  # ADR path + sha; backticks via file
```

## 6. Superseding

Never edit an accepted record's body. Write the new record with
`supersedes: [NNNN]`; on the old one change **only** `status: superseded` and
`superseded-by: MMMM`; add the new index row; `adr-hygiene` checks the link
resolves both ways. The old record's *Context* is the reason the new one looks
the way it does — it is kept, not hidden.
