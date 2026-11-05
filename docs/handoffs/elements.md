# Elements design — continuation prompt

Paste the block below as the first message of the next session. Everything it
names is on master; nothing lives only in a transcript.

---

Continue the elements design pass (#1716 is the hub). Read, in order:

1. `docs/design/elements.md` — every owner call to date, quoted and dated
   (2026-11-03/04/05); pass proposals are marked as such.
2. `docs/adr/0072-*.md` (an aspect is one status, an element is a family) and
   `docs/adr/0073-*.md` (a hit is damage + rider map + reach entry; an intake
   row has a use) — then `docs/adr/0070-*.md`, which 0073 should have cited:
   a row's use is a swappable `LoadUse` Resource (`attack/spell/load_use/`),
   not an enum. "ride" = `PlantUse`, "reach" = a `ReachUse` replacing
   `DetonateUse` + `FuelUse`, "shape" = whatever spell-only shaping remains;
   `CleanseUse` is a payload modifier beside ride.
3. The adversarial review findings recorded at the end of this file.
4. #1733 (payload and reach rules R1–R5, owner verdicts in round 2), #1444
   (Ice: Frost / Frostbite / Frozen, the toll, shatter), #1660 (Fire: Fuel +
   Heat, Metropolis diffusion), #1741 (landed: a hit crits once, its payload
   copies it).

Work case by case with `AskUserQuestion`, one or two forks per question, the
recommended option first; after each verdict, write it into
`docs/design/elements.md` with the quote and date, then a docs-only PR (the
cloud auto-merge takes `docs/design/` and `docs/handoffs/`, NOT `docs/adr/`
— an ADR needs a human merge, so batch ADRs separately). Run
`mise run docs-hygiene` after touching a design doc and `mise run
adr-hygiene` after an ADR. `gh issue view` is blocked (GraphQL); use
`gh api repos/Koaieus/skill-tree-of-life/issues/<n>` and `/comments`.

Still open, in this order:

- **"member"** as the term for a status of an element (Fuel is a member of
  Fire; an Element Matrix row is a member row). Owner asked for a word; not
  yet accepted.
- **read / land / settle** as the landing resolution (pass proposal in the
  doc). If held → ADR 0074 and the pair table's cells are final. Check it
  against #1741's sequencing first (riders land before their hit, ADR 0067;
  `CritRoll.decide` memoised by `crit_decided`).
- **Ice pricing knob**: per-spell int:int affinity converting count to hops
  plus a per-hop payload multiplier near the measured ratio; whether the
  multiplier is one number per spell or the measured ladder. Reads both
  `max_hops` and `max_visits`. Numbers are in the doc (two tables).
- **Fuel access for ranged**: Element Matrix chosen; availability (a reload
  grant from the `fire` count?) and the per-element ammo stock cap
  (`AmmoType.max_stock`, knob or stat?) undecided.
- **Explosive artifacts**: the design says no Explosive aspect survives; each
  of `aspects/defs/explosive.tres`, `identity/defs/explosive.tres`,
  `effects/status/explosive.tres` (tag `charge` → must become `fuel`),
  `attack/ammo/types/explosive.tres`, the Explosive addon,
  `docs/domain/explosive.md`, ADR 0061/0062 needs a named destination or a
  supersession before any element issue goes `Ready`.
- **Element count as a stat**: `fire` / `ice` / `lightning` on the StatBoard
  (manage-stats skill), what `_facet_id` keys a member's
  `<x>_stacks_per_hit` / `<x>_resistance` on (the element or the member).
- Greed under the new vocabulary (#1659); arc pick rule and radius per load
  (#1733); inner-tree shape for elements; Shocked / Burning parked.
- Housekeeping: a comment on #1694 pointing at ADR 0072; the Aspect:Status
  1:1 guard test (code — belongs to the first element issue, not a docs PR).

When the open list above is empty, the doc goes `settling` → spec: split
#1716 into drone-sized children with the `spec` skill (the first is the
element count + `ReachUse` seam; Fire's family is #1660's children; Ice is
#1444).

---

## Adversarial review findings (2026-11-05)

_Pending — filled in when the review lands; see the session that wrote this
file._
