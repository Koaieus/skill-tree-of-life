Lightning, beside Fire after the spine: Charge becomes Shocked past T, Shocked arcs to every neighbour (further on the L² × T ladder), a spell walk conducts through a Shocked node, the Charge blade addon and the Shocked vertex. Child of the #1716 hub; design home `docs/design/elements.md`. `lightning_bolt` keeps its name (owner, 2026-11-10: "(a) Keep the name lightning_bolt for now"); its innate Charge row is #{forge}, not this unit.

Blocked by: #{blade-elements}
Blocks: #{pairs}, #{forge}, #{quiver}

## Acceptance spec

**Decisions**
- *Shocked*, a hit on it: "arcs to **every** neighbour (owner: *"it will arc to *all its neighbors* each time it is hit"*)"; also "conducts a spell walk" (`docs/design/elements.md:73-76`, § The threshold model, owner 2026-11-08).
- Spend: "Shocked 1 per neighbour struck" (owner, 2026-11-08: *"charge is more travel-across-edges-ey"*); the spend digs under T: "a degree-4 node at 9 Charge arcs all four neighbours at cost 4 and drops to 5 — *"would decharge more rapidly"*" (`:79-93`).
- The ladder: "level L at count > L² × T (owner: *"T = 1 hop, 4T = 2 hops, 9T = 3 hops"*)" (`:110-113`).
- Atomic 3 (owner, 2026-11-04): *"A Curse arrow hits a Charged (lightning) node and it applies curse to the target *and* to 1..N neighbors"* (`:478-481`).
- Chains (owner, 2026-11-05): *"LET IT RIDE. The hit, all rider, no decay. Maybe raise you: for charge arcs hitting charged nodes also just keep arcing (and consuming a stack ofc) and concatenating hits."* (`:489-496`).
- A Charge rider on an arc copy replants `ceil(r × s) ≥ 1` on every node reached, a wire that re-lays itself (owner, 2026-11-05: *"Leaning 2. My reasoning: if buildup is too strong we can always tune up decay rates/mechanisms"*) (`:512-523`).
- Travel (owner, 2026-11-06: *"picture A sounds very good. also in some sense: elec - hops -> 1D (lines)"*): Shocked "a path **conducts**: a spell walk entering a Shocked node leaves it without spending a hop — a line of Shocked nodes is a wire for anyone's magic", spending "one Charge per pass-through"; side-less; rejected for v1: "Shocked self-discharging on the tick" (`:884-899`).
- **Charge stays put** (owner, 2026-11-08: *"charge staying put sounds good"*) (`:964-967`). The edge subclass is the Shocked `GoOff`; no `ArcEffect` exists (owner, 2026-11-09, `:734-747`).
- Blade: *"copy shocked node -> get shocked blade node (zaps/arcs)"* (owner, 2026-11-09): a Shocked vertex arcs from the node it touches; a vertex go-off spends the copy, never the source (`:425-440`).
- Dual reach (owner, 2026-11-10: *"riders twice, payload twice. charged burning nodes sounds like a dangerous concept"*): a node both Burning and Shocked blasts and arcs; a node reached by the disc and an arc is two entries, each landing every rider and the damage at its share. Each go-off fires once per hit (owner, 2026-11-10), through the once-per-node set; the dedupe stays a one-line switch (`:770-781`).
- **An arc moves its Charge, it does not void it** (ADR 0084 §7, falling 0081 §1's void for a Shocked arc; owner, 2026-11-10: *"knob, transfer by default"*, reasoning: *"decay is 1 per charged node. if it voids 4, they are gone. if it spreads them to 0 charge nodes, they are gone by next tick. if more charge is at play, more things can happen, chain effects, priming mid hit or after, all reads as *very* STATIC DISCHARGE i must say"*; `:945-962`). The go-off still pays 1 per node reached; each spent stack lands on the node it reached, +1 there in the same commit as the -1 on the source. Pass readings, tentative: the conduct cost of a pass-through is still voided; a transferred stack is treated exactly like the Charge rider an arc copy lands (same commit, same primed-ness read); Burning and Frozen keep the void.
- **An arc's reach is shape-blind at every level** (ADR 0084 §7; owner, 2026-11-10: *"option 1"*, then *"so far just keep it shape blind always"*; `:532-542`): every node within L hops over the whole graph, allocated or not, whoever holds it, so transferred Charge lands on empty ground too. Parked by the same answer, not built: *"allocated only at lv1, whole graph at lv 2+"* for Fire and Lightning together.
- **Riders first** (ADR 0083 §1, §5): at a node the Charge riders land, then the node's Shocked state and its level are read from the result, so the hit whose Charge rider tips the node over T sets it off itself; same-beat hits read the beat's summed terrain. Every "Shocked" and "count" in this body is that post-land read.
- **The arc's entry point takes a level as a parameter** (ADR 0084 §3, §4): a cast's Lightning shape level N adds to the node's own level M into one go-off at level N+M, not two. This unit only keeps the entry point level-taking (own level from the post-land count by default, a caller may pass a higher one); the cast-shapes unit `{cast-shapes}` builds the feed, and owns shape levels and their cost (1+2+…+N points, ADR 0084 §1). The combined go-off pays the node's solo cost (what its own go-off would have spent, ADR 0084 §4).
- The vertex's copied state reaches the gather as a "go-off source" argument (pass pick, tentative; kept 2026-11-10). Spec-time readings this child owns (`:457-458`), pass picks, tentative: the arc excludes its centre and reads L off the post-land count; a Shocked vertex's level comes from its copy against its source node's T, centred on the contact's node, spending the copy 1 per node reached.
- Conduction at 0 hops (owner, 2026-11-10: *"i forgot i designed that as a feature. it's rather powerful, not spending a hop. but might be just what it needs"*, and on keeping it including the 0-hops case: *"i agree with that lean."*): a walk arriving on a Shocked node with 0 hops left still leaves, for the conduct cost.
- Conduction, pass picks, tentative (the spend at the gather head kept 2026-11-10; the only shape that keeps "a gather hit at span head is the only terrain writer", `:684-693`): the pass-through Charge is spent at the arriving wave's gather head when the walk has a spread; Shocked is read from the beat's summed terrain after the riders land (ADR 0083 §5); the wave minted out of that node keeps its parent's `hops_remaining`, so an arrival with 0 hops left on a Shocked node still leaves (the owner call above, not tentative). `max_visits_per_node` still bounds a wire ring. `max_hops` itself is never modified (no stat scaling, `docs/domain/spell-propagation.md:444-473`).

**Knobs** (tentative defaults — easy to change; tests assert ratios)
- Lightning's edge `GoOff` (#{resolver}'s edge subclass) `.ladder_exponent` = 2 (`@export_range(1, 4)`) — level L at count > L^exp × T (owner's L²).
- the same `GoOff` `.max_level` = 3 (`@export_range(1, 6)`) — a ceiling on the level read from the node's own count (a level passed in by a caller is the caller's, `{cast-shapes}`); the k × T cap already bounds it (k ≤ 5 gives L ≤ 2) so this only guards overflow.
- the same `GoOff` `.spent_charge_goes_to` (`@export_enum("Reached node", "Void")`) = Reached node (owner default): where each spent stack lands. Inspector on Lightning's `Element` def; the blast sandbox tab shows a wire holding or draining.
- the same `GoOff` `.share` = 0.5 — #{resolver}'s one-share knob, Lightning's own instance.
- Lightning's Shocked band `.conduct_cost` = 1 (`@export_range(0, 5)`) — Charge per pass-through.
- Charge addon `.stacks` = 1 — authored innate Charge per vertex (#{blade-elements}'s element addon base).
- Charge decays in #{flow}'s world-turn pass with Heat and Cold (owner, 2026-11-10, picked the world-turn pass over decay on read); no decay knob here.

**Composition**
- Lightning's `Element` def (#{defs}) owns Charge and its Shocked band; this unit fills the band: `go_off` = an edge `GoOff` instance, travel verb = conducts with `conduct_cost`. Shocked stays a pure function of `NodeState`'s Charge int and T (#{terrain}).
- #{resolver}'s gather asks the band to *go off*; the edge subclass answers the level, the reached set (one hop-bounded BFS, `GraphMirror.nodes_within` on the global mirror; never a per-candidate `in_range`), the spend (= reached count) and the share. Chains, concatenation and the once-per-node-per-hit set are the gather's, not Lightning's.
- Conduction: the spell walk reads the arrival node's band at the expansion step, from the beat's summed terrain after the riders land (ADR 0083 §5) (`spell_resolver.gd` § 4) and tells `PropagationConfig.mint` not to decrement; the gather head records the conduct spend with the arrival's other terrain changes for peers (ADR 0077). Nothing else learns about Shocked.
- `BladeVertexFill` (via #{blade-elements}'s generic copy) carries the Charge copy; at contact the vertex hands the gather its copy as the go-off source and the edge `GoOff` answers from it. The Charge addon is an element addon scene on #{blade-elements}'s base.
- Dies: nothing; Lightning adds an answer and an addon. Readers of the arc look: the attack record's blast table row for the go-off (#{resolver}'s mark), which names its `GoOff` so the VFX picks an arc layer instead of a disc.

**Files touched**
- Lightning's `Element` def and Shocked band `.tres` (created by #{defs}) — the answers above.
- `attack/spell/spell_resolver.gd` — the expansion step's terminal check reads conduction; `attack/spell/propagation/propagation_config.gd` — `mint` keeps `hops_remaining` on a conducting parent.
- `skill_node/addons/defs/charge_addon.tscn` (new) and a visual under `skill_node/addons/visuals/` (new).
- `ui/vfx/` — an arc layer drawn per hop on top of edges (the `EdgeEnergize` rule: paint on top, never touch `Edge`); `ui/vfx/blast_vfx.gd` routes an edge go-off's mark to it (shared seam with #{fire}).
- `docs/domain/spell-propagation.md` — a conduction paragraph beside `max_hops`; the elements domain doc #{defs} opens — Lightning's section.

**Acceptance**
1. `test/unit/elements/test_shocked_go_off.gd` (red first): a hit whose Charge, after its own Charge rider lands, is > T copies its payload to every neighbour at `share`, spends 1 Charge per neighbour struck and may land under T; a hit that leaves Charge ≤ T lands plainly (no copy, no spend); a hit whose rider tips a node from T to T+1 sets it off at once (ADR 0083 §1). With the transfer default the source nets -N and each reached node +1 in one commit, an unallocated neighbour included; an interior node of a line wire whose two neighbours arc back nets 0; with the knob on Void no reached node gains.
2. Same file, the ladder: at count > 4T (with `ladder_exponent` 2) the reach is every node within 2 hops, spend = that count; a ratio test across two levels, never the literal default.
2a. Same file, the entry point: called with an extra level N on a node at level M it returns the reached set of level N+M as one go-off (one entry per reached node, not two), spending the node's solo cost for level M; with N = 0 it equals the plain call.
3. Same file, chains and the wire: a copy on a Shocked neighbour arcs in turn, once per node per hit; a hit carrying Charge re-lays `ceil(r × share) ≥ 1` Charge on every node it reached; a Curse rider lands on target and neighbours (atomic 3).
4. `test/unit/spell/test_shocked_conduction.gd`: a hop spell walking a line A–B–C–D with B and C Shocked reaches further than the same walk unshocked by exactly the Shocked count; each pass-through spends `conduct_cost` Charge; a walk arriving on a Shocked node with 0 hops left still leaves, for the conduct cost (owner, 2026-11-10); a ring of Shocked nodes terminates (visit cap); a spread-less spell spends nothing.
5. Conduction and the arc both fire on one spell arrival on a Shocked node and their spends sum in one settle (one snapshot per beat). A node both Burning and Shocked, hit once, blasts (#{burning}'s disc) and arcs once each; a node inside the disc that an arc also reaches takes two entries, each with every rider and the damage.
6. Determinism: the same cast resolved on a shadow world and on live reaches the same set and spends the same Charge (re-use the attack-determinism harness, `test/unit/attack/test_attack_determinism.gd`).
7. `test/unit/attack/melee/test_shocked_vertex.gd`: a vertex filled from a Shocked source arcs from its contact node at the copy's level; the source node's Charge is unchanged; the copy is spent per node reached; once the copy drops to the source's T the vertex stops arcing.
8. Charge addon: its vertex lands `stacks` Charge on every contact it lands, that vertex only; a refused contact lands nothing.
9. Visible: an arc per hop on the board from the centre to each reached node, in Lightning's colour, readable as distinct from a Burning disc; a conducting walk shows the wire carrying it and the Charge spent per pass-through (the node's bar drops); the Charge addon and a Shocked vertex read as charged. Sandbox host, `mise run check` only.

**NOTES**
- The transfer reverses ADR 0081 §1's rejected "radiating transfer" for arcs only; ADR 0084 §7 carries it. Write no ADR here.
- The look may be handed to a sub-agent working in this same worktree once the hook it draws from (signal, record field, scene stub) exists; the unit's drone stays the owner and reviewer of the result.
- Reading list and seam map were cut before #{defs}…#{catalyst} landed; #{refresh} re-cuts the stamp. If `mise run issue-drift` still flags this issue at dispatch, stop and say so.
- Parked, not built: **a wire evens itself out** (a Shocked run sharing Charge each world turn, `:1133-1135`); the **arc mirror** (owner, 2026-11-05: *"maybe when a nb tries to emit a lightning reach it reflects it? maybe not"*; a blanket reflect rejected, `:1136-1141`) — a Frozen neighbour is simply struck here, and what Frozen does to an arriving arc is #{pairs}.
- Frozen mutes Shocked / the break releases the storm and Frozen ends an arc are #{pairs}; the dual-reach entries themselves are #{resolver}'s gather (its dual-reach acceptance; Acceptance 5 here only pins Lightning's side). The Shocked "crackle" revealing charged nodes is parked as minor (`:904-907`).
- The no-parent go-off ("terrain hit", `:498-503`) has no caller; not built (the handoff's "lands with 6 and 7" is stale). Generator keystones (#1787) mint Charge without a hit and are their own issue.
- `lightning_bolt` gaining its innate Charge row: #{forge}. Charge arrows: #{quiver}; starter counts: #{forge}.
- Adversarial (f) — Charge colliding with explosive's `charge` tag and `vertex_charges` — is cleared by #{catalyst}; #{refresh} confirms neither name survives before this dispatches.

**Stubs on master** — none — shapes are named in Composition; the drone adds them.

```drift-stamp efba0bc3
docs/design/elements.md:70-113 — the trigger table, what a go-off pays, the hop ladder
docs/design/elements.md:418-458 — the element addon, vertex copy-on-fill, the spec-time vertex question
docs/design/elements.md:460-523 — the reach rule, chains concatenating, a copy carries Charge (the wire re-lays)
docs/design/elements.md:684-747 — the gather as the only terrain writer, one snapshot per beat, the edge subclass
docs/design/elements.md:770-784 — dual reach concatenated, the dedupe switch
docs/design/elements.md:857-907 — bands, the travel verb (a path conducts, one Charge per pass-through), the parked crackle
docs/design/elements.md:964-967 — Charge stays put
docs/design/elements.md:1133-1141 — the parked wire and arc mirror
graph/graph_mirror.gd:229-250 — nodes_within, the one hop-bounded BFS
attack/range_finder/hop_range_finder.gd:58-66 — gather over a mirror, not the per-candidate predicate
attack/spell/spell_resolver.gd:376-404 — the expansion step: terminal check on hops_remaining, then the visit cap
attack/spell/propagation/propagation_config.gd:99-124 — mint: where hops_remaining decrements
docs/domain/spell-propagation.md:444-473 — max_hops takes no stat scaling
attack/melee/blade_vertex_fill.gd:42-60 — the fill: a status copied per vertex, addons applied after
docs/domain/melee-blade-sim.md:416-425 — the Toxin rider-only addon pattern
attack/spell/spell_resolver.gd — seam: conduction in the expansion step
attack/spell/propagation/propagation_config.gd — seam: mint keeps hops on a conducting parent
graph/graph_mirror.gd — seam: nodes_within for the arc reach
ui/vfx/blast_vfx.gd — seam: routes a go-off mark to its layer
ui/vfx/projectile/visual/edge_energize.gd — seam: painting on top of an edge, the arc look's neighbour
attack/spell/on_hit/blast_mark.gd — seam: the record row an arc look reads
skill_node/addons/explosive_barrel_addon.gd — seam: apply_to_blade, the template for a blade-stack addon
skill_node/addons/defs/ — seam: the addon scenes the Charge addon joins
docs/domain/spell-propagation.md — seam: the conduction paragraph
test/unit/attack/test_attack_determinism.gd — seam: the determinism harness
```
