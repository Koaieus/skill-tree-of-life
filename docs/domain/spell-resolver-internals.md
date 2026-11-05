# Spell resolver and Cyclone — module internals

Per-class contracts for `SpellResolver` and `CycloneSpread`. The pipeline is in `spell-propagation.md`.

## CycloneSpread: the curl

`CycloneSpread` ranks the filtered candidates by the turn the front makes to
reach them, measured from the edge it arrived on in one fixed rotational
direction, and picks one child per rank carrying a decaying share of the
incoming damage. The share rides the `PropagationPick`; `PropagationConfig.mint`
is where the damage is split.

- **The whole spell is three numbers.** Rank 1 is the sharpest turn (it hugs
  the face the front circles); ranks 2 and 3 are wider turns that radiate
  outward. Coefficients whose sum exceeds 1 while each is individually below 1
  make the storm: energy grows globally, decays per thread, and concentrates
  only where geometry folds threads back together. Nothing detects a cycle; it
  is what a weighted walk on a planar graph does.
- **Authoring condition `c_1 < 1 < sum(c_r)`.** As a linear operator on directed
  edges, growth per wave is its spectral radius: `rho(any lone ring) = c_1`
  regardless of length or parity, `rho(dense triangulated) -> sum(c_r)`. A lone
  ring cannot sustain itself, a triangulated patch can. Measured: every tree
  0.000, every lone ring (triangle through hexagon) 0.650, a hex wheel 1.159, a
  37-node triangular lattice 1.326. The spell types terrain by "is it
  two-dimensional", not "is it cyclic".
- **A ranked fan, not a face-trace.** Taking only rank 1 is the next-edge
  permutation whose orbits are the embedding's faces; that necessarily assigns
  one arm to the outer face, so a triangle reads as two arms colliding rather
  than one storm turning. Verified on a hex wheel: all six arms off the hub
  trace same-signed faces (they co-rotate).
- **Closing a loop boosts the coefficient** (`closing_gain`) rather than merely
  lighting `CycleCondition`. The crit is sparkle on the landing; the gain feeds
  forward, so a ring that closes gets sustain and a lone triangle is worth
  killing over instead of fizzling at `c_1` per hop (owner call, 2026-09-01).
- Every knob is an export because the owner tunes them live; the spell
  playground re-reads spread exports on each Cast (`playground_panel.gd`).

## SpellResolver: the walk lands each wave

`SpellResolver` is pure resolution: it produces an `AttackOutcome` for a
`SpellDef` seeded at `target` from `source` by `caster`, using `graph` for
topology. Each iteration processes a whole frontier so the `IncidentReducer` can
collapse simultaneous arrivals at a node before any `OnHitEffect` fires, which
makes self-loops and diamond convergence a first-class mechanic (see Resonator).

- **The walk mutates the world it is handed, never the real one.** Each wave is
  landed through `OutcomeApplier.land_one` (the landing every other path uses)
  between "reduce incidents" and "expand next wave", so wave N+1's
  `PropagationFilter` selects against a world in which wave N's kills already
  happened. Filters that pick the next hop (`OwnerFilter`, `ExpressionFilter` via
  `to_owned_by_caster` / `to_unallocated`) read ownership, and a spell must not
  propagate back into a node this same cast just killed. Landing rather than a
  resolve-local "who died" ledger is deliberate: a ledger is a second
  implementation of death, cannot see `Mitigation` or a forced-dealloc cascade,
  and a gate that disagrees with the real applier is the drift
  `attack-timeline.md` exists to prevent.
- **`world` must be a shadow, and callers get one by default** (owner call
  2026-08-23, "shadow always"). `resolve` mints a throwaway `CombatWorld.shadow`
  and frees it, which is what the preview callers (SpellTooltip, the spell
  playground, the balance harness, the AI's magic candidates) want: they ask
  what a spell would do, with no real/preview flag anywhere. The authority's
  launch path resolves against a shadow too, then replays its own record on the
  live world as a peer does, which leaves `OutcomeApplier` the sole mutator of
  the real world (`BattleSystem.apply_launch_command`).
- The VFX layer is a pure observer that replays what already landed; the
  coordinator does not apply damage on projectile arrival.
