# Elements split — tentative readings the bodies carry (for the owner)

Each line is a reading a body carries, marked "(tentative, not the owner's)" in that body. If you accept the list, each stays as written. Name any line you reject.

## Whole-hit call (2026-11-10, night)
- go-off-zero / resolver: go-off zero (today's explosive, ported) is exempt from whole-hit until the Catalyst retag: share authored at 0.5, no centre copy (`GoOff.lands_on_own_node` = false on its disc, true by default). Keeps the shipped tests green. The alternative, following whole-hit now, re-points `test_explosive_charges` "never the centre", `test_blast_mark` "the centre's own hits carry no mark" and `test_heal_spell_blast`'s `[n[2]]`, and doubles bystander damage.
- Open by design: Frozen's shatter tuned to match the doubling. Carried as a knob.
- resolver / pairs: with `dedupe_dual_reach` on, the hit node's centre copies merge too (3 → 2).
- resolver / burning: the centre copy also takes the go-off's own damage.
- resolver: two channels with different shares reaching one node: the larger share's terrain rider lands.
- resolver: a copy's load is 0.
- resolver / lightning: the spend and Charge transfer count nodes already visited this hit. A transferred stack is spend, not a terrain rider, so the once-per-node cap does not bound it. The centre landing costs no Charge and transfers none.
- pairs: Charge an arc transfers to a Frozen neighbour that absorbs the copy is lost.
- pairs / ice: the centre landing is a copy to `admits` (the two agree at share 1).
- ice / ice-cast: Frozen has no go-off and is not a channel. A break adds the burst, not a landing, and a concentrated seed lands on a Frozen node once.
- lightning: a Shocked blade vertex's unprimed contact node takes 2 landings.
- cast-shapes: a shape added into a primed node's same-element go-off is that node's one channel, so the seed takes 2. Under the Frozen mute the shape runs alone and the seed takes 1; once the hit breaks the ice, the shape adds into the released go-off.
- catalyst: the goo arrow plants Catalyst on its own node via the centre landing.

## Go-off, reach, resolver
- go-off-zero: a mask-excluded charged node inside the disc does not chain, as today (0084 §7 is silent).
- resolver: the blast mark names its `GoOff` by the holding band's `Identity`, in a new record column. A shape's reach with no band behind it names the `GoOff` that answered it (cast-shapes).
- resolver: the gather never ends a chain by itself; the absorb and the pairs mute do.
- lightning / burning: past the cap a node reads the overflow band, which has no go-off and no travel verb, so it neither arcs nor conducts (Burning has the same hole). Carried as an open NOTES line.
- burning: an element row with `plants` unset defaults to Fire's terrain (Heat). This is undefined once Frostbite lands (#1444).
- burning: who builds the walk over two rows of one concept.
- pairs: what an arc released by a blade's weight-break carries is not pinned.

## Ice
- ice: an arrival that shatters the ice still ends its walk (0083 is silent).
- ice: the shatter's burst rides `Admits`' second answer and lands in stage two.
- ice: a Frozen node with no holder: the flat breaker does not apply. The alternative is the `node_health` default; `get_max_hp()` reads 0 on a never-owned node.
- ice: breaking one copy lets no under-threshold copy through in the same generation, and a node breaks at most once per hit.
- ice: the blade's weight is read from `{blade-elements}`' go-off-source argument.
- ice-cast: the multiplier rides the whole shortened walk, not only the seed landing. A later hop that lands on a primed node takes ×m once plus once per channel going off there.
- ice-cast: a spell with no authored Ice row concentrates at the default.

## Cast shapes
- cast-shapes: a multi-seed cast shapes every seed. The Fire shape reads the seed node's radius. The disc's own damage reads excess only, not shape points. The Frozen mute does not drop a cast's shape.
- cast-shapes: the range preview draws only the shape's own reach, from the pure functions, with no add-up and no go-offs.

## Forge, overqualified casting
- forge: the order `clamp_infusion` trims in. Two owner quotes the doc no longer holds were dropped ("×1 stub", "every entity"); the rules are kept unquoted.
- forge: shape points don't count against the cap; a count is shared by shape and ride; the exchange rate (these were "pass pick, tentative" already).
- overqualified-casting: with no target picked, sockets fill to the best capacity among eligible casters. Reset-to-base is a one-shot trim, not sticky. An aimed spell refuses the extra point rather than re-pick its source. The AI fills to its own source's cap. It is filed as one unit behind forge-ui; the non-UI part could be split off (seam in its NOTES).

## Terrain, flow, catalyst
- flow: decay below the first band: § Cooling says only "decays 1 toward zero per world turn", so the below-band rate is 1, `Element.decay_per_world_turn` from `{defs}`.
- catalyst: a "round" is one holder turn end on a one-carrier board, which closes one world turn. Catalyst loses no more than the Fire band's decay rate per cycle.
- catalyst: old saves are refused, as with versions 11 to 13.
- catalyst: a payload with zero or two element riders converts nothing.
- catalyst: in the interim, a blade's charged contacts still spend and pop but arm no blast.

## Records and doc asks
- adr-fixes: the body keeps three corrections that § 000's list does not name, because 0083-0085 do not carry them: 0081 §3 (the blade weight gate has no ADR), 0081 §7 (an arrow is an aspect subtype or an element, never both) and 0081 §1 (own go-off fires once per hit). The alternative is a new ADR for the weight gate.
- defs: `aspect_matrix.md:34` still says "side-less terrain, gives reach" and has no `## Element Matrix` heading; those doc asks stay in the defs body.
- pairs: the pair table's "for the next landing" contradicts ADR 0083 §1 for a rider. That is a doc fix in `elements.md`.

## Still open by design (untouched)
Shape points against the capacity; the hops-cut → shatter knob; the Fire multiplier (5); the "at least 1" solo cost.
