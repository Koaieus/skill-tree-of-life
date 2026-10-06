# Archived design docs

What lands here: a `docs/design/` doc whose every passage shipped — its
decisions moved to ADRs (`docs/adr/`) and its "what is" to the `docs/domain/`
page named in its `domain:` frontmatter. Files are named
`<yyyy-mm-dd>-<name>.md` by archiving date.

**Never cite an archived doc as truth.** It records what was weighed, not what
the game does; the code, `docs/domain/` and the ADRs are the truth.

Each archived doc carries, directly under its frontmatter:

```
> **Archived <yyyy-mm-dd> — design record, never cite as truth.** What is: [docs/domain/<x>.md](../../domain/<x>.md).
> Decisions: [ADR NNNN](../../adr/NNNN-<slug>.md), … (or `none — no architectural call`).
```

Process: [`../../domain/design-doc-lifecycle.md`](../../domain/design-doc-lifecycle.md).
