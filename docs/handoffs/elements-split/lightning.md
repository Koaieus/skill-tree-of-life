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
- Travel (owner, 2026-11-06: *"picture A sounds very good. also in some sense: elec - hops -> 1D (lines)"*): Shocked "a path **conducts**: a spell walk entering a Shocked node leaves it without spending a hop — a line of Shocked nodes is a wire for anyone's magic", spending "one Charge per pass-through"; side-less; rejected for v1: "Shocked self-discharging on the tick" (`:850-865`).
- **Charge stays put** (owner, 2026-11-08: *"charge staying put sounds good"*) (`:911-914`). The edge subclass is the Shocked `GoOff`; no `ArcEffect` exists (owner, 2026-11-09, `:708-721`).
- Blade: *"copy shocked node -> get shocked blade node (zaps/arcs)"* (owner, 2026-11-09): a Shocked vertex arcs from the node it touches; a vertex go-off spends the copy, never the source (`:425-440`).
- Dual reach (owner, 2026-11-10: *"riders twice, payload twice. charged burning nodes sounds like a dangerous concept"*): a node both Burning and Shocked blasts and arcs; a node reached by the disc and an arc is two entries, each landing every rider and the damage at its share. Pass reading: each go-off fires at most once per hit (the once-per-node set); the dedupe stays a one-line switch (`:744-753`).
- The vertex's copied state reaches the gather as a "go-off source" argument (pass pick, tentative; kept 2026-11-10). Spec-time readings this child owns (`:457-458`), pass picks, tentative: an arc's reach is every node within L hops of the centre over the whole graph (side-less, not a territory mirror), centre excluded, L read off the post-land count; a Shocked vertex's level comes from its copy against its source node's T, centred on the contact's node, spending the copy 1 per node reached.
- Conduction at 0 hops (owner, 2026-11-10: *"i forgot i designed that as a feature. it's rather powerful, not spending a hop. but might be just what it needs"*, and on keeping it including the 0-hops case: *"i agree with that lean."*): a walk arriving on a Shocked node with 0 hops left still leaves, for the conduct cost.
- Conduction, pass picks, tentative (the spend at the gather head kept 2026-11-10; the only shape that keeps "a gather hit at span head is the only terrain writer", `:663-672`): the pass-through Charge is spent at the arriving wave's gather head when the walk has a spread; Shocked is read pre-beat; the wave minted out of that node keeps its parent's `hops_remaining`, so an arrival with 0 hops left on a Shocked node still leaves (the owner call above, not tentative). `max_visits_per_node` still bounds a wire ring. `max_hops` itself is never modified (no stat scaling, `docs/domain/spell-propagation.md:444-473`).

**Knobs** (tentative defaults — easy to change; tests assert ratios)
- Lightning's edge `GoOff` (#{resolver}'s edge subclass) `.ladder_exponent` = 2 (`@export_range(1, 4)`) — level L at count > L^exp × T (owner's L²).
- the same `GoOff` `.max_level` = 3 (`@export_range(1, 6)`) — a ceiling on L; the k × T cap already bounds it (k ≤ 5 gives L ≤ 2) so this only guards overflow.
- the same `GoOff` `.share` = 0.5 — #{resolver}'s one-share knob, Lightning's own instance.
- Lightning's Shocked band `.conduct_cost` = 1 (`@export_range(0, 5)`) — Charge per pass-through.
- Charge addon `.stacks` = 1 — authored innate Charge per vertex (#{blade-elements}'s element addon base).
- Charge decays in #{flow}'s world-turn pass with Heat and Cold (owner, 2026-11-10, picked "In the world-turn pass, with Heat/Cold"); no decay knob here.

**Composition**
- Lightning's `Element` def (#{defs}) owns Charge and its Shocked band; this unit fills the band: `go_off` = an edge `GoOff` instance, travel verb = conducts with `conduct_cost`. Shocked stays a pure function of `NodeState`'s Charge int and T (#{terrain}).
- #{resolver}'s gather asks the band to *go off*; the edge subclass answers the level, the reached set (one hop-bounded BFS, `GraphMirror.nodes_within` on the global mirror; never a per-candidate `in_range`), the spend (= reached count) and the share. Chains, concatenation and the once-per-node-per-hit set are the gather's, not Lightning's.
- Conduction: the spell walk reads the arrival node's pre-beat band at the expansion step (`spell_resolver.gd` § 4) and tells `PropagationConfig.mint` not to decrement; the gather head records the conduct spend with the arrival's other terrain changes for peers (ADR 0077). Nothing else learns about Shocked.
- `BladeVertexFill` (via #{blade-elements}'s generic copy) carries the Charge copy; at contact the vertex hands the gather its copy as the go-off source and the edge `GoOff` answers from it. The Charge addon is an element addon scene on #{blade-elements}'s base.
- Dies: nothing; Lightning adds an answer and an addon. Readers of the arc look: the attack record's blast table row for the go-off (#{resolver}'s mark), which names its `GoOff` so the VFX picks an arc layer instead of a disc.

**Files touched**
- Lightning's `Element` def and Shocked band `.tres` (created by #{defs}) — the answers above.
- `attack/spell/spell_resolver.gd` — the expansion step's terminal check reads conduction; `attack/spell/propagation/propagation_config.gd` — `mint` keeps `hops_remaining` on a conducting parent.
- `skill_node/addons/defs/charge_addon.tscn` (new) and a visual under `skill_node/addons/visuals/` (new).
- `ui/vfx/` — an arc layer drawn per hop on top of edges (the `EdgeEnergize` rule: paint on top, never touch `Edge`); `ui/vfx/blast_vfx.gd` routes an edge go-off's mark to it (shared seam with #{fire}).
- `docs/domain/spell-propagation.md` — a conduction paragraph beside `max_hops`; the elements domain doc #{defs} opens — Lightning's section.

**Acceptance**
1. `test/unit/elements/test_shocked_go_off.gd` (red first): a hit on a node with Charge > T copies its payload to every neighbour at `share`, spends 1 Charge per neighbour struck and may land under T; Charge ≤ T lands plainly (no copy, no spend).
2. Same file, the ladder: at count > 4T (with `ladder_exponent` 2) the reach is every node within 2 hops, spend = that count; a ratio test across two levels, never the literal default.
3. Same file, chains and the wire: a copy on a Shocked neighbour arcs in turn, once per node per hit; a hit carrying Charge re-lays `ceil(r × share) ≥ 1` Charge on every node it reached; a Curse rider lands on target and neighbours (atomic 3).
4. `test/unit/spell/test_shocked_conduction.gd`: a hop spell walking a line A–B–C–D with B and C Shocked reaches further than the same walk unshocked by exactly the Shocked count; each pass-through spends `conduct_cost` Charge; a walk arriving on a Shocked node with 0 hops left still leaves, for the conduct cost (owner, 2026-11-10); a ring of Shocked nodes terminates (visit cap); a spread-less spell spends nothing.
5. Conduction and the arc both fire on one spell arrival on a Shocked node and their spends sum in one settle (one snapshot per beat). A node both Burning and Shocked, hit once, blasts (#{burning}'s disc) and arcs once each; a node inside the disc that an arc also reaches takes two entries, each with every rider and the damage.
6. Determinism: the same cast resolved on a shadow world and on live reaches the same set and spends the same Charge (re-use the attack-determinism harness, `test/unit/attack/test_attack_determinism.gd`).
7. `test/unit/attack/melee/test_shocked_vertex.gd`: a vertex filled from a Shocked source arcs from its contact node at the copy's level; the source node's Charge is unchanged; the copy is spent per node reached; once the copy drops to the source's T the vertex stops arcing.
8. Charge addon: its vertex lands `stacks` Charge on every contact it lands, that vertex only; a refused contact lands nothing.
9. Visible: an arc per hop on the board from the centre to each reached node, in Lightning's colour, readable as distinct from a Burning disc; a conducting walk shows the wire carrying it and the Charge spent per pass-through (the node's bar drops); the Charge addon and a Shocked vertex read as charged. Sandbox host, `mise run check` only.

**NOTES**
- Parked owner idea, NOT DECIDED, not this unit (owner, 2026-11-10: *"wires might even be draining *too* fast, i think the fix would be to spread 1 Charge to each affected neighbor instead of voiding as many, but that could complicate timings badly if not thought through perfectly"*): an arc handing its spent Charge to the node it reaches. Not built here; the edge go-off spends into the void. If picked up it is one exported choice on the edge go-off, committed in the gather's per-beat sums.
- The look may be handed to a sub-agent working in this same worktree once the hook it draws from (signal, record field, scene stub) exists; the unit's drone stays the owner and reviewer of the result.
- Reading list and seam map were cut before #{defs}…#{catalyst} landed; #{refresh} re-cuts the stamp. If `mise run issue-drift` still flags this issue at dispatch, stop and say so.
- Parked, not built: **a wire evens itself out** (a Shocked run sharing Charge each world turn, `:1083-1085`); the **arc mirror** (owner, 2026-11-05: *"maybe when a nb tries to emit a lightning reach it reflects it? maybe not"*; a blanket reflect rejected, `:1086-1091`) — a Frozen neighbour is simply struck here, and what Frozen does to an arriving arc is #{pairs}.
- Frozen mutes Shocked / the break releases the storm and Frozen ends an arc are #{pairs}; the dual-reach entries themselves are #{resolver}'s gather (Acceptance 5 only pins Lightning's side). The Shocked "crackle" revealing charged nodes is parked as minor (`:870-873`).
- The no-parent go-off ("terrain hit", `:498-503`) has no caller; not built (the handoff's "lands with 6 and 7" is stale). Generator keystones (#1787) mint Charge without a hit and are their own issue.
- `lightning_bolt` gaining its innate Charge row: #{forge}. Charge arrows: #{quiver}; starter counts: #{forge}.
- Adversarial (f) — Charge colliding with explosive's `charge` tag and `vertex_charges` — is cleared by #{catalyst}; #{refresh} confirms neither name survives before this dispatches.
- The next element ADR's corrections are a sibling issue, not this one.

**Stubs on master** — none — shapes are named in Composition; the drone adds them.

```drift-stamp bd800181
docs/design/elements.md:70-113 — the trigger table, what a go-off pays, the hop ladder
docs/design/elements.md:418-458 — the element addon, vertex copy-on-fill, the spec-time vertex question
docs/design/elements.md:460-523 — the reach rule, chains concatenating, a copy carries Charge (the wire re-lays)
docs/design/elements.md:663-726 — the gather as the only terrain writer, one snapshot per beat, the edge subclass
docs/design/elements.md:744-753 — dual reach concatenated, the dedupe switch
docs/design/elements.md:823-873 — bands, the travel verb (a path conducts, one Charge per pass-through), the parked crackle
docs/design/elements.md:911-914 — Charge stays put
docs/design/elements.md:1083-1091 — the parked wire and arc mirror
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
