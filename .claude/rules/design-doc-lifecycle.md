---
description: Design-doc lifecycle — status frontmatter, promotion to docs/domain + ADRs, then archive
paths:
  - "docs/design/**"
---

# Design-doc lifecycle

Every `docs/design/*.md` opens with `status: exploring | settling | built` frontmatter (default `exploring`); `built` also names `domain: docs/domain/<x>.md`. `built` means the decisions went to an ADR and the "what is" went to that domain doc — the design doc is then **moved** to `docs/design/archive/<yyyy-mm-dd>-<name>.md` with a two-line header pointing at the domain doc and the ADRs, and its index row goes with it.

**Why:** a design doc that outlives its build reads as spec for something that already exists differently; deleting it loses the record of what was weighed. Archiving keeps the record and takes it out of the live set.

**How to apply:** bump `status:` (and the index's Status column) when a doc's state changes; promote and archive only when the whole doc is built — a half-built doc stays live and loses its built passages instead. Run `mise run docs-hygiene` after touching any design doc. Steps and header template: `docs/domain/design-doc-lifecycle.md`.
