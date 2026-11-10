Ice on the node: the Frozen band's answers (a copy is absorbed, a path ends), the three breakers, the corruption-shaped shatter with deep freeze, a blade snapping on Frozen, the Frozen vertex's concentrate snap, and the Cold addon. Child of hub #1716 (late unit). Design home: `docs/design/elements.md`. Nothing about a cast: Ice on a spell is #{ice-cast} (the concentrate; #{forge} stubs it at ×1 until then).

Blocked by: #{blade-elements} (and through it #{refresh}, #{defs}, #{terrain}, #{flow}, #{resolver}, #{go-off-zero}, #{burning}, #{catalyst}, #{catalyst-blade})
Blocks: #{pairs}, #{forge}, #{quiver}

## Acceptance spec

**Decisions** (owner, dated as quoted; `docs/design/elements.md` line ranges)
- Frozen on a hit: "a copy under the break threshold is absorbed whole (no damage, no riders), a path ends (0D); a direct hit lands (owner, 2026-11-09, picked *absorbed* over *lands, then stops*)" (:77; ADR 0082 §3, which stands). Frozen reads at two points (owner, 2026-11-10, picked *admit on arrival, the rest after riders*; ADR 0083 §2): the copy's absorption is checked against the node as it arrives, an absorbed copy lands no riders; the path-end and the break check read after the hit's element riders land. Only a direct Cold hit deepens a freeze; a Cold copy onto a Frozen node lands nothing (:679-681).
- The blade: *"We want to pop just the two vtx. Not too dramatic, and remember Ice is 0D. Point like. Single target. So no splash or anything just a fragile snap"* (owner, 2026-11-08, :176-184). First contact pops that one vertex; it breaks the ice only if the vertex is at least as heavy as the node: *"melee blade nodes shatter frozen nodes they hit *only if their radius is equal or larger than the node they hit* (specifically: if they have more weight; ignoring temporary modifications by e.g. passing over Cold (but not frozen) nodes)"* (owner, 2026-11-10, § A blade on Frozen). Weight = `(radius / 32)²`, the vertex's from its source radius × Bunker's `blade_mass` (owner picked *Bunker counts*), the node's from `SkillNode.radius`; a tie breaks; nothing per-contact (Cold drag) enters. A lighter vertex still pops and the ice holds (owner picked *snaps, ice holds*; fallback *deflects off the ice* *"if it turns out to nerf melee too much"* — not built here).
- The burst: *"frozen side: effect removed at %maxhp propto the amount removed"* (owner, 2026-11-08, :185-194): the shatter removes everything above T, overflow included, and deals excess × a knob fraction × max HP to the frozen node's holder as TRUE damage through the shared burst path corruption uses, nothing if unallocated. *"drop crit for now"* (owner, 2026-11-08).
- The breakers (owner, 2026-11-08, :196-207): a blade vertex's touch (gated by weight, above; only the touch is gated — owner picked, 2026-11-10 — so a light vertex's contact that crits or would deal threshold damage still breaks), any crit hit landing on the node, any damage at or above a flat threshold — *"a flat amount not scaling with excess …"*. The threshold applies to direct hits and arriving copies alike; a copy that breaks through also lands. Heat and decay end Frozen without a shatter. No re-evaluation: a hit's crit and damage are its own facts, fixed before it lands (crit conditions still read the node as it was before the hit, ADR 0083 §4); the Frozen band the breakers and the path-end read is the one after the hit's riders land (ADR 0083 §2), so a Heat hit that thaws the node passes through without a shatter and a hit that freezes it ends its own walk there.
- Deep freeze: *"deep-freeze stacks dealing bonus damage on breaking ice and get removed along with it"* (owner, 2026-11-06, :918-923).
- Travel verb: Frozen, 0D — "a path **ends**: hops, chains and arcs stop here" (owner, 2026-11-06, :884-891).
- A vertex copies its source's primed state: *"copy frozen node -> frozen blade node (detrimental so far, makes blade node fragile, but maybe we do add a damage increase to even it out?)"* (owner, 2026-11-09, :425-433). The Frozen vertex's snap is a concentrate (owner, 2026-11-09, :441-455): one contact hit, then the vertex pops; the bonus is an overlay on that vertex's `blade_damage` read at fill (*"bonus or multiplier riding the pipeline (see `overlay`)"*), scaled by Cold excess at fill.
- A blade's element is *"an addon per element"* (owner, 2026-11-09, :418-424): the Cold addon grants the rider and nothing else.
- Spike pop: *"The existing one just pops the one, docs may be stale"* (owner, 2026-11-08, :1206-1209) — settle the header against the code here.
- (pass reading, tentative) A spell walk's "path ends" reads the band after the arriving hit's riders land (ADR 0083 §2), before a break's spend settles; so an arrival that shatters the ice still ends the walk there, and one that thaws it does not.

**Knobs** (tentative defaults — easy to change; owners are the Ice `Element` def and its Frozen band as #{defs} shaped them)
- Frozen band `break_fraction_max_hp` = 0.10, `@export_range(0.0, 1.0, 0.01)` — the flat breaker.
- Frozen band `shatter_fraction_per_stack` = 0.01, `@export_range(0.0, 0.2, 0.001, "or_greater")` — burst % max HP per excess stack.
- Frozen band `shatter_spend_fraction` = 1.0, `@export_range(0.0, 1.0, 0.05)` — share of the excess a shatter removes.
- Frozen band `vertex_bonus_per_excess` = 0.10, `@export_range(0.0, 1.0, 0.01, "or_greater")` — the Frozen vertex's multiplier, no base term.
- Cold addon innate load per vertex — the shape and default are #{blade-elements}'s per-element addon; Ice authors its value (default 1).
- Visual knobs (shatter shard count, crust tint) — setter redraw on the `@tool` visual, or the sandbox-host blade tab.
Tests assert ratios (a deep freeze bursts more than a shallow one; burst ∝ excess), never these literals.

**Composition**
- The Ice `Element` def (#{defs}) carries the Frozen band; this unit adds the Frozen subclass of the `Admits` base #{defs} created in `elements/`. The gather head (#{resolver}) asks it in two reads per arriving hit (ADR 0083 §2): the copy's admission against the node as it arrives, then, after the hit's element riders have landed, the path-end and break check against the resulting band and the hit's crit and damage facts (crit conditions elsewhere still read the pre-hit node, 0083 §4). It gets one of: land, absorb (copy only, under the threshold: no stage-two entry, no onward reach), land + break. Ice owns no gather code and no terrain write.
- A break's spend (the excess × `shatter_spend_fraction`) joins the beat's committed spends through #{flow}'s shared settle routine, the one terrain writer (#{terrain}); the burst lands through `DotTick.mint`, the path `CorruptionStatus._on_burst` uses, so "a burst lands" stays one implementation. Unallocated node: spend yes, burst nothing.
- Spell walk: a node whose band is Frozen after the arriving hit's riders land (an absorbed copy lands none) is terminal for the walk, the way `hops_remaining <= 0` is today (`spell_resolver.gd:383`); the seam is wherever #{resolver} left departure.
- Blade on a Frozen node: `BladePopResolver.LiveGate.admit` gains a Frozen check that runs *before* its unallocated (`blade_pop_resolver.gd:280`) and own-node (:289) early returns — terrain is side-less (:896-898), so your own and unowned Frozen nodes snap a vertex too — and pops the vertex through the existing `_kill` (no drain check). The gate runs on a shadow world and writes no terrain. The refused contact still runs stage one: its gather head reads the Frozen band, and the `admits` answer fires the blade-touch breaker (spend + burst) when the vertex's weight (its build-time mass `(radius / 32)²` × Bunker's `blade_mass` — not `1 / inv_masses`, which is 0 for the pivot and dead vertices; the pivot keeps its exemption, #{blade-elements}) is ≥ the node's `(radius / 32)²`, and otherwise still checks the contact's crit and damage against the other two breakers. The weight is a fact the contact carries into the gather, read from the build-time mass, never a per-contact one. Only its stage-two payload (damage, other riders) is dropped. Today a refused contact returns from `BladeDamageInstance.land_on` before anything lands (:29-33), so the drone threads the refused contact through #{resolver}'s gather, not around it. The pop itself stays recorded as today (`popped_vertex`, emitted by `OutcomeApplier.land_one`). If the hit scan emits no contact event for an unallocated node, say so in the report and keep the check for allocated nodes of either side.
- Frozen vertex: #{blade-elements}'s copy-on-fill sets the vertex's primed copy and one-shot flag; Ice adds (a) the overlay on `blade_damage` at fill through the `overlays_for` hook, scaled by the copied excess, and (b) the pop after that vertex's first contact hit lands (the hit lands, unlike a spike pop). The source node is never touched.
- Cold addon: data on #{blade-elements}'s per-element addon base (rider only, budget by the `ice` count); no Ice-specific code.
- Dies: nothing. Frostbite (#1444) is not here: its own issue, blocked by this one.

**Files touched**
- The Ice `Element` def `.tres` and its Frozen band (paths #{defs} creates) — the knobs, the `admits` answer resource.
- A Frozen `Admits` subclass in `elements/`, beside the `GoOff` subclasses (new).
- `attack/spell/spell_resolver.gd` — walk ends at Frozen (shared with #{lightning}'s "conducts").
- `attack/melee/sim/blade_pop_resolver.gd` — Frozen check in `admit`; header and `_disintegrate_unreachable` docstring fixed.
- `attack/melee/blade_vertex_fill.gd`, `attack/plan/melee_attack_plan.gd` — the Frozen vertex overlay and one-shot pop (shared with #{fire}, #{lightning} through #{blade-elements}'s seat).
- The Cold addon scene under `skill_node/addons/defs/` (new, from #{blade-elements}'s template); its visual under `skill_node/addons/visuals/`.
- `docs/domain/melee-blade-internals.md` — the spike-pop section; the elements domain doc #{resolver} created — Frozen's rules.
- Tests: `test/unit/attack/test_frozen_admits.gd`, `test/unit/attack/test_ice_shatter.gd`, `test/unit/attack/test_blade_frozen.gd` (new).

**Acceptance** (red first, `docs/domain/red-green.md`)
1. `test_frozen_admits.gd`: a copy whose damage is under the break threshold, arriving on a Frozen node, produces no stage-two entry and no onward reach (no damage, no riders, Cold included).
2. Same file: a direct hit on a Frozen node lands in full; a Cold direct hit raises the node's Cold, a Cold copy does not.
3. Same file: a copy at or above `break_fraction_max_hp` of the holder's max HP lands and breaks the ice; so does a crit copy under it.
4. `test_ice_shatter.gd`: a break leaves Cold at exactly T (spend fraction 1.0; at a lower fraction, T plus the unspent share) and lands TRUE damage equal to `excess × shatter_fraction_per_stack × max HP` on the holder via `DotTick.mint`; an unallocated Frozen node loses the excess and takes nothing.
5. Same file: deep freeze — a node past the cap bursts for its whole excess, overflow included; the ratio of two bursts equals the ratio of their excesses.
6. Same file: the breakers and the path-end read the band after the riders land (ADR 0083 §2) — a direct hit whose own Heat thaws the node below T passes through with no shatter and no burst; a direct hit whose own Cold takes a node over T ends its walk there, and with a crit it shatters at once. An absorbed copy lands no riders (its Heat does not thaw the node).
7. Spell walk: a hop arriving on a Frozen node lands and the walk mints no next wave from it, even when that arrival shatters it (test in `test_frozen_admits.gd`, a two-hop spell over a Frozen middle node).
8. `test_blade_frozen.gd`: a vertex at least as heavy as the Frozen node it touches (an enemy's, and your own; equal radius included) pops (`dead_at` set at the contact), its contact deals no damage, the replayed record breaks the ice (one burst), and no vertex other than the popped one gets a `dead_at`.
8b. Same file: a lighter vertex (smaller source radius, no crit, under the threshold) pops the same way and the ice holds (Cold unchanged, no burst); the same light vertex given Bunker mass enough to reach the node's weight breaks it; the light vertex with a crit contact breaks it.
9. Same file: a Frozen vertex's first contact hit lands at `blade_damage × (1 + vertex_bonus_per_excess × excess)` (assert the ratio to an unfrozen twin), then the vertex pops; the source node's Cold is unchanged.
10. Same file: a Cold addon vertex plants Cold as a rider and changes no stat.
11. Spike-pop docs: `blade_pop_resolver.gd`'s header and `melee-blade-internals.md` § Spike pop say a pop kills the one vertex and records the vertices it orphaned as a coasting severance; the `_disintegrate_unreachable` docstring no longer says "as dead". `test_blade_pop_resolver.gd`, `test_blade_severance.gd`, `test_blade_pop_shatter.gd` pass untouched (characterization pins, not re-pointed).
12. Look — shatter: a break shows shards at the node, sized by the excess, so a deep freeze visibly bursts bigger than a shallow one (live game and the sandbox-host blast/status tab).
13. Look — blade snap on Frozen: the popped vertex shatters into `ShatterField` at the contact and the node's ice breaks in the same beat (melee sandbox).
14. Look — Frozen vertex snap: a frozen vertex reads as brittle on the blade before the swing, and its one contact shows a heavier hit then the pop (melee sandbox).
15. Look — absorbed copy / ended walk: a player can tell a copy or a spell walk stopped at this node (a cue on the node), distinct from a miss (spell playground, a blast near a Frozen node).
16. Look — Frozen node: a crust or frost read on the node itself, distinct from and compatible with #{terrain-ui}'s band glow, visible on unowned nodes too.
17. Look — Cold addon: the addon on a blade vertex reads as Cold (addon gallery and melee sandbox).

**NOTES**
- The look may be handed to a sub-agent working in this same worktree once the hook it draws from (signal, record field, scene stub) exists; the unit's drone stays the owner and reviewer of the result.
- Reading list and seam map were cut before #{defs}…#{catalyst-blade} landed; #{refresh} re-cuts the stamp. If `mise run issue-drift` still flags this issue at dispatch, stop and say so.
- On a cast, the hops cut by the Ice shape add to the shatter's excess (ADR 0084 §8; the Ice seed is no breaker of its own) — built by the Ice-concentrate unit #{ice-cast}. This unit keeps the shatter's excess an input that can be added to (one number the burst and the spend read), and builds none of it.
- Not here: Frozen muting Shocked and the break releasing it, Frozen ending an arc, a Heat hit thawing harder, Heat never touching a Frostbite pack — #{pairs}. Frostbite #1444 (blocked by this). The Cold spell and Thermal shock — #1789 (Needs design). The cold arrow — #{forge}. Sweep speed on `t`, which acts per contact (owner, 2026-11-10: *"option 1 seems best"*) — #{blade-elements}; a Frozen vertex's snap reads that per-contact speed like any contact. The band glow and Frozen label — #{terrain-ui}. Melee crit condition #1786.
- "Nothing severed" (:184) is read as "no other vertex dies": `_kill` still records the orphans as a coasting severance, which is the shipped spike pop the owner kept.
- `docs/design/aspect_matrix.md:535` still calls resting Cold "**Frost**, Ice's medium"; the owner renamed it Cold (`elements.md:254`). Fix it if this unit touches the matrix; otherwise it rides the next element ADR's sibling issue.
- Next element ADR corrections (0081 §1, §3, §5, §6, §7, §9; 0082's Context) are a sibling issue, not this unit.

**Stubs on master** — none — shapes are named in Composition; the drone adds them.

```drift-stamp efba0bc3
docs/design/elements.md:70-78 — the trigger table: Frozen denies, a copy under the threshold is absorbed whole
docs/design/elements.md:176-207 — blade snap, corruption-shaped burst, the three breakers, pre-hit reads
docs/design/elements.md:425-455 — vertex copy-on-fill; the Frozen vertex's concentrate snap and its overlay knob
docs/design/elements.md:661-681 — stage one: the Frozen check at the read; a Cold copy lands nothing
docs/design/elements.md:857-923 — bands on the Element def, the travel verb "ends", deep freeze
docs/design/elements.md:1206-1209 — the spike-pop docs-vs-code check
effects/status/corruption.gd:24-37 — the burst path a shatter reuses (`_on_burst`, `burst_amount`)
effects/status/dot_tick.gd:15-48 — `DotTick.mint`: TRUE damage on a node or entity host
attack/melee/sim/blade_pop_resolver.gd:1-10 — the header to settle against the code
attack/melee/sim/blade_pop_resolver.gd:271-309 — `LiveGate.admit`: where the Frozen check sits beside the spike check
attack/melee/sim/blade_pop_resolver.gd:603-648 — `_kill` and `_disintegrate_unreachable` (records a Severance, not `dead_at`)
attack/melee/sim/blade_damage_instance.gd:29-69 — `land_on` and the once-only gate; a refusal carries `popped_vertex`
attack/melee/blade_vertex_fill.gd:28-49 — `overlays_for` hook and the per-vertex fill a Frozen copy rides
attack/plan/melee_attack_plan.gd:588-600 — `overlays_for`: how a swing's overlay folds into one node's read
docs/domain/melee-blade-internals.md:5-31 — § Spike pop: line 7-8 says "disintegrated", 21-25 says "not killed"
attack/spell/spell_resolver.gd — seam: walk departure (`hops_remaining <= 0` at :383), where a Frozen node is terminal
attack/melee/sim/blade_pop_resolver.gd — seam: LiveGate.admit Frozen check; header/docstring fix
attack/melee/blade_vertex_fill.gd — seam: Frozen vertex overlay at fill
attack/plan/melee_attack_plan.gd — seam: overlays_for, owns the BladeVertexFill instance (:42)
attack/outcome/outcome_applier.gd — seam: land_one emits a recorded pop; the blade-touch break lands here
ui/vfx/shatter/shatter_field.gd — seam: the shard field a pop already spawns into
skill_node/addons/explosive_barrel_addon.gd — seam: the addon template the per-element addons follow
test/unit/attack/test_blade_pop_resolver.gd — seam: characterization pin
test/unit/attack/test_blade_severance.gd — seam: characterization pin
test/unit/effects/test_corruption_status.gd — seam: the shared burst path's pin
```
