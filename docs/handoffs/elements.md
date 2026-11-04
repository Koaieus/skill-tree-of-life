# Handoff — elements design session (2026-11-03/04)

**State.** Written against the `claude/pensive-hamilton-ikyix7` branch (PR
#1739, on top of master `36e9eb3`). Authoritative: `docs/design/elements.md`
(the design) and the issues named below (the conversation). This file is a
map for the owner's fresh-eyes pass and the fold that follows; it goes once
both are done.

**What the session settled.** Elements are a second axis beside aspects (not
a parent of aspects, not a damage type); one count per element plus a status
family with fixed roles (medium / mover / state); start with one derived state
(Frozen). The roles table is owner-confirmed and persisted. Greed's "stacks
outlive the kill" direction on #1659 is called an exploit on paper (verified:
not an exploit *as built*, a node kill strips every row; the exploit is in the
settled-but-unbuilt direction).

## To confirm (owner, fresh eyes), in the order they unblock things

1. **The reach rule** — hit element + node medium set reach, payload copied at
   one share, medium spent, load not (`elements.md` § The reach rule). Unblocks
   #1733 round 3 and every element cell.
2. **The reach triad** — melee·STR·disc·Fire, ranged·DEX·point·Ice,
   magic·INT·path·Lightning, a school assignment that never scales
   (`elements.md` § The reach triad). Unblocks the inner-tree placement and
   `node_subtypes.md` supply.
3. **Greed** (#1659) — hot potato onto the killing node (pass pick), spent on
   kill (as built), or rides the relic (#1662). Coupling: picking hot potato
   keeps Greed sided and needs no new `on_dealloc` shape; picking "lingers on
   the ground" forces a third dealloc shape *and* reopens the re-kill exploit.
4. **"Heat" vs "Burn"** for Fire's mover (#1660 open item 4). The doc keeps
   Heat; the session floated Burn, then the owner moved Burning to a parked
   derived state, so Heat stands unless redirected.
5. **Payload ordering by group** — explore, not decide (`elements.md` § Open,
   last item). Couples with #1733 R1.
6. **Post the axis call on #1716** — done below as a one-line pointer; the
   full decision text waits on 1 and 2.

## Next unit: the fold (owner said one doc is the authority, 2026-11-04)

Pull the settled rules out of the five cell issues into one tight section per
element in `elements.md`, no round narrative; then one pointer line per cell
("design home: `docs/design/elements.md`; this issue is the build cell") and
make #1716 the hub (no work of its own, child list only). #1733's R1–R5 stay
on #1733 until settled.

| Element | Pull from | What is settled there |
|---|---|---|
| Fire | #1660 rounds 1–2, #1695, #1696 | `Aspect.statuses` plural (#1694, "A1 100%"); Metropolis flow ⌊(hᵢ−hⱼ)/(max(dᵢ,dⱼ)+1)⌋, snapshot then apply; unallocated sinks; ½ dmg/stack at turn end before emitting; always dies out; dealloc puts it out; death blasts pre-cooling; faces dissolve, ignition = state check heat>0 ∧ fuel>0 spending min(heat,fuel) |
| Ice | #1444 (+ `aspect_matrix.md` Frostbite row) | Frostbite pack hops one node per turn along the shortest owned path to the core, sheds on each node left, survivors hit core HP; Frozen = resting stacks ≥ T, the travel blocker; open: shed rule, through-Frozen, shatter magnitude; owner lean: fire thaws, melee shatters |
| Lightning | #1716 rounds 1–2, #1733 round 2 | chain not ball (max_hops untouched); a node discharges once per attack; arc k at d·f^k; Tesla leap to the most charged node within `radius_for(budget)`; `lightning_bolt.tres` renamed not reshaped; open: target pick (owner finds node-id tie-break weak), Charge decay |

Under the new vocabulary two things in those issues change wording, not
substance: Fire's count moves from the `aspects` family to an `elements`
family (`fire`, not `fire_aspect`), and ignition becomes one blast trigger
among several (any non-planting hit on Fuel blasts).

## Read list for the fresh-eyes pass

- `docs/design/elements.md` — whole, ~150 lines.
- `docs/design/aspect_matrix.md` § Glossary (the two new rows), the Elemental
  family row (~line 557), § Schools harvest line (~line 619).
- #1716 body + comments of 2026-11-02 (rounds 1–2: the "not a second axis"
  proposal this session overturned, and the owner's verbatim element
  questions, which the roles table answers).
- #1659 body (Greed's settled direction and its own "possibly a feature" note).
- #1660 comments "Design beat, round 1" and "round 2" (Fire's locked rules).
- #1733 last comment (R1–R5 verdicts; R3 and R4 stand under the reach rule).
- Code, only if the dealloc seam comes up: `combat/status_host.gd:274-287`
  (`release_statuses`), `combat/entity_combat.gd:991-1003` (`strip_node`),
  `effects/status/status_def.gd:31-44` (`OnDealloc`). Doc/code mismatch found:
  `status_def.gd:35-37` says a bare `force_deallocate` keeps LINGER rows;
  `systems/allocation_system.gd:337` passes CAUSE_DEATH and releases them.

## Issues touched or to touch

#1716 (hub, pointer posted), #1659 (unpicked, nothing posted), #1660, #1694,
#1695, #1696, #1444, #1733 (another session's, leave its round alone),
#1707 (Fire's school now answered by the triad: STR), #1662 (Greed shape C).
Board lanes were unreadable from this cloud session (GraphQL blocked, #1736);
no status moved.
