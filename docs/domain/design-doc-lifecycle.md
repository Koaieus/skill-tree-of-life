# Design-doc lifecycle

`docs/design/` is what *could* be, `docs/domain/` what *is*, `docs/adr/` what
was decided (`.claude/rules/design-docs-vs-code.md`). This page is how a design
doc moves between them: promoted to `docs/domain` (and ADRs) when built,
archived afterwards.

## The scheme

Every top-level `docs/design/*.md` except `index.md` opens with:

```
---
status: exploring | settling | built
domain: docs/domain/<x>.md     # required when built, absent otherwise
---
```

| Status | Means |
|---|---|
| `exploring` | Ideas, spitball, lore, open threads. The default. Not spec for anything unless a `Ready` issue cites it. |
| `settling` | Converging — the owner is filling and fixing it (e.g. the aspect matrix), or parts are built and the rest is being decided. |
| `built` | Every passage left in it is shipped. Decisions are in ADRs, behaviour is in the named `domain:` doc. A transient state: the next step is archiving. |

The index (`docs/design/index.md`) carries a Status column that mirrors the
frontmatter, with the domain twin linked for a `built` row.

## Within a live doc vs. a whole doc

- **A passage** that the code or a later call has overtaken is **deleted**, not
  annotated — the existing rule. Most of our design docs with a domain twin
  (`click_grammar`, `node_subtypes`, `damage_over_time`, …) are live docs that
  already shed their built half this way; they stay `exploring`/`settling`.
- **A whole doc** that is built is **archived**, not deleted — the record of
  what was weighed survives, out of the live set.

## Promotion steps

1. Confirm every passage is shipped. Anything still unbuilt either moves to an
   issue / another design doc, or the doc is not `built` yet.
2. Each settled architectural call → an ADR (the `adr` skill). Game-design calls
   that aren't architecture stay in the issue that decided them.
3. The "what is" → `docs/domain/<x>.md` (new or existing), present tense, no
   decision prose.
4. Set `status: built` and `domain: docs/domain/<x>.md`.
5. `git mv docs/design/<name>.md docs/design/archive/<yyyy-mm-dd>-<name>.md`
   (the date is the archiving day), add the header below directly under the
   frontmatter, and remove its row from the index's Documents table.
6. Repoint inbound links: a `docs/domain/` page should link the domain twin,
   not the archive. If it must cite the archived doc, say so with
   `design record:` (or `history:`) in the same line.
7. `mise run docs-hygiene` until green; commit.

## Archived-doc header

Directly after the frontmatter (kept, `status: built`), exactly two lines:

```
> **Archived <yyyy-mm-dd> — design record, never cite as truth.** What is: [docs/domain/<x>.md](../../domain/<x>.md).
> Decisions: [ADR NNNN](../../adr/NNNN-<slug>.md), … (or `none — no architectural call`).
```

The rest of the doc is left as it was on the day it was archived.

## `mise run docs-hygiene`

Reports; exits 1 on any violation, one line each. Checks:

- every top-level `docs/design/*.md` (except `index.md`) has frontmatter with a
  valid `status:`;
- a `built` doc names a `domain:` path that exists;
- every `docs/design/archive/*.md` (except `README.md`) carries the two-line
  header and its `What is:` domain link exists;
- `docs/design/index.md` links every top-level design doc;
- **warn only:** a `docs/domain/*.md` line linking into `docs/design/` without
  `design record:` / `history:` on it. Today these are mostly legitimate
  pointers at a live doc's unbuilt half, so they are counted, not failed
  (`-- --verbose` lists them). A link into `docs/design/archive/` without the
  phrase, or to a design path that no longer exists, **fails** — that is what
  archiving a doc breaks.
