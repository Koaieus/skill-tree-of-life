# Handoff: Explosive row design, the arming order (2026-10-13)

**State.** Written against the commit that adds this file, on top of `d37fe17`.
Authoritative: `docs/design/aspect_matrix.md` § Explosive (the design, in the
owner's words, plus the rejected branches) and the issues below. This file
only indexes them.

## Open forks, take in this order

1. **The arming order** (#1594, the charge status; it gates #1398 and #1400).
   Today's spec says a hit on a charged node *sets it off first, then lands its
   riders*. With `explosive_stacks_per_hit` = 1, three explosive arrows therefore
   leave **one** charge, because each one spends a charge and replants. The
   owner's worry: prepping a volley's splash takes 2+ stacks per hit, a knob gate.
   - **A. "Hits whose only rider is explosive arm and never fire."** This
     is the owner's narrowing of the advisor's "explosive arms, everything else
     fires". Arrows carry 0–1 riders, so it is exact for ranged. Blades and spells
     with several riders still fire and plant. "A blast never plants" then
     mostly follows from it.
   - **B. An explosive hit on a charged node sets off every charge at once, then
     plants fresh.** A bigger boom for more stacks. The owner's catch: arrows put
     in front of a poison volley would cash the big stack in as one riderless
     boom.
   - **C.** A cluster-grenade arrow type that *does* reapply, as a later
     exception on top of A.

   **Couplings:** whatever wins, rewrite #1594 (the decision line, acceptance 1
   and 2), #1398 (acceptance 1) and the "Chains" bullet in § Explosive. Then put
   #1594, #1398 and #1400 back in Ready. #1595 (blade contacts) is unaffected.
2. **Firecracker's built-in explosive** (#1400). Should a spell's innate load
   plant charges? Innate and infused explosive share the same machinery
   (ADR 0047). Firecracker's innate 6 would plant 6 charges on every node it
   visits. The owner floated *"applies *and detonates* on each hit"*, then saw
   the bounce-back arithmetic break (apply 6, jump away at 5, return and apply
   4, so the node holds 10). Options seen: only infused explosive plants; innate
   plants too and gets retuned down; neither plants (infusion only shapes the
   spell).
3. **#1466 (infusion: plant or blast).** The owner leans toward planting and
   says infusion *"may do anything we want"*. It closes once 1 and 2 are
   settled. If planting wins, the issue closes with no work.

## Ready to dispatch

- #1592 (blast bed) → #1595 (blade contacts) is blocked by #1594, so it is
  effectively parked.
- #1399 (barrel addon) and #1596 (Flamestrike) are blocked by #1594, and
  #1596 also by #1593.
- `aspects/defs/explosive.tres` is shared by #1594, #1398, #1399, #1400 and
  #1596; #1594 lands first.

## Live numbers

- `blast_radius` base 128 px (a stake-1 node is 32 px), ceiling 512 (#1592).
- Shrapnel 0.5 of raw; the warhead blast's scale 0.5; the death blast 2 per
  charge (tentative); decay −1 at end of turn, refill at turn start.

Delete this file once #1594 is back in Ready with the arming order settled and
#1466 is closed or specced.
