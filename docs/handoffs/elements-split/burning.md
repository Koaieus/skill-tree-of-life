Burning, on the spine: Fire's `Element` gains its Heat ride row and the Burning band's disc `GoOff`, so master has a Burning blast before the Catalyst retag deletes go-off zero's Explosive disc. Child of the #1716 hub; design home `docs/design/elements.md`. The rest of Fire (burn tick, light, Heat addon, Burning vertex) is #{fire}.

Blocked by: #{go-off-zero}
Blocks: #{catalyst}

## Acceptance spec

**Decisions**
- The blast gap closes on the spine (owner, 2026-11-10: *"option 1 but spare no drones, split if needed"*): Burning's disc lands before the retag; go-off zero's disc keeps riding the Explosive `Aspect` beside it until #{catalyst} deletes it. Master always has a blast.
- *Burning*, a hit on it: "explodes: a disc, power = the excess, a little damage ∝ power, the triggering hit's payload copied over the disc" (`docs/design/elements.md:73-75`).
- Spend: "Burning 1 per node its disc covers" (owner, 2026-11-08: *"at some explosion size, fire would hit basically "all its nbs" like equalling a shock to each nb"*); a disc that reaches no other node does not go off (*"possibly extend this rule to make it cost 0 if it hits nobody?"*, *"there should be at least 1 stack disappearing, possibly more"*); the spend digs under T (*"would decharge more rapidly"*) (`:79-93`).
- Power is the excess read after the triggering hit's element riders land; primed-ness reads pre-hit (`:93-102`, owner 2026-11-09 two-stage order).
- Size: radius ≈ √power × node radius (owner, 2026-11-08: *"size(N) ≈ sqrt(N)×node_radius so chances are power 1 doesn't hit any node, but that's tuning"*) (`:110-113`). Go-off zero keeps its ported `reach_per_radius` (3.0) until #{catalyst} deletes it (coordinator ruling, 2026-11-10).
- The disc is the `GoOff` disc subclass on the `Element` def (owner, 2026-11-09: *"i think it should sit on Element def, going off is just about their thing"*), "go-off zero, then Burning unchanged with another power source" (`:708-721`).
- **Burning is what ignites** (owner, 2026-11-05: *"Burning ignites"*, picked over "any Heat ignites") (`:903-906`).
- Copies carry everything (owner, 2026-11-08: *"everything rides yeah, LET IT RIDE! can change that later if it becomes too much"*) (`:105-108`), so a Heat rider on a copy chains.
- Dual reach (owner, 2026-11-10: *"riders twice, payload twice. charged burning nodes sounds like a dangerous concept"*): a node holding Explosive charges and Burning sets off both discs, and a node inside both gets two entries, each landing everything at its share. Pass reading (tentative, unconfirmed): each go-off fires at most once per hit (the once-per-node set).
- A ride row plants its named status: Heat rides "exactly as Poison rides" (the doc's rule, `:346-360`; the owner's 2026-11-04 line behind it is at `:354-357`).

**Knobs** (tentative defaults, easy to change; tests assert ratios, never the literal)
- Fire's disc `GoOff` `.radius_per_node_radius` = 1.0 (`@export_range(0.1, 5.0)`). This is the owner's √power × node radius. Editor feedback: the blast sandbox tab (`addons/sandbox_host/tabs/71_blast_panel.gd`) shows Fire's disc beside go-off zero's.
- the same `.damage_per_power` = 2.0. The disc's own "little damage", added to each copy; the default is carried from `ExplosiveSpread.damage_per_charge`.
- the same `.share` = 0.5. The one-share knob (#{resolver}), on Fire's own instance.

**Composition**
- Fire's `Element` def (#{defs}) owns Heat and its ordered bands. This unit authors the Burning band's `go_off` as a second instance of #{go-off-zero}'s disc subclass. Its power source is the band excess (Heat over T, read from #{terrain}'s signed `t` after the land step), not go-off zero's charge formula. If the disc subclass hard-codes go-off zero's power, the power read becomes the subclass's one override point. No second disc class.
- #{resolver}'s gather asks the band to *go off*. The disc answers four things: the reached set (Euclidean, through the spatial index go-off zero uses, never the centre), the spend (the reached count), the share, and the own damage. The gather owns chains, the once-per-node set and the one-snapshot settle.
- The Heat ride row is the existing `AspectIntake` row naming Heat's `StatusDef` (#{defs} gives a row its planted status). Landing it writes `t` through #{terrain}'s one writer. No new use class.
- Look: the blast VFX that #{go-off-zero} renders from the record's blast table. Fire's disc reads in Fire's colour (the `Element` identity, #{defs}) and stays distinct from go-off zero's.
- Dies: nothing. Go-off zero's disc and its Explosive holder stay until #{catalyst}.

**Files touched**
- Fire's `Element` def and Burning band `.tres` (created by #{defs}): `go_off` set.
- the disc `GoOff` subclass (created by #{go-off-zero}): a power source seam, if it lacks one.
- `ui/vfx/blast_vfx.gd` / `blast_visual.gd`: a per-element look for Fire's disc (shared seam with #{go-off-zero}, #{catalyst}, #{lightning}).
- a test spell or fixture carrying a Heat ride row (test-only).
- `docs/domain/explosive.md`: a short "Burning's disc" paragraph beside go-off zero's (#{catalyst} rewrites the file); the elements domain doc #{defs} opens gets Fire's band.

**Acceptance**
1. `test/unit/elements/test_burning_go_off.gd` (red first): a hit on a node with Heat > T goes off as a disc. The reach grows with √excess (a ratio test across two powers) and excludes the centre. The disc spends 1 Heat per node reached and may leave Heat under T.
2. Same file: a disc reaching no other node spends nothing and lands no copy. Heat ≤ T lands plainly (no copy, no spend).
3. Same file: power is read after the hit's Heat rider lands, so repeated 1-Heat hits on a sub-reach node grow the disc until it first catches a neighbour. Each copy carries `share` of the payload plus `damage_per_power × power`.
4. Chains: a copy's Heat rider lands on the reached node, and a reached Burning node goes off in turn, once per node per hit.
5. Dual reach: a node holding both Explosive charges and Burning sets off both discs in one hit, and a node inside both takes two entries, each with every rider and its damage.
6. Ride row: a spell with a Heat ride row writes Heat into the landed node's `t` and plants no status row.
7. Go-off zero's characterization tests (the files #{go-off-zero} leaves green) pass un-re-pointed, so this unit changes no Explosive behaviour.
8. Visible: a Burning disc plays on the blast VFX in Fire's colour at its reached radius, readable as different from go-off zero's. Check it in the sandbox host's blast tab; `mise run check` only.

**NOTES**
- The look may be handed to a sub-agent working in this same worktree once the hook it draws from (signal, record field, scene stub) exists; the unit's drone stays the owner and reviewer of the result.
- Reading list and seam map were cut before #{go-off-zero} (and the spine before it) landed and moved these lines. The dispatching lead re-checks `mise run issue-drift`. If it still flags this issue, stop and say so.
- Burn tick, light source, Heat addon and the Burning vertex are #{fire}. Fire arrows and the forge element field are #{forge} / #{quiver}.
- The no-parent go-off ("terrain hit", `:498-503`) is a defined shape with no caller, so it is not built.
- Firecracker's row moves to Heat in #{catalyst}, not here.

**Stubs on master**: none. The shapes are named in Composition; the drone adds them.

```drift-stamp bd800181
docs/design/elements.md:70-113 — the trigger table, what a go-off pays, power post-land, the disc's size
docs/design/elements.md:346-360 — element statuses ride as Poison rides
docs/design/elements.md:460-503 — the reach rule, chains, the no-parent go-off
docs/design/elements.md:704-726 — one share, go-off zero, the disc subclass on the Element def
docs/design/elements.md:744-753 — dual reach concatenated, the dedupe switch
docs/design/elements.md:891-909 — temperature, Burning ignites
effects/status/spread/explosive_spread.gd:41-81 — today's disc: radius from power, one finder per reach
attack/spell/on_hit/detonate_effect.gd:91-121 — today's detonation the port starts from
attack/range_finder/euclidean_range_finder.gd:93-100 — nodes_within over a list, the blast path
ui/vfx/blast_vfx.gd:24-60 — spawn on blast_landed, layers_for per rider
docs/domain/explosive.md:93-175 — the blast carries the hit, chains, the knobs (reach_per_radius 3.0)
attack/spell/aspect_intake.gd:18-75 — the intake row a Heat ride row is
effects/status/spread/explosive_spread.gd — seam: the disc go-off zero ports
ui/vfx/blast_vfx.gd — seam: the per-element disc look
ui/vfx/blast_visual.gd — seam: the ring the look restyles
aspects/aspect.gd — seam: blast_layer, the field name an Element keeps
addons/sandbox_host/tabs/71_blast_panel.gd — seam: the blast sandbox tab
docs/domain/explosive.md — seam: the Burning's-disc paragraph
```
