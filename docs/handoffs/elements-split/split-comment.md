## Split (owner, 2026-11-10)

The design is settled: ADR 0072, 0075, 0081, 0082, 0083, 0084, 0085 and `docs/design/elements.md`. This hub keeps the problem and the DAG; every unit of work is a child below, each with its own Acceptance spec.

**The spine, in order**
- #{defs} — element counts, the `Element` def and its bands, Heat / Cold / Charge
- #{terrain} — terrain as node state (blocked by #{defs})
- #{flow} — the world-turn settle: diffusion, decay (blocked by #{terrain})
- #{terrain-ui} — bars, labels, tooltip, glow (blocked by #{terrain}, #{flow})
- #{applier} — the applier drains a worklist; no behaviour change
- #{resolver} — the land-time gather (blocked by #{defs}, #{terrain}, #{flow}, #{applier})
- #{go-off-zero} — today's detonation ported onto the gather (blocked by #{resolver})
- #{burning} — Heat's ride row and Burning's disc (blocked by #{go-off-zero})
- #{catalyst} — Explosive retagged as Catalyst (blocked by #{burning})
- #{catalyst-blade} — the blade's explosive path removed (blocked by #{catalyst})

**The gate**
- #{refresh} — re-cut the late specs against the new master; board only (blocked by #{catalyst-blade})

**The late units**
- #{blade-elements} — element addons, vertex copy-on-fill, sweep speed (blocked by #{refresh})
- #{fire}, #{lightning}, #{ice} — in parallel (each blocked by #{blade-elements})
- #{pairs}, #{forge}, #{quiver} — (each blocked by #{fire}, #{lightning}, #{ice})
- #{forge-ui} — (blocked by #{forge}, #{quiver}, #{terrain-ui})
- #{cast-shapes} — Fire's disc and Lightning levels on a cast (blocked by #{forge}, #{forge-ui}, #{pairs})
- #{ice-cast} — Ice on a cast, the concentrate (blocked by #{forge}, #{forge-ui}, #{ice})
- #{overqualified-casting} — the point cap grows with the caster node's degree, the loadout gates the caster (blocked by #{forge}, #{forge-ui})

**Owner calls behind the cut** (2026-11-10): pair rules are their own unit — *"option 1. or whichever fits a DAG."*; small looks ride their mechanics unit and a large display surface is its own unit — *"option 1"*; every child is `Ready` with one spec-refresh issue gating the late ones — *"all children ready, but add 1 extra issue … make it be blocking later ones. and that issue just tells to update the specs?"*

**Siblings, not children:** #{inner-tree} (the inner-tree shape for elements and the card cadence, Needs design); #{adr-fixes} (corrections to ADR 0081 §1, §3, §5, §6, §7, §9, 0082, 0061, 0062, 0070); #1787 generator keystones; #1786 melee crit condition; #1789 the Cold spell; #1444 Frostbite, blocked by #{ice}.

**Closed into the units:** #1733 and #1735 into #{resolver} / #{go-off-zero}; #1765 into #{quiver}; #1660, #1695, #1696 into #{burning}, #{fire} and #{flow}.

**Still open, blocking nothing:** overflow-band decay 2 / 3 / proportional (a knob in #{defs}; owner: *"idk yet"*).
