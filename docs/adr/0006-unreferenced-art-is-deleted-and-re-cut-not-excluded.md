---
id: 0006
title: Unreferenced purchased art is deleted and re-cut from a pipeline, not excluded from the export
status: accepted
date: 2026-09-04
deciders: owner
supersedes: []
superseded-by: null
sources:
  - "f8bdcb2"
  - "d5396d5"
  - "docs/domain/exporting.md"
tags: [exporting, assets, build]
---

# ADR 0006 — Unreferenced purchased art is deleted and re-cut, not excluded

> **Backfilled 2026-09-07** from `docs/domain/exporting.md`, which recorded this
> decision before the ADR tier existed (see
> [ADR 0001](0001-adrs-record-decisions-domain-docs-record-behaviour.md)). The
> date above is the date of the call, not of this file.

## Context

`assets/` is a *stock of source material*, not a manifest of what the game uses,
and the export preset's `all_resources` mode ships the stock. In 2026-09 that was
**17M of the 22M of packed art with zero references** — `border_pack`,
`button_round`, the 1x/2x rungs of `Icon set 1`, and five loose pngs including two
3.7M bar sheets.

The one thing keeping `Icon set 1` alive was six glyphs on the pause menu, out of
258 files at three resolutions. So the material split cleanly into "referenced by
nothing" and "referenced by six files that could come from somewhere else".

The first fix, the same day, was an **export exclusion** (`f8bdcb2`, 88M → 76M),
taken deliberately as a holding pattern: *"the material is still the pool the game
is being built out of, so the cost of being wrong should be editing one line, not
going back to the pack."*

## Decision

**Delete the packs, and re-cut anything still referenced through a pipeline that
can reproduce it** — owner call 2026-09-04. The six pause-menu icons were re-cut
from game-icons.net through the repo's existing `mise run icons:update` mapping,
and the packs went. The export exclusions added for those same directories were
reverted in the same commit: **deleted material needs no filter.**

The general form, and the order to prefer: *an exclusion is the holding pattern; a
delete plus a pipeline-baked replacement is the answer, and it leaves nothing to go
stale.*

## Consequences

- **The art is reproducible from a mapping rather than owned as a pack.** Losing
  or replacing the source no longer risks losing six live icons.
- **The export preset stays close to empty.** Every exclusion is a rule that can
  rot silently against a moving `assets/`; there are now fewer of them, not more.
- **`assets/` keeps only material with a claim on it.** The archives still there
  (`icons.zip`, `border_pack.rar`, …) are repo weight only — Godot has no importer
  for them, so they were never packed and there is nothing to exclude.
- **A residue remains, known and unbought:** `assets/emblem_luts/`'s `addon_*` and
  `armed_*` LUTs (~348K) are emitted by the icon bake and referenced by nothing.
- **The pipeline gained a knob to make the re-cut faithful** — `icons:update`
  learned a per-folder `#fg` directive, because the six were baked WHITE rather
  than the pipeline's default cyan (**owner call:** *"cyan sounds like a modulation
  choice down the line"*).

## Alternatives considered

### Export exclusions, kept as the end state

Filter the unreferenced directories out of the build and leave the files in the
tree. This was actually taken first and then reverted; it lost as a *destination*
because a filter is a second, invisible manifest that has to be maintained against
a directory nobody prunes. Two traps it carries, both hit in practice and both
recorded in [exporting.md](../domain/exporting.md):

- **`*` crosses `/`** — `assets/*.png` matches every png at any depth, including
  live art.
- **A directory can be partly live** — `Icon set 1/` shipped at three resolutions
  with six files used from one of them, so the exclusion had to be written per-rung.

Neither trap is visible to any test, because a filter that only exists in the build
can only be verified by grepping the packed `.pck`.

### Keep the pack, ship only its used rung

The narrowest fix: exclude 1x and 2x, ship 0.5x whole. It survives as long as
nobody asks why 252 unused files ship so that six can. It also leaves the six
icons defined by a purchased artifact rather than by a mapping, which is the part
the owner's call was actually about.
