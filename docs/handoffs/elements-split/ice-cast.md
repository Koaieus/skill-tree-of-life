Title: Ice on a cast: what the concentrate is and how it prices the seed

Intended lane: `Needs design`. Not blocked; blocks nothing. A sibling under hub #1716. Design home: `docs/design/elements.md` § Ice on a cast (:538-627).

**Problem.** An Ice load on a spell is meant to trade the cast's hops for a stronger seed, but the doc calls its shape "the pass's best shape … unconfirmed" (:540-545). The pricing formula also says two different things (:580-584 against :610-611). Until both are settled, #{forge} stubs Ice on a cast as hops untouched and the seed scaled ×1. The owner, 2026-11-10: *"yeah needs design that one, just stub it as an unconditional ×1 until we fix it/decide on it"*. The Cold ride row still plants Cold.

**The Cold spell #1789 is the same design beat.** Its innate Ice row is this concentrate, eating its hops to 0 (owner, 2026-11-09, :1052-1058). Settle the two together.

## What the owner has already said (verbatim, dated; not reopened)
- *"ice concentration should i think still be a thing just not sure how"* (2026-11-08, :540-545).
- *"a spell beforehand doesnt know how many hits a 4-hop spell would do"* and *"a pure nerf if it just reduces hops"* (:552-555): the price must be known at cast, and a hop cut must pay something back.
- Pricing, *"leaning 1"* (2026-11-08, :580-584; ADR 0081 §8). The Ice row's int:int affinity turns count into hops per spell (Venom Burst 2:1, Pestilence 4:1). Each removed hop multiplies the seed by a per-spell knob near that hop's measured ratio. :1049-1051 records this "as a lean".
- *"option 1 but possibly even in this authoring one could set up *how* it triggers exactly. some resource? like most spells -> just reduce hops. some others -> maybe reduce max visits. something that takes the ice-suppression value and uses it to alter the cast spell?"* (2026-11-05, :602-615). The price is an authored mass per spell, and a swappable resource spends it. Rejected: one global curve, and a flat addition per hop.
- *"… ice + fuel sounds like a combo why not?"* (2026-11-05, :617-626): a concentrated seed on a primed node is a combo, bounded only by the pricing knob.

## Forks

**1. Is the concentrate an intake-row `LoadUse` that reshapes the cast?**
Restated: does an Ice load on a spell run as a bespoke `shape` use on the spell's Ice intake row? Such a use would lower `max_hops` (and, for some spells, `max_visits`) before the walk, and pay the seed.
- (a) **A `ConcentrateUse` on the Ice row.** It is a new `LoadUse` subclass, ADR 0070's open set (`attack/spell/load_use/`). Its `spend` writes a hop cut and a seed multiplier into the `LoadBag`. `SpellResolver` reads the bag once at cast: `hops_remaining = max(0, max_hops − cut)` (set raw at `spell_resolver.gd:185` today), and the seed arrival's whole payload scales through the same payload-scale path as #{resolver}'s share. The data per spell is `landings_at_hops`, L(0) = 1, taken from the measured ladder (:561-568). A spell whose walk cannot be priced (`max_hops = inf` with uncapped visits) authors `affinity_gain = 0`, which is today's refusal (`infusion.gd:59-67`). A `max_visits` variant is a second subclass, built when a spell needs it. **Tentative pick**: it is the shape the owner's *"some resource?"* describes, and the Cold spell assumes it.
- (b) **A spell-level field instead of a row use.** It would be a `SpellDef` (or `PropagationConfig`) export that reads the cast's `ice` load directly, the way `FuelBlastReach` reads `ctx.load`. That means no new `LoadUse`, but the price sits off the row the forge budgets, and "one row type, two uses" (:592-600) is lost.
- (c) **Keep the ×1 stub permanently.** On a cast, Ice is only a Cold ride. A spell gains no hop trade, and the Cold spell #1789 needs another signature.

**2. How does the price land on the seed when hops remain?**
Restated: H is the authored hop count and h is the count after the cut. The doc gives two formulas. They agree at h = 0 and diverge in between.
- (a) **Multiplicative: seed × L(H)/L(h).** Each removed hop multiplies the seed by its own ratio (:580-584, the owner's *"leaning 1"*). The total payload shrinks when hops remain. **Tentative pick**, because it is the owner's lean.
- (b) **Additive: seed × (1 + L(H) − L(h)).** "Pays the mass beyond the new limit onto the seed" (:610-611). The total payload is conserved at every cut.
- Arithmetic (Pestilence, `max_hops = 6`, visits ≤ 2, L = 1, 4.0, 11.9, 24.4, 40.9, 60.8, 84.6):
  - Going 6 → 0 gives ~84× under both formulas.
  - Going 6 → 3 gives ×3.5 under (a) (84.6 / 24.4) and ×61 under (b) (1 + 84.6 − 24.4).
  - At 6 → 3, (a) leaves a cast worth ~27 landings in total and (b) keeps ~84.
  - `elements.md:624-625` says "from 4 hops to 0", but Pestilence has 6 (`pestilence.tres:40`), and 84.6 is the table's 6-hop row. Fix the line when this settles.

**3. Which way does the affinity read? (a number, settled alongside 1 and 2)**
The house convention is gain:cost (`aspect-cell-authoring.md:206`, "venom has 2:1 poison affinity"). Read that way, "Venom Burst 2:1" cuts 2 hops per Ice point, and Venom Burst has only 2 hops. :582-583 says the affinity "absorbs counts of 20–50", which reads it as 2 Ice per hop (gain 1, cost 2).
- (a) **Ice per hop**: Venom Burst 2 Ice/hop, Pestilence 4 Ice/hop. **Tentative pick.**
- (b) **Hops per Ice point**, the literal house convention.

## The look (when built)
The forge's concentrate preview: "N hops → M, seed ×X" as the Ice load changes, with why a spell refuses Ice. #{forge-ui} no longer carries it, so it returns with whichever unit builds fork 1. The look may be handed to a sub-agent working in that unit's worktree once the hook it draws from (signal, record field, scene stub) exists; the unit's drone stays the owner and reviewer of the result.

## Notes
- No tension with the `max_hops` ruling (owner, 2026-09-02, `spell-propagation.md:444-473`, no stat scaling of propagation hops): the concentrate only lowers hops, per spell, authored.
- `elements.md:1049-1051` ties the per-spell numbers to #1444 (Frostbite). Nothing in Frostbite's scope prices a spell, so this is likely stale.
- The Frozen vertex's snap is a blade concentrate (#{ice}), not this.

```drift-stamp bd800181
docs/design/elements.md:538-627 — Ice on a cast: owner quotes, hop ladder, pricing lean, authored mass, combo
docs/design/elements.md:362-389 — the forge: ride and shape uses, one element per cast
docs/design/elements.md:1049-1076 — Ice pricing as a lean; the Cold spell (#1789)
attack/spell/infusion.gd:46-77 — intake_of, ratio_of (gain 0 refuses), gained
attack/spell/infusion.gd:90-142 — load_of, use_of, bag: where a use's spend enters the cast
attack/spell/load_use/load_use.gd:1-27 — the abstract use
attack/spell/spell_resolver.gd:140-190 — bag read once per cast; seed hops_remaining = max_hops raw (:185)
attack/spell/propagation/propagation_config.gd:36-50 — max_hops, max_visits_per_node
docs/domain/spell-propagation.md:444-473 — max_hops takes no stat scaling
docs/domain/aspect-cell-authoring.md:205-216 — affinity convention gain:cost; the LoadUse set
attack/spell/defs/pestilence.tres — seam: max_hops 6, visits 2
attack/spell/defs/venom_burst.tres — seam: max_hops 2, visits 1
```
