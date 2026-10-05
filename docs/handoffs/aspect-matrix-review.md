# Handoff — aspect-matrix design round

**State:** written against the commit that updates this file. Authoritative:
`docs/design/aspect_matrix.md` (Glossary, § Attributes and pairs = the
twelve, § Schools with the round 3/4 owner blocks, Contenders,
Misplacements), `skill_node_addons.md`, `core_classes.md`, and #1249 / #1252
/ #1414 comments. This file only orders the work. Speak the pinned Glossary.

Settled 2026-10-05: the six attributes are the schools; primaries never
scale via primaries or aspects; the placement rule (verb or own strength
turned bad); Corruption → WIS; Bleeding → STR; Explosive → DEX; Elemental
kept away; tempo is an axis, not a school; coolness is not a school; struck:
Thorns, Petrified, Debt, Frailty. Explorer sweeps (reference games, attribute
dossier, tempo plumbing, issue trail, ADRs) are done and folded in — don't
re-sweep.

## Open forks, best first

1. **The twelve, rounds 5–6 (2026-10-06):** Silence UNSETTLED (owner sleeping on it — the boolean saturates; see round 6), was stacks as
   duration (INT); Greed closed (×2 per hit, one stack spent post-hit, WIS);
   Fatigue / Slow / Paralysis struck; CON keeps one open slot; school spread
   within one. Left: **Fortress** may be struck and drag may have no home —
   owner wants to see it in action first. Next code-side step: Greed's and
   Silence's seams (landing term; no attack-origin gate exists today).
2. **Spell facet rule** — reconcile § "The rule"'s Spell bullet with the
   owner's four-shape coverage (many small / few big / utility / boon) and
   "spells diverge by topology". Spell affinity (owner idea) is on #1250. Couples to #1381, #1384, #1389, #1392,
   #1394, #1397, #1400, and #1250 (infusion).
3. **Misplacements migration** — items 3–8 and the Twins/Orphans/Defender
   lists are now mostly answerable by the rule; move each ruled line into
   its row and delete it. Ruled but not migrated: Pacifist (not a
   misplacement), Watchtower (item 2 → #1413), Thorns (struck).
4. **Buffs** — pass proposal: only as a face inside an existing row, never a
   buff row. Not ruled.
5. **Pure-coolness node** — its own procgen node, or only a side roll.
6. **Production vs firing** — #1413, "needs a big think".

## Deferred, next session

- ADR candidate: *attributes are schools; primaries never scale via other
  primaries* — a stat-system invariant (`.claude/rules/stats-system.md`).
- Thorns OQs in `combat_system.md` (OQ13/32) and `core_classes.md`
  (OQ7/9/11) to delete under the design-docs rule; Halo is not a design
  basis (owner).
- Write the school onto each row hub; file the Bleeding / Fatigue / Greed
  contender rows once their forks close.

## Ready / filed

- #1414 — stale-fact fixes (now incl. three ADR contradictions).
- #1249 — remaining: `node_subtypes.md` + procgen pool swap.
- #1415 — `tempo` → `momentum` rename (Backlog).

Delete this file once the Misplacements section is empty and the twelve has
no `?` cells.
