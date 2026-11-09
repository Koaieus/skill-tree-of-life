Fire, after the spine: what is left of Fire once #{burning} landed Burning's disc. That is the burn on the world turn, Burning as a light source, the Heat blade addon and the Burning vertex. Child of the #1716 hub; design home `docs/design/elements.md`. #1660, #1695 and #1696 close into this issue (their surviving content is in #{flow}, #{burning} and here). #1660's "death blasts first" is dropped, not built.

Blocked by: #{blade-elements}
Blocks: #{pairs}, #{forge}, #{quiver}

## Acceptance spec

**Decisions**
- *Burning* also "burns its holder each world turn ∝ the excess, side-blind (owner pick, 2026-11-08)" (`docs/design/elements.md:73-75`). Burning's burn is world-turn time, never a hit (`:728-742`).
- **Burning is a light source** (owner, 2026-11-06: *"burning being a light source does sound clever, could be one of the cells filled by burning"*): visible through fog to every entity and reveals its neighbours, as a VisionSystem fact with no combat rule (`:867-870`).
- **A holder's death changes nothing** (owner, 2026-11-08, picked *nothing — terrain persists*; #1660's "death blasts first" is pre-threshold history) (`:263-266`).
- Blade, *"an addon per element"* (owner, 2026-11-09): the Heat addon grants the rider and nothing else (`:418-424`). *"copy a burning node and you get a burning blade node (booms)"* (owner, 2026-11-09): a Burning vertex blasts a disc where it touches. *"so far there is *no* gameplay connection back to the source node after a blade node copy is made from it. not starting now"*, so the excess at fill is the vertex's power (`:425-440`).
- Fire needs no overflow verb (owner, 2026-11-06: *"ramping up fire der states to blaze to inferno"*, Burning's power growing with the excess) (`:880-884`).
- The vertex's copied state reaches the gather as a "go-off source" argument (pass pick, tentative; kept 2026-11-10). Spec-time readings for `:457-458` (pass picks, tentative): a Burning vertex is primed iff its copied Heat > its source node's T at fill, and its power = copy − that T. Its disc is #{burning}'s, centred on the contact's node, sized by that node's radius, never including it. It spends the copy 1 per node reached and stays Burning while the copy stays > T.
- Burn (pass picks, tentative): a step in #{flow}'s world-turn settle, reading the pre-diffusion snapshot. It lands through `DotTick.mint` on the node's combat host as TRUE damage with no record (the corruption-burst path), and lands nothing on an unallocated node. Amount = `burn_per_excess` × excess, carrying #1695's 0.5 per stack. Light radius: the farthest neighbour's centre distance plus that neighbour's radius.

**Knobs** (tentative defaults, easy to change; tests assert ratios)
- Fire's Burning band `.burn_per_excess` = 1.0 (`@export_range(0.0, 10.0)`) — owner, 2026-11-10: *"butn 1 per stack"* (burn; read as per stack above T, since only Burning burns — pass reading).
- Fire's Burning band `.light` = true. This is the band's light answer (#{defs}); the radius is derived, with no number.
- Heat addon `.stacks` = 1. The authored innate Heat per vertex, on #{blade-elements}'s element addon base. Editor feedback: the melee sandbox.

**Composition**
- Fire's `Element` def (#{defs}) owns the Burning band. #{burning} set its `go_off`. This unit sets `burn_per_excess` and `light`. Burning stays a pure function of `t` and T; nothing stores it.
- #{flow}'s settle routine gains one world-turn step: for every Burning node, mint `burn_per_excess × excess` through `DotTick.mint`. It is not on #{resolver}'s per-beat call.
- `VisionSystem.sources_for` gains one branch, `VisionSource.Kind.BURNING`, for every viewer: one disc per Burning node, read off its band in the same single pass over nodes. Vision recomputes on `terrain_band_changed` (#{terrain}) only when Burning is entered or left.
- The Burning vertex: #{blade-elements}'s copy-on-fill carries the Heat copy. At contact, the vertex hands the gather its copy as the go-off source, and #{burning}'s disc answers with the copy's power. The copy is spent; the source node is never touched.
- The Heat addon is one element addon scene (rider only) on #{blade-elements}'s base.
- Dies: nothing.

**Files touched**
- Fire's Burning band `.tres` (created by #{defs}): `burn_per_excess`, `light`.
- the settle routine #{flow} creates: the burn step.
- `systems/vision_source.gd`, `systems/vision_system.gd`: `Kind.BURNING` and its branch.
- `skill_node/addons/defs/heat_addon.tscn` (new), a visual under `skill_node/addons/visuals/` (new), and the addon pool/roster wiring #{blade-elements} names.
- `docs/domain/vision-system.md`: a "Burning nodes" section beside "Scout discs from rows". The elements domain doc gets the burn and the light.

**Acceptance**
1. `test/unit/elements/test_burning_burn.gd` (red first): one world turn burns an allocated Burning node by `burn_per_excess × excess` TRUE damage with no attack record. An unallocated Burning node takes nothing. The node's own camp does not matter. Heat ≤ T burns nothing.
2. Same file: a holder's death, a dealloc and a retake leave `t` untouched, and the burn resumes for the next holder.
3. `test/unit/systems/test_vision_sources.gd` (extend): a Burning node is a `BURNING` source for every viewer, including one owning nothing near it, with a radius of √power × node radius, the Burning disc's own size formula (owner, 2026-11-10: *"light radius same formula as explosion size would"*) — read from the same function #{burning}'s disc uses, never a second copy. It is gone once Heat drops to T. `sources_for` stays one pass over the nodes (`docs/domain/vision-system.md` § Cost model).
4. `test/unit/attack/melee/test_burning_vertex.gd`: a vertex filled from a Burning source booms #{burning}'s disc at its contact node with power = copy − source T. The source node's Heat is unchanged after the swing. The copy is spent per node reached, and a later contact goes off only while the copy stays > T.
5. Heat addon: its vertex lands `stacks` Heat on every contact it lands, that vertex only. A refused contact lands nothing (the Toxin pattern).
6. Visible: a burn tick shows a damage number on the node; a Burning node is lit through fog with its neighbours; the Heat addon and a Burning vertex read as hot on the board and on the blade. Check it in the sandbox host; `mise run check` only.

**NOTES**
- The look may be handed to a sub-agent working in this same worktree once the hook it draws from (signal, record field, scene stub) exists; the unit's drone stays the owner and reviewer of the result.
- Reading list and seam map were cut before #{defs}…#{catalyst} landed; #{refresh} re-cuts the stamp. If `mise run issue-drift` still flags this issue at dispatch, stop and say so.
- The no-parent go-off ("terrain hit", `:498-503`) is a defined shape with no caller and is not built. The handoff's "lands with 6 and 7" is stale.
- Burning × Frozen and thaw are #{pairs}. Fire arrows are #{quiver}; the forge element field and starter counts are #{forge}.
- Whip-crack (`:1077-1082`) is parked, not v1. The door for "a bespoke twist or tweaked T value later for Burn. or extinguish mechanics" stays open (`:907-909`).
- #1695's flow lives in #{flow} on the signed `t`. Its "unallocated sinks" and "½ damage per stack" are superseded (terrain rests on unallocated ground; burn ∝ excess). #1696's faces and its ignition rule (heat meets fuel) are superseded by the threshold model and Catalyst.
- The next element ADR's corrections are a sibling issue.

**Stubs on master**: none. The shapes are named in Composition; the drone adds them.

```drift-stamp bd800181
docs/design/elements.md:70-77 — the trigger table: Burning burns its holder each world turn
docs/design/elements.md:245-266 — the family table, why a holder's death changes nothing
docs/design/elements.md:418-458 — the element addon, vertex copy-on-fill, the spec-time vertex question
docs/design/elements.md:728-742 — the two clocks: the burn is world-turn time
docs/design/elements.md:823-884 — bands, Burning as a light source, no overflow verb for Fire
docs/design/elements.md:498-503 — the no-parent go-off, no caller
docs/design/elements.md:891-909 — temperature; the door kept open for Burn
docs/design/elements.md:1077-1082 — Whip-crack, parked
effects/status/dot_tick.gd:24-46 — mint: TRUE damage with no record, node-host branch
systems/vision_system.gd:313-337 — sources_for: SCOUT and OWNED branches, one pass
systems/vision_source.gd:1-20 — the Kind enum a new sight adds to
docs/domain/vision-system.md:116-149 — scout discs from rows, the closest analogue
attack/melee/blade_vertex_fill.gd:42-60 — the fill: a status copied per vertex, addons applied after
docs/domain/melee-blade-sim.md:416-425 — the Toxin rider-only addon pattern
systems/turn_manager.gd:401-409 — the world-turn body the settle runs in
systems/vision_source.gd — seam: Kind.BURNING
systems/vision_system.gd — seam: a BURNING gather branch in sources_for
test/unit/systems/test_vision_sources.gd — seam: source tests to extend
effects/status/dot_tick.gd — seam: the burn lands through mint
skill_node/addons/explosive_barrel_addon.gd — seam: apply_to_blade, the template for a blade-stack addon
skill_node/addons/defs/ — seam: the addon scenes the Heat addon joins
docs/domain/vision-system.md — seam: the Burning-source section
```
