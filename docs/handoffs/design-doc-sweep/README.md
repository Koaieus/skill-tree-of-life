# Design-doc sweep — handoff (2026-09-29)

**Owner rule, 2026-09-29, verbatim:** *"docs/design: what could be, what might be
there, or if faulty: what has been there (would need a cleanup because that'd just
confuse everyone; ADRs are there to remain and be invalidated, design docs don't
have this luxury) / docs/domain: what is"*. Follow-up, same day: design docs are
freely tweakable brainstorming space; a drone treats one as spec only when its
`Ready` issue cites it. Encoded in `.claude/rules/design-docs-vs-code.md` and the
`docs/design/index.md` banner.

## Done (commits 3ce62a5 … 88031d4, NOT pushed)

- `mvp_decisions.md` → `docs/adr/legacy-mvp-decisions.md` (pre-ADR record, in the
  ADR index, D→ADR crosswalk at its top); every citation repointed.
- `spells.md` split into Shipped / issue-backed / idea pool; `core_classes.md` and
  `GDD.md` carry per-class status.
- The "mvp_decisions is authoritative" banners are gone.

## To do — apply the five survey reports in this folder

`combat.md`, `world.md`, `stats.md`, `nodes.md`, `misc.md` classify every section
of every design doc as COULD / IS / WAS / MIXED / UNSURE, with grep evidence.
Spot-check the evidence before acting on a row. They were produced by read-only
subagents.

**The filter to apply to every IS row (the agents were briefed "IS → move to
domain", which is too generous):** the *original design sketch of something that
shipped* is "what has been there", so the default is **delete**, not move. Move a
sentence only if it is true today **and** absent from code / `docs/domain`. If it's
a *why*, its home is a code docstring or an ADR, not a domain doc. Restating a
`.tres` `description` in prose is a second copy that drifts.

Queued from this session (not in the reports):
- `spells.md` Shipped section and the design notes → delete. Keep only the
  sentences that pass the filter. Leafblower's `<=`-not-`<` reasoning is a *why*,
  so it goes in the `.tres`/filter docstring. Cyclone's dated owner-call prose
  goes in an ADR candidate, or is already in `docs/domain/spell-propagation.md`.
- `core_classes.md`: Ninja/Serpent entries → delete, and so does the status table
  once built entries leave. Keep `#786`-style pointers on issue-backed classes.
- `status-tags.md`: the "Superseded" block → delete. The tag channel has shipped
  (see `misc.md`), so the doc's own relocation trigger has fired.
- `node_subtypes.md`: nearly all shipped (see `nodes.md`). `click_grammar.md`
  and most of `core_movement_plan.md` are shipped (see `misc.md`).
- `docs/GDD.md` milestone checklists are wholesale stale. Owner's call whether
  to rewrite or cut them.
- `docs/design/*.zip` and the handoff HTML folders: check whether they're still
  referenced.

Checks:
- Does swarmify's drift stamp (verified by `clerk`) cover design-doc citations
  in a `Ready` spec? If not, swarmify should copy the settled text into the issue.
- Does `docs/charters/drone.md` / the drone brief already say "your issue is
  your spec"?
- Candidate ADR backfills (the owner picks): D-18, D-33, D-27, D-24, D-2/D-4.

Delete this folder when the sweep lands.
