---
id: 0046
title: A concept's display identity — noun, kind, hue, glyph — is one `Identity` resource that every facet def references; `StatusDef.tint`/`icon` and a concept stat's `tint_color` derive from it
status: accepted
date: 2026-10-04
deciders: owner (the atom, the roster, StatusDef-wins); pass (supersession of the 2026-09-14 call, the fallback for concept-less stats, retuned hues)
supersedes: []
superseded-by: null
revisit-when: "A concept needs two hues (e.g. a status that must read differently from its aspect stat), or concept-less stats grow identities and the `StatDef.tint_color` fallback has no authored users left"
sources:
  - "#1403"
  - "#1404"
  - "docs/domain/exporting.md (D13)"
  - ".claude/rules/ui-palette.md"
tags: [ui, identity, palette, stats, status, architecture]
---

# ADR 0046 — Identity is the one display atom

## Context

Every aspect concept carried two hues — `StatusDef.tint` and its `<concept>_aspect` `StatDef.tint_color` — with different values, and two places each called theirs the single source of truth: the `status_def.gd` header (owner, 2026-09-14: *"tint is THE canonical colour of this status everywhere it is mentioned"*) and `.claude/rules/ui-palette.md` (`StatDef.tint_color`). Wither, blindness and armor break also sat in gold, which is reserved for reward.

## Decision

Owner, 2026-10-04 (hub #1403): *the display atom is an **`Identity` resource, one `.tres` per concept**, referenced by every facet def*; *every `<concept>_*` stat (aspect, resistance, stacks_per_hit) carries the concept's identity; where StatusDef and StatDef hues disagree the **StatusDef value wins***.

1. `identity/identity.gd` — `id`, `noun`, `kind` (ASPECT / ATTRIBUTE / VITAL / SPELL / ADDON), `tint` (unlifted, ≤ 1.0; presenters lift it), `icon` (null → a letter). One `.tres` per concept in `identity/defs/`.
2. Runtime discovery is the authored `identity/identity_roster.tres` (`IdentityRoster.shared()`, `by_id`) — never a directory scan (D13). `test/unit/identity/test_identity_roster.gd` is the drift guard and pins same-kind OKLab separation (dE ≥ 0.14) and gold reservation (dE ≥ 0.10 from XP gold except `xp`, `wisdom`).
3. `StatusDef.tint` and `StatusDef.icon` are getters over `identity` — no exports, no setters. `display_name` stays on the def: the status noun may differ from the concept noun.
4. `StatDef.identity` is an export; `StatDef.tint_color` stays an export but its getter returns `identity.tint` whenever an identity is set. **Pass deviation from the spec's "export removed":** ~55 shipped stats (movement points, blade damage, armor…) belong to no concept and author their own hue, which every `tint_color` reader and `test_stat_modifier_format`'s non-white audit depend on. Concept stats drop their authored value; concept-less stats keep it.
5. **Supersedes the 2026-09-14 code-comment call** that `StatusDef.tint` is canonical: the Identity's tint is canonical, the StatusDef reads it. Pass's tentative call, following from the owner's decisions above.
6. Pass-picked hues (tentative knobs, owner retunes in the editor): wither olive `(0.42, 0.46, 0.22)`, blindness pale grey-violet `(0.7, 0.66, 0.8)`, armor break rust `(0.7, 0.3, 0.22)` — off gold. The resistance and stacks stats move from the shared armor/green hues to their concept's.

## Consequences

- A hue or glyph change is one edit on `identity/defs/<id>.tres`; the status, its aspect / resistance / stacks stats, arrows and node tint follow.
- A fixture that needs a status hue hands the def an `Identity` (`test/support/identity_fixture.gd`) — `tint`/`icon` cannot be written.
- Spell and addon identities, the `Aspect` resource and the badge renderer build on this atom (#1403 children).

## Alternatives considered

- **Fields on each def + an id registry** — two writes per concept again; the drift this ADR exists to end.
- **A Theme type-variation per concept** — dead: arrows, node tint and VFX read these colours outside Control theming.
- **A const table in one script** — dead: a `.tres` def cannot reference a script constant.
- **Removing `StatDef.tint_color` outright** — would white out every concept-less stat; revisit only once those stats have identities of their own.
