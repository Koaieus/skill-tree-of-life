# Explosive grammar — axis two (whose side a blast hurts) — continuation

**State.** Written against the commit that lands this file. Authoritative:
`docs/design/aspect_matrix.md` § Explosive (owner, 2026-10-14), ADR 0061,
issue #1608 (child of hub #1211, lane `Intake`). This file only points.

Axis one is settled and recorded there: three faces on the intake row
(DETONATE default / PLANT / FUEL), the spend/power formula
(`power = present + load + 2·min(load, present)`, a spark spends one, a loaded
hit spends `max(1, shared)`), a blast replicates the hit under the landing's
mask and never plants.

**Open forks, in the order worth taking** (all written as a menu on #1608):

1. **Whose side a blast's payload hurts.** Side-blind shrapnel with masked
   riders ("the bomb is the node"; prices self-mining; friendly fire on
   borders) vs the landing's mask filtering everything (what ships for
   projectiles; the heal circle under an ally mask makes this one attractive).
   Coupling: the second reading keeps the barrel asymmetry (an uncharged blade
   on a charged node pops blade pieces and spares the defender's neighbours);
   the first removes it.
2. **A blade contact's load — settled** (owner, 2026-10-14, on #1608 and in
   aspect_matrix): a contact is a DETONATE hit with load = the piece's whole
   count through the one formula; each reservoir pays its own spend.
   Remaining check: the piece spends exactly 1 per contact, or
   `max(1, shared)` like the node (what the code ships). Differs only on a
   struck node holding 2+.
3. **Blade chains.** aspect_matrix still says a blade's blast does not set off
   board charges, which sits oddly beside "a blast is a zero-load hit on each
   neighbour". Confirm or delete that sentence when fork 1 lands.
4. **"Both" from one heal** (plant and heal-circle on one cast): the pass
   proposed two list entries priced by affinity instead of a third face; the
   owner asked the question and never ruled. On #1608's menu.
5. **Death blast** (#1604) is untouched by axis one.

**Then:** fold the axis-two answers into aspect_matrix.md and #1608, and run
`/spec` on #1608 to split it into drone-sized children (intake-row enum +
effects list; ammo → PLANT; blast payload generalised; resonance knob;
delete the explosive-only exception and its tests).

**Delete this file** once axis two is recorded in aspect_matrix.md and #1608
has moved out of `Intake`.
