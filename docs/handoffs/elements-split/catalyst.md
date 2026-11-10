The Explosive aspect is retagged as Catalyst, an element-generic converter. Catalyst turns into the landing element 1:1 at land, and into the priming element at settle. Go-off zero's Explosive disc is deleted here, which is safe because Burning's disc already lands blasts. Firecracker is rewritten to plant Heat. This is spine unit 9 of the #1716 split. Design home: `docs/design/elements.md`.

Blocked by: #{burning}
Blocks: #{catalyst-blade}

## Acceptance spec

**Decisions**
- *"so my relevation yesterday was: maybe we should move Fuel OUT of Fire, and turn it into smth like "Catalyst" instead, and let it act on any incoming elemental-terrain status (Heat, Cold, Charge)"*; *"like "3 Catalyst" has incoming hit of "2 Heat" and it turns it into "5 Heat" doing a 1:1 Catalyst→{incoming element} trade."* (owner, 2026-11-09; `elements.md:115-120`)
- *"i think catalyst only sits on allocated nodes like most/all Aspect statuses (but we can always make an exception and make it owner-agnostic)"* (owner, 2026-11-09; `:123-125`). Taken as settled. `on_dealloc` stays CLEAR.
- Colouring (owner, 2026-11-09; `:134-142`): *"option 1. or: also when "igniting"? … still element-symmetric right?"*. The owner picked *hits and priming*: (a) a hit carrying that element's rider lands (land phase), or (b) the node primes by any route (read at settle). Flow below T never colours Catalyst.
- The trade (owner, 2026-11-09; `:149-154`): *"… iff we decide a hit can have at 0 or 1 Element associated with it then we don't need the "slice" part and can just consume all"*. The whole store converts at 1:1, with no slice.
- *"yeahhh exactly option 1. w/visually like purple crystals or smth instead of black goo"* (owner, 2026-11-09; `:166-170`):
  - Count `catalyst_aspect`, school DEX.
  - Facets `catalyst_stacks_per_hit` / `catalyst_resistance`.
  - The goo arrow plants it.
- The blast gap (owner, 2026-11-10): *"option 1 but spare no drones, split if needed"*. Burning's disc lands first (#{burning}). This unit deletes go-off zero's disc, so master always has a blast.
- Firecracker (owner, 2026-11-10, handoff § 0): its row names Fire and plants Heat. `FuelUse` and `FuelBlastReach` are deleted here.
- Prime conversion is read inside #{flow}'s settle seat and never hooked on `terrain_band_changed` (pass pick, tentative, kept 2026-11-10). Doc `:876-882` keeps that signal for display.
- A planting hit is a hit: on a primed node it sets it off (`:484-487`; pass ruling, 2026-11-10). A goo arrow on a primed node flips nothing (`:144-149`).
- Catalyst caps at k × T (pass default, tentative; `:295-297`). It keeps its own `StatusDef` decay and decays slowly (`:163`, `:984`; pass ruling, 2026-11-10).
- The retag list (`:1089-1095`). The `charge` tag is freed for Lightning (`:1200-1201`).

**Knobs** (tentative; tests assert ratios and invariants, never the literal)
- `CatalystStatus.ratio_in` / `ratio_out` (`@export_range(1, 10, 1, "or_greater")`) = 1 / 1. This is the int:int trade rate. Editor feedback: the status sandbox tab.
- `CatalystStatus.cap_k_times_t` (bool) = true. It caps the row at the node's k × T, read from #{terrain}'s cap function.
- `catalyst.tres` decay = `FlatDecay.per_tick` 1.0, per holder turn end (today's value). The invariant to pin (the doc says only "decays slowly (knob)"; the reading is tentative, not the owner's): over one **cycle**, Catalyst loses no more than a terrain stack does. A cycle is the span from one holder turn end to the next on a board with one living carrier, where #{flow}'s `PER_CARRIER` rule closes exactly one world turn, so the status decay runs once and #{flow}'s decay sweep runs once. The loss to compare is the Fire band's decay-rate answer (#{defs}), read from the def, never the literal.

**Composition**
- **Retag.** `explosive` becomes `catalyst` on every artifact in the stamp: the id, file, class, `display_name`, tag and identity.
  - `effects/status/catalyst.gd` (`CatalystStatus extends StatusDef`, the `poison.gd` pattern) owns the ratio, the cap, and one static `converted(store) -> int`.
  - `catalyst_resistance` is new. No `explosive_resistance.tres` exists, so mint it the way the other facets are minted (`manage-stats`).
- **Land conversion.** It happens in #{resolver}'s gather land step (`:661-666`). When a hit's element rider lands on a node holding Catalyst, the store converts via `converted()` into that rider's stacks before the terrain write, and the row is cleared. The converted stacks count toward this hit's own primed-ness and power: both are read after the hit's element riders land (ADR 0083; `:93-95`). Copies are hits, so they convert too.
- **Prime conversion.** The seat #{flow}'s settle routine exposes (per beat and per world turn) reads the node's Catalyst row whenever a band crosses from inert to primed, and converts the row into that element.
- **Go-off zero's disc goes.** The `GoOff` field leaves the Catalyst `Aspect` def. Burning's disc (#{burning}) is the only blast; it replaces the old ×3 disc with `disc_radius(power, node_radius)`, r = 2 × (√power + 1) × node radius (ADR 0084 §2), and this unit adds no radius of its own. Detonation tests that #{go-off-zero} pinned on the Explosive disc re-point to the Burning band, with Heat excess as the power source. This unit does the re-pointing (acceptance 9). Burning's disc lands a centre copy at share 1 (`elements.md` § Landing resolution, "Every landing is a whole hit"), and #{go-off-zero} tentatively lands none at share 0.5, so three of its pins do not survive the move and are re-pointed by this unit to the whole-hit rule: `test_explosive_charges` "never the centre", `test_blast_mark` "the centre's own hits carry no mark", and `test_heal_spell_blast`'s `[n[2]]`. If the owner rules that go-off zero follows the whole-hit rule, #{go-off-zero} has already re-pointed those three, and this unit only re-points them again if their numbers still read the old disc.
- **Firecracker.** Its intake row names Fire with the default `PlantUse`, so a landing plants Heat. A row named by element resolves its status through the `Infusion.load_of` / `use_of` rekeying that #{burning} owns; this unit relies on it and adds none. `FuelUse`, `FuelBlastReach` and the `fuel_blast_reach` propagation sub-resource are deleted. The spell walks with its config's remaining reach (pass reading, tentative). Its blasts now come from the Burning nodes it primes. The description is rewritten to match.
- **Dies:**
  - `DetonateUse`.
  - `LoadBag.detonate_load` and `Infusion.detonate_load`.
  - `StatusDef.default_face`, `AspectIntake.use_for_status` and `_DEFAULT_DETONATE_TAG`. Catalyst takes `PlantUse` by default.
  - Any `DetonateEffect` / `ExplosiveSpread` remnant.
- **The blade in the interval.** #{go-off-zero} moved the blade's board blast onto the gather, hosted by the Explosive disc; deleting the disc therefore ends the board blast a charged contact arms. Between this unit and #{catalyst-blade} (tentative, not the owner's; #{catalyst-blade} still deletes the rest):
  - A charged piece contact still spends Catalyst as charges and still pops or shrugs, as the node-side piece pass has it, and lands its one hit. It no longer arms a board blast of its own. A primed struck node goes off through Burning's disc as any hit does.
  - `test_blade_explosive.gd` stays, edited. Its cases that assert a board blast from a charged contact (reached nodes, share, the blast mark) are deleted here, because their disc is gone. Its piece-side cases (spend, pop and shrug verdicts, the pre-beat read) are re-pointed to `catalyst` and stay green. #{catalyst-blade} deletes the file, with `test_blade_piece_charges.gd`.
  - This unit does not touch the piece pass, `vertex_charges` or the barrel on a blade; those are #{catalyst-blade}'s.
- **The blade side is #{catalyst-blade}'s.** Here, the blade's id literals only re-point to `catalyst`:
  - `BladeVertexFill.EXPLOSIVE`
  - `BladeStyle.charge_identity`
  - `BladePopResolver.LiveGate.explosive_def()`

  That keeps the blade suite green, with the `test_blade_explosive.gd` edit above. In the interval, a swung vertex still spends Catalyst as charges (pass pick, tentative).
- **Replication.** The renamed ids reach `_R_STATUSES` and the fingerprint. Bump `SaveFile.FORMAT_VERSION` and `MIN_FORMAT_VERSION` together (`network/save_file.gd:46-48`; 14 at the time of writing, the next free number if another unit bumped first), as the 11, 12 and 13 renames did: older files are refused (tentative, not the owner's: the doc says nothing on old saves, and a file's `explosive` id would otherwise name no status). The five rosters re-point.

**Files touched** — the stamp's seam map, each entry with its destination. #{catalyst-blade} later owns the blade files listed there.

**Acceptance**
1. `test/unit/effects/test_catalyst_conversion.gd` (new, red first, `docs/domain/red-green.md`) covers these cases:
   - 3 Catalyst plus a 2-Heat hit gives 5 Heat, and the row ends at 0.
   - The converted stacks count toward this hit's own primed-ness and power: a node at T-4 with 3 Catalyst, hit by 2 Heat, ends at T+1 and sets off within the same hit (read after the riders land, ADR 0083). The same hit with no Catalyst stays under T and does not.
   - Cold and Charge behave the same way.
   - A hit's centre landing converts nothing, and a copy's Heat rider on a reached node converts that node's Catalyst (copies are hits).
   - A hit with no element leaves Catalyst alone.
   - The ratio scales the result.
   - The converted stacks obey the element's k × T cap and overflow.
   - A payload carrying no element rider, or more than one, converts nothing (the doc converts on a payload with *exactly one* element rider; the zero-or-two case is a reading, tentative, not the owner's).
2. Same file: Heat raised past T by the settle routine alone converts Catalyst. Heat that flows in but stays at T or below does not.
3. Same file: a goo arrow on a Burning node sets it off. Its copies carry Catalyst over the disc. The node's own pre-hit Catalyst is not converted (no element rider lands, so its Burning band and its Heat do not move on that account) and is not lost. Under the whole-hit rule the arrow's own landing and the go-off's centre landing carry aspect riders, so each plants Catalyst on the hit node by the usual planting rules; the test asserts the row grew by exactly those landings' stacks and no more (tentative, not the owner's: the doc's "the Catalyst on the node itself waits for the next element" predates the whole-hit call; reported as a gap). The centre landing carries no terrain rider, so it converts nothing.
4. Same file: Catalyst lands only on allocated nodes, clears on dealloc, caps at k × T, and decays by its own def.
4b. Same file, the decay invariant (Knobs): on a one-carrier board, a node holding N Catalyst and N Heat (N above both rates) goes through one cycle, a holder turn end that closes one world turn. The Catalyst lost is at most the Heat lost, and the Catalyst lost equals `catalyst.tres`'s per-tick decay. Both numbers are read from the defs. It fails if the decay is raised above the Fire band's rate.
4c. `test/unit/network/test_save_file.gd`: the bumped `FORMAT_VERSION` has its entry in `_ROW_LAYOUT_PINS`. The existing refusal case (`MIN_FORMAT_VERSION - 1`) now covers the previous version. A new case: a file written at the previous version, whose status rows carry the `explosive` id, loads as refused with the version message (`load_result` not OK, the world left at its empty default), never half-applied. Add the `## <n>:` comment line to the version history, as 11, 12 and 13 have it.
5. `test/unit/spell/test_firecracker.gd` is re-pointed: a landing plants Heat, and a cast that primes a node blasts through Burning's disc. Its old fuel-radius asserts go.
6. Gone from master: `DetonateUse`, `default_face`, `detonate_load`, `FuelUse`, `FuelBlastReach`, and the `"charge"` tag in `effects/`.
7. Outside `attack/melee/`, `skill_node/addons/explosive_barrel_addon.gd`, `addons/melee_sandbox/`, history docs and `addons/at-icons`, `git grep -i explosive` returns nothing.
8. Retag pins: the following tests pass with only the id re-pointed. Their assertions are unchanged.
   - `test_ammo_type_roster`, `test_status_decay_slot`, `test_roll_pass`, `test_aspect_intake`.
   - `test_aspect_stats`, `test_dot_stack_stats`, `test_pool_scoping`, `test_status_sections`.
   - `test_explosive_barrel_addon`, renamed `test_catalyst_barrel_addon`.
9. Detonation pins (`test_explosive_charges`, `test_blast_mark`, `test_blast_effect` if #{go-off-zero} kept it, `test_paired_damage_effect`, `test_heal_spell_blast`, `test_disc_go_off`) are re-pointed to the Burning band by this unit. Their death-burn, heal-under-mask, mask-excluded-no-chain and record assertions survive. What does not survive unchanged, and is re-pointed here:
   - The three centre pins (Composition, "Go-off zero's disc goes"): "never the centre" becomes the hit node taking its centre landing (1 + 1 per channel); "the centre's own hits carry no mark" becomes the centre landing carrying the mark; `test_heal_spell_blast`'s `[n[2]]` becomes `[n[1], n[2]]`, the centre joining the heal.
   - Charge-formula assertions (the spend/power table, radius 3 × √power) become Burning's: spend 1 Heat per node reached, power the Heat excess, radius `disc_radius`; they read the knobs.
   - The share reads the disc's knob (default 1), never 0.5.
   - `test_burning_go_off.gd`'s dual-reach case (#{burning} acceptance 5) loses its Explosive channel. It re-points to a second disc `GoOff` built in the test, so it still has two channels to concatenate.
   - Any other test whose fixture authors the Explosive `Aspect`'s `go_off` is re-pointed to a Burning band or retired with it.

   The drone lists every re-pointed assertion in its report.
10. `docs/domain/explosive.md` is `git mv`'d to `catalyst.md` and rewritten as what *is*: the status, the trade, both triggers, cap, decay, barrel, goo arrow and knobs, checked against `catalyst.tres`. The blade passage is left for #{catalyst-blade}.
11. `.claude/rules/explosive.md` is rewritten. The PlantUse claim goes, and only its blade line remains, scoped to `blade_pop_resolver.gd`. `mise run rules-hygiene` and `mise run docs-hygiene` are clean.
12. Explosive wording is fixed in the same pass: `aspect-cell-authoring`, `node-subtypes`, `stat-surfaces`, `status-effects`, and the `aspect_matrix.md` rows.
13. Visuals:
    - Catalyst on a node reads as violet crystals. When #{terrain-ui}'s bars exist, it sits under them.
    - A conversion shows a pulse in the landing element's colour on that node.
    - The Catalyst icon replaces `explosive.png`, with `mapping.txt` and `ATTRIBUTION.md` updated.
    - The goo arrow (`catalyst_arrow.tscn`) and the barrel visual read as crystal.

**NOTES**
- Reading list and seam map were cut before #{resolver}, #{go-off-zero} and #{burning} landed. #{go-off-zero} moved these lines. The dispatching lead re-checks `mise run issue-drift`; if it still flags this issue, stop and say so.
- The look may be handed to a sub-agent working in this same worktree, once the hook it draws from (signal, record field, scene stub) exists. The unit's drone stays the owner and reviewer of the result.
- Firecracker needs a retune knob pass (`innate`, `power`, `max_hops`) once Fire plays. That pass is not this unit. Owner aside, 2026-11-10: *"btw infusing Firecracker with Catalyst naturally makes it more effective!"*. That combo is intended and needs nothing built.
- ADRs 0061, 0062 and 0070 (`DetonateUse` / `FuelUse`, the default face, the two-sided blade) join ADR 0081 §1, §3, §5, §6, §7 and §9 and ADR 0082's Context in the sibling issue for ADR corrections. Write no ADR here.
- Out of scope here: the starter count → #{forge}; the Greed guard → #{resolver}.
- Left untouched on purpose: history (`docs/adr/*`, `docs/corpus/*`, `docs/handoffs/*`, `docs/design/archive/*`), and `explosiveness` particle properties (`pop_burst.tscn`, `dust_puff.tscn`, `leafblower_rebound.tscn`, `arrow_impact_emitter.*`).

**Stubs on master** — none — shapes are named in Composition; the drone adds them.

```drift-stamp efba0bc3
docs/design/elements.md:115-174 — Catalyst: trade, both triggers, goo arrow, retag, decay
docs/design/elements.md:295-298 — the k × T cap (pass default)
docs/design/elements.md:484-487 — a planting hit is a hit
docs/design/elements.md:661-677 — stage one: Catalyst converts in the land step
docs/design/elements.md:734-747 — go-off zero's disc and its deletion at the retag
docs/design/elements.md:876-882 — terrain_band_changed is display-only
docs/design/elements.md:982-984 — Catalyst keeps its own decay
docs/design/elements.md:1003-1040 — the three "explosive"s; the vocabulary guard
docs/design/elements.md:1076-1101 — the retag list
docs/design/elements.md:1198-1202 — the `charge` tag freed for Lightning
docs/handoffs/fuel-to-catalyst-arc.md:128-149 — every Explosive artifact and its history
docs/domain/explosive.md:1-190 — what is today, to rewrite
attack/spell/aspect_intake.gd:44-75 — the default-face map that dies
attack/spell/propagation/reach/fuel_blast_reach.gd:1-40 — Firecracker's fuel shape, deleted
combat/status_host.gd:76-92 — apply_status, where the cap clamps
effects/status/explosive.tres — seam: → catalyst.tres + CatalystStatus; tag charge → catalyst
effects/status/spread/explosive_spread.gd — seam: delete the remnant
effects/status/status_def.gd — seam: delete default_face
effects/status_roster.tres — seam: re-point
identity/defs/explosive.tres — seam: → catalyst.tres, violet
identity/identity_roster.tres — seam: re-point
identity/defs/spell_firecracker.tres — seam: wording
aspects/defs/explosive.tres — seam: → catalyst.tres; GoOff field off
aspects/aspect.gd — seam: GoOff field and comment go
aspects/aspect_roster.tres — seam: re-point
stats_system/defs/explosive_aspect.tres — seam: → catalyst_aspect.tres
stats_system/defs/explosive_stacks_per_hit.tres — seam: → catalyst_stacks_per_hit.tres
stats_system/stat_def_roster.tres — seam: re-point; add catalyst_resistance
attack/ammo/types/explosive.tres — seam: → catalyst.tres
attack/ammo/ammo_type_roster.tres — seam: re-point
attack/spell/defs/firecracker.tres — seam: row names Fire, PlantUse; reach sub-resource goes
attack/spell/load_use/detonate_use.gd — seam: delete
attack/spell/load_use/fuel_use.gd — seam: delete
attack/spell/load_use/load_bag.gd — seam: delete detonate_load
attack/spell/load_use/load_use.gd — seam: comment
attack/spell/infusion.gd — seam: delete detonate_load
attack/spell/on_hit/detonate_effect.gd — seam: delete the remnant
attack/spell/on_hit/blast_effect.gd — seam: explosive strip goes
attack/spell/spell_resolver.gd — seam: detonate_load arming goes
attack/formulas/ranged_damage.gd — seam: arm call and comment go
attack/outcome/hit_landing.gd — seam: comment
attack/outcome/paired_damage_instance.gd — seam: comment
attack/melee/blade_vertex_fill.gd — seam: EXPLOSIVE literal → catalyst (interim)
attack/melee/blade_style.gd — seam: charge_identity → catalyst (interim)
attack/melee/sim/blade_pop_resolver.gd — seam: explosive_def() → catalyst (interim)
skill_node/addons/explosive_barrel_addon.gd — seam: → catalyst_barrel_addon.gd
skill_node/addons/defs/explosive_barrel_addon.tscn — seam: → catalyst_barrel_addon.tscn
skill_node/addons/visuals/explosive_barrel_visual.gd — seam: → catalyst_barrel_visual.gd, crystal
skill_node/keystone/instances/spirit_node.tscn — seam: aspects list re-point
entity/blocker/faces/explosive_face.tres — seam: → catalyst_face.tres
procgen/modules/blockers.gd — seam: face preload
procgen/pools/dexterity.tres — seam: roll → catalyst_aspect
procgen/modules/first_level/content.tres — seam: barrel re-point
procgen/modules/coop_versus/content.tres — seam: barrel re-point
entity/ring/aspect_ring.tscn — seam: two cells → Catalyst
addons/sandbox_host/tabs/71_blast_panel.gd — seam: picker default → Burning
ui/vfx/blast_visual.gd — seam: ring identity comment
ui/vfx/rider_blast_layer.gd — seam: comment
ui/vfx/projectile/visual/arrows/explosive_arrow.tscn — seam: → catalyst_arrow.tscn
assets/icons/aspects/explosive.png — seam: → catalyst.png (+ .import, mapping.txt, ATTRIBUTION.md)
network/save_file.gd:46-48 — the version bump
.claude/rules/explosive.md — seam: rewritten to its blade line
docs/domain/aspect-cell-authoring.md — seam: examples → Catalyst
docs/design/aspect_matrix.md — seam: remaining Explosive rows
```
