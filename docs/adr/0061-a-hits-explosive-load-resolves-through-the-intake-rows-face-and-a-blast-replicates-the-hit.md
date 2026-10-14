---
id: 0061
title: A hit's explosive load resolves through the intake row's face (DETONATE / PLANT / FUEL), realised as an effects list; a blast replicates the hit under the landing's mask, never damage specifically — supersedes 0060's `rides` flag in part
status: accepted
date: 2026-10-14
deciders: owner (the faces' roles, the filter-gated list); pass (enum naming, the blast-carries-the-hit framing, "both" as composition)
supersedes: [0060]
superseded-by: null
revisit-when: "A row needs a behaviour no combination of DETONATE, PLANT and FUEL entries expresses, or a blast must carry something that is not a replica of its hit"
sources:
  - "#1594"
  - "#1595"
  - "#1597"
  - "#1250"
  - "docs/adr/0060-infusion-vocabulary-aspect-intake-int-ratio-affinity-times-ingest.md"
  - "docs/design/aspect_matrix.md"
tags: [spells, aspects, infusion, combat, on-hit, architecture]
---

# ADR 0061 — A hit's explosive load resolves through the intake row's face; a blast replicates the hit

## Context

ADR 0060 gave an `AspectIntake` row one flag, `rides: bool` (#1597): true lands the load as a rider, false makes it fuel that only shapes the spell. Explosive now has a status (#1594) and a blast is sized by the node it goes off on (#1595), so "what does this hit's explosive load do" has more than two answers, and a heal that should detonate or plant had no way to say so. The blast was also damage-specific. Game numbers (spend, power, resonance) are design tuning and live in the design doc; only the shape of the call is recorded here. This supersedes 0060 clause 4 (the `rides` flag) only; everything else in 0060 stands.

## Decision drivers

- One mechanism for every hit source: blade contact, arrow, spell.
- The blast must work for a heal as well as damage.
- Authoring stays on the intake row; no new parallel resource per behaviour.
- Peers reproduce the result; nothing new mutates the world outside the recorded hit.

## Decision

Owner, 2026-10-14, verbatim:

- *"The ignites bool knob (or enum? ...) on the hit is a good idea. Keeping that."*
- *"If the loaded hit is configured to DETONATE. The explosive arrow will take PLANT and a more 'flammable oil or unstable goo' role to match."*
- *"Healing spell might author an alternative set of hits or tag the hit list items then filter this list at hit time depending on target node / spell ctx, e.g. set entire spell to 'detonate if primary target has even degree, plant if odd'"*
- On a heal wanting both faces: *"healing circle can't have it both ways? As options separately or together?"* — answered by the filter sentence above; the owner did not rule on "both" as a face.

So (owner-accepted formalisation, 2026-10-14):

1. **Face.** The intake row carries a face enum, replacing `rides: bool`: DETONATE (default for every hit), PLANT, FUEL (today's `rides = false`). The default comes from the aspect def; a row overrides only when it differs.
2. **Composition.** A face is realisable as an effects list with the load injected as power (the shape of ammo `on_hit_effects`); empty means the aspect's default. A list entry may be gated by the propagation filter resource type, evaluated at landing.
3. **A blast is the hit.** It replicates a fraction of whatever its hit does, plus the hit's non-explosive riders, under the landing's own target mask. It is never a damage-specific effect, and never plants.
4. **Explosive is infusable**, through the same row and faces.

## Consequences

- One path serves damage and heal, melee, ranged and spell; a peer replays the recorded hit like any other.
- The `rides` flag and the "explosive-only rider does not detonate" exception disappear.
- A list-of-effects face costs more authoring than an enum alone.

## Alternatives considered

- **Keep `rides: bool` (0060)** — lost on the heal driver: two states cannot name PLANT. Revivable only if the faces collapse to two.
- **A third face, "both"** — tentative pass pick against it: two entries at full load, priced by the row's affinity, say the same thing. The owner asked the question and has not ruled; open on #1608, revivable.
- **A bool `ignites` on the hit** — the owner kept the knob "(or enum?)"; the pass chose the enum on the intake row, since a bool cannot carry three faces. Tentative pick; the most likely to be revived.
- **Two Explosive aspects, one that blasts and one that plants** — the owner called it "an unwanted split (2 explosive aspects?)" on 2026-10-14; the face enum carries both on one row. Dead ground.
- **Derive the default face from the hit's payload (damage detonates, no damage plants)** — lost on the heal driver: a heal that should blast as a circle could not say so. The default lives on the aspect def instead, PLANT is always opt-in.
- **A damage-specific blast effect** — lost on the heal driver and on one-mechanism-for-every-hit.
