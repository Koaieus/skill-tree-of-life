# Elements design — continuation prompt

Paste the block below as the first message of the next session. Everything it
names is on master; nothing lives only in a transcript.

---

Continue the elements design pass (#1716 is the hub). **Read nothing in
full** — `docs/design/elements.md` is ~950 dense lines; a session that reads
it whole is at 150k before the first fork (it happened twice, 2026-11-09).
Open with one `Explore(model: haiku)` that returns, per item below, the doc
section + line range and the owner quote verbatim with its date, and read
only those ranges. The seam facts are already in § 2 here: do not re-grep.

The design is **settled** (ADR 0072, 0075, 0081, 0082 — 0082 reached master
2026-11-09 evening, 895e9c06). Work `AskUserQuestion` case by case,
recommended first; write each verdict into the doc with quote and date;
commit, push. **Local session: commit on master, no PR; pull/rebase onto
origin/master before editing and before every push.** Cloud session: a
docs-only PR (auto-merge takes `docs/design/` and `docs/handoffs/`, never
`docs/adr/`); the board (`mise gh-project`) is GraphQL, so the split needs a
local session. `mise run docs-hygiene` after a design doc, `adr-hygiene`
after an ADR. `gh issue view` is blocked; use `gh api
repos/Koaieus/skill-tree-of-life/issues/<n>` and `/comments`.

**Settled 2026-11-09, evening pass (owner quotes in the doc):** acquisition
— v1 sources are the aspect sources (school pool roll, inner tree, found and
stolen mods); starter count **1 in every element for now, 3 each for the dev
sandbox Player**; later 0 with gains from the inner tree / core class /
metagame / board keystones. **Generator keystones** filed as #1787 (Needs
design; +2 stacks per world tick, not a hit so no go-off, Charge piles to
~4T). **Catalyst is an aspect status on allocated nodes only**, clearing with
its holder like Poison — not terrain (owner lean taken as settled, hedge
*"but we can always make an exception"* noted: `explosive.tres` leaves
`on_dealloc` at its default CLEAR, so the retag changes no lifecycle). **ADR
0081 §6's "one side-less terrain status" wording is stale** — carry the
correction into the next element ADR. **A blade's element is an addon
per element**, rider only, no stat. **A blade vertex copies its source
node's primed state** (Burning vertex booms, Shocked vertex arcs, Frozen
vertex is brittle). **v1 spells:**
`lightning_bolt` carries Charge; a **new single-target Cold spell** whose
innate Ice row concentrates it to 0 hops, swap the element at the forge and
hops return. **Melee crit condition** filed as #1786 (Needs design, P0; crits
shatter Frozen). Doc fact fixed: spell shrapnel rolls its *own* crit today
(`paired` null → `draws_own_crit()` true), it does not draw none.

**Settled 2026-11-09, night pass (owner quotes in the doc: § The forge,
§ Acquisition, § Open's v1 spell content):** the Cold spell's signature is
the crit condition **Thermal shock** (crits when the target's terrain holds
a different element than the cast carries; with Fire swapped in, the
restored chain shatters every Frozen node it walks). **Whip-crack** (crits
where the walk ends) is parked for a Fire spell, not v1. **Element arrows
are their own ammo type, one per element**, minted 1:1 from the count into
their own bin, a card in the volley order; an arrow is an aspect subtype or
an element, never both; no cap on elements per volley — the "element
orthogonal to subtype" passage is deleted, and "which arrows take the tag"
is dissolved. **Catalyst starts at 1** (dev sandbox Player 3), same interim
rule as the elements. **A vertex go-off spends the copy, never the source
node.** **The Frozen vertex's snap is a concentrate**: one contact hit, then
the vertex pops; the bonus is an overlay on that vertex's `blade_damage`
read at fill, scaled by Cold excess at fill.

**Settled 2026-11-09, late pass — the five seams (owner quotes in the doc:
the terrain bullet of § What an element is, § Order's build shape, § Open's
adversarial items a/b/h):** **terrain is node state** — two ints on
`NodeState` (signed `t`, Charge), cloned by every shadow world for free;
Heat/Cold/Charge stay `StatusDef`s whose landing writes the node's ints; the
diffusion pass gathers packed arrays as scratch over a live-only index.
**Row keys**: a row names the status it plants (#1660 B2), the forge budget
stays keyed by concept, everything else walks the rows. **The count's
role**: `StatDef.Role.ASPECT` renamed `COUNT` (one role for a concept's
count); `Identity.Kind.ELEMENT` added, presentation only; an element is its
own `Element` def beside `Aspect`, a shared `Concept` base deferred (keep
`Aspect`'s field names). **Riders**: one summed entry per status id per
landing entry. **The resolver**: a land-time gather (not compile-time), unit
= one hit (an arrow, a blade contact, one arrival of a spell wave — a wave is
N gathers), a gather hit at span head is the only terrain writer, stage two
is the existing compile-and-land path per entry, an element answers *admits*
and *go off*.

**Settled 2026-11-09, resolver pass (owner quotes in the doc: § Landing
resolution's "The resolver's five build calls"):** a spell's **crit is per
arrival, decided at the head of its gather**, crit conditions included
(evaluated against the pre-hit node; a copy never re-evaluates); **each hit
owns its once-per-node set and hits of one beat settle terrain from one
snapshot** (generation by generation, sums committed together and clamped at
0 — the same routine the world-turn tick uses; the per-wave `detonated` scope
goes); **one share scales the whole payload** (damage and every rider's
stacks, ceil per rider; one knob per go-off, default 0.5); **today's
detonation is ported first as go-off zero** on a `GoOff` resource that sits
on the `Element` def (owner call; disc subclass, later an edge subclass for
Shocked; no `ArcEffect`; go-off zero's disc rides the Explosive `Aspect` def
under the same field name until the retag — pass pick); **the applier drains an open
worklist**, hits compiled through one stamping callable.

## 000. Local session 2026-11-10 afternoon — READ THIS FIRST; it supersedes § 00 where they differ

**State.** Nothing is on the board. On master: the stale facts of § 0 are
fixed in `elements.md` and `aspect_matrix.md` (`efba0bc3`); the cloud
session's three cast-shapes commits are cherry-picked (they had been left on
`claude/eager-dijkstra-clrnfl`, unmerged); in `docs/handoffs/elements-split/`
sit `ORDER.md` (the clerk work order), `inner-tree.md` and `adr-fixes.md`
(the two sibling bodies), `split-comment.md` (the hub comment) and
`close-<n>.md` (six closing comments).

**Settled 2026-11-10, late afternoon (owner quotes in the doc: § The
threshold model "Size", § Shape and ride):** the disc is r = A × (√power + B)
× node radius, A=2 B=1, one radius for Burning's go-off, its light and the
Fire shape; Lightning's shape talks in levels (level N = every node within N
hops, cost 1+…+N points); Fire's shape feeds the same formula with points ×
a multiplier (knob, tentative 5; ballpark, not a fit); a shape and a primed
node of the same element add into one go-off (Lightning level N on a Shocked
level M node arcs N+M); a shape-added landing carries what a go-off copy
carries. Probe: `tools/disc_reach.py`; tables in
`elements-split/cast-shapes-rates.md`.

**Settled 2026-11-10, evening (cloud session; owner quotes in the doc:
§ The threshold model, § The forge "Overqualified casting", § Shape and ride,
§ Ice on a cast, § Landing resolution):** every fork of the "Open after it"
list is answered.
- **Riders first.** A hit lands its terrain riders, *then* primed-ness and
  power are read: the hit that tips a node over T sets it off. Frozen admits
  a copy on arrival; its path-end and break check read after the riders.
  Crit conditions still read before the riders. Per target, aspect riders
  still land before damage. **This reverses ADR 0082's pre-hit read**: add
  it to the ADR-corrections sibling's list, and `resolver.md`, `burning.md`,
  `lightning.md`, `ice.md`, `pairs.md`, `go-off-zero.md` must be checked for
  "pre-hit" wording.
- **Fire adds the roots** (√(points × multiplier) + √excess); **the node
  pays its solo cost** (pass pick: at least 1).
- **A shape and a go-off of another element concatenate**, the dual-reach
  rule, one dedupe switch.
- **Ice on Frozen: hops cut add to the shatter** (× a knob), not a breaker.
- **Ice hop price: one number per spell, default 0.5.**
- **Forge: three kinds of slot** — the element field is the shape, a second
  field is the ride (one terrain element at most, may differ from the
  shape), aspect slots untouched; ride points count against the spell's
  `infusion_capacity`.
- **Overqualified casting** (new mechanic, needs its own issue): capacity =
  base 10 + 5 per degree above `min_degree`; the loadout gates the caster
  (the target union filters sources by it; the pick stays highest
  `spell_damage`); UI asks: a reset-to-base control with a "n targets
  hidden" hint, the real cap shown once a target is picked. Code anchors:
  `attack/targeting/spell_target_union.gd:125-224` (sources, pick),
  `attack/plan/magic_attack_plan.gd:759-770` (overrun check, launch only),
  `attack/spell/spell_def.gd:79,135` (`min_degree`, `infusion_capacity`),
  `systems/armed/armed_stack.gd:137` (clamp). #744 is the neighbour.
  Stale: `stats_system/defs/infusion_slots.tres`'s description says 100 /
  1000 / 10000, the board grants at 10 / 100 / 1000.

**Settled 2026-11-10, night (owner quotes in the doc: § A blade on Frozen,
§ What breaks the ice):** **a blade vertex's touch breaks the ice only if
the vertex is at least as heavy as the node** — weight is the sim mass
`(radius / 32)²`, Bunker's `blade_mass` counts, nothing per-contact (Cold
drag) does, a tie breaks. A lighter vertex still snaps and the ice holds;
fallback if that nerfs melee too much: the vertex deflects off the ice like
a defender plate (deals nothing, nothing breaks). Only the touch is gated:
a light vertex's contact that crits or would deal threshold damage still
breaks it. Carried into `elements-split/ice.md` (Decisions, Composition,
acceptance 8 / 8b).

**ADRs filed 2026-11-10 evening:** 0083 (riders first; 0082 §1 in part), 0084
(shape and ride, the disc formula, same-element add-up, solo cost,
concatenate, shape-blind reach, arc transfer, the Ice concentrate and its
price; 0081 §1 and §8 in part), 0085 (three forge slots, ride points under
`infusion_capacity`, overqualified casting; 0081 §7 in part). The
ADR-corrections sibling shrinks to what they do not cover: 0081 §5, §6
(Catalyst is an aspect status, not terrain), §9; 0082's Context; 0061, 0062,
0070 — rewrite `adr-fixes.md` from this line. The bodies cite 0081 / 0082
for calls these three now carry; fix in the body pass.

**Settled 2026-11-10, night, after the ADRs (owner quote in the doc:
§ Landing resolution, "Every landing is a whole hit"):** the share's default
is 1, not 0.5, and each channel that goes off also lands on its own node —
hit node 1 + 1 per channel, a reached node 1 per channel. Terrain riders
still once per node per hit. **This changes ADR 0082's share default and
ADR 0084's "the seed node takes the seed once"** (decision 5): one more
record, or the corrections sibling. Bodies touched: `resolver.md`,
`go-off-zero.md`, `burning.md`, `lightning.md`, `pairs.md`, the cast-shapes
body, and the Ice combo arithmetic (×4 seed now copies at ×4). A shape
alone is not a channel for the seed (owner); a shape added into a
same-element go-off counts as that node's one channel (pass reading). Open:
Frozen's shatter tuned to match.

**Open after it, none blocks the split:** whether shape points count against
the capacity too; the knob for hops cut → shatter; the Fire multiplier (5,
tentative); the min-1 pass pick above. `ice-cast.md` (the cast-shapes menu)
is now almost wholly answered: rewrite it from the doc as a spec, or fold it
into the forge units — a call for the body pass.

**Owed in the bodies (do once, before the range pass):** `burning.md` — the
size Decision and the knob (`radius_per_node_radius` 1.0 becomes the two
knobs A=2, B=1); `fire.md` — the light-radius line (same formula);
`go-off-zero.md` keeps ×3.

**Owner on how this pass must run** (2026-11-10): *"a session that mainly
first should read the bare minimum of getting a full grip of what is to be
settled, then settle it, think about it, see to it that it makes right, then
update issue bodies, and lastly, right before filing them, we update them in
terms of line numbers because this has just eaten an entire session for
something that might gotten stale by the end of it and we hadnt even started
the real discussion yet"*. So: discussion first, bodies once, line ranges
and stamps as the very last step before the clerk. Worth a law in the `spec`
/ `swarmify` charters (`/charter`).

**Before the clerk runs, in this order:**
1. Any design talk the owner still wants (cast shapes is its own `Needs
   design` issue and blocks nothing).
2. Bodies: `ORDER.md` still files `{ice-cast}` as a
   `Ready` child blocked by forge and forge-ui — it is the "Cast shapes"
   `Needs design` menu now, a sibling with no parent and no blockers, its
   title on the body's first line (strip that line and the lane line from
   the body); `split-comment.md` lists it under the late units — move it to
   the siblings; `adr-fixes.md`'s §8 line states the flat price as settled —
   it is a lean (§ 00); `refresh.md` says "eight" and names a
   `drift-stamp bd800181` in prose; `forge.md:11,73` cite a "3 units of
   int:int" quote the doc no longer holds; `defs.md:64` asks for two doc
   fixes that are already done.
3. Last: every `elements.md` range in the 20 bodies was verified at
   `efba0bc3`, but `forge.md` and `ice-cast.md` were then replaced by the
   cherry-pick, and the doc has since grown (+35 lines at § Shape and ride,
   +3 in § Ice on a cast, +8 at "Size"). One Sonnet pass re-places the ranges
   by content and restamps at the then-current master sha. Then the clerk
   with `ORDER.md`, then delete `docs/handoffs/elements-split/` and this
   file. `cast-shapes-rates.md` is cited by the cast-shapes menu: move it
   somewhere that survives (or inline its numbers) before deleting the folder.

**Pass picks in the order, the owner has not seen them:** #1733 / #1735 /
#1765 / #1660 / #1695 / #1696 close now as completed with a pointing comment
(`go-off-zero.md` still says #1733 closes when it lands); the ADR-corrections
sibling goes to `Backlog`; labels `ui` on the two display units, `tech-debt`
on `applier`.

## 00. Fork pass 2026-11-10 (cloud session) — READ THIS FIRST; it supersedes § 0 where they differ

**State.** Nothing is on the board yet (a cloud session has no board access).
Every fork is answered and carried into `docs/design/elements.md` and the 21
bodies in `docs/handoffs/elements-split/`; the reviewer leftovers are fixed.
What remains is board work for a local session: the clerk order of § 0's
"Where the pass stopped", then the stale facts, then deleting the bodies and
this file.

**Owner calls, 2026-11-10 (quotes in the doc at the bold lead-ins named):**
- **A go-off picks its nodes by shape alone, at every level** — Burning's
  disc and a Shocked arc reach unallocated nodes too. Backup, not built:
  allocated-only at level 1 and whole graph at 2+, for Fire and Lightning
  together. In `resolver.md`, `burning.md`, `lightning.md`.
- **A blade follows the same rule** (one snapshot): two contacts of one
  sample on one node read the pre-beat store, spends summed; the blade ledger
  dies. In `go-off-zero.md`.
- **Shape and ride are two things an element does on a cast** (doc § Shape
  and ride): ride plants terrain (the whole split); shape reshapes the
  cast's own walk at once and plants nothing — Fire widens the seed into a
  disc, Lightning adds whole hops, Ice cuts hops and pays the seed. The
  caster picks each independently. Direction only: `ice-cast.md` is the
  `Needs design` menu for it ("Cast shapes"), four forks with tentative
  picks, filed as a sibling of the hub as § 0 says. Settled inside it: Ice's
  shape is a `ConcentrateUse` on the Ice row, its bonus never scales Heat /
  Cold / Charge stacks, 1 Ice = 1 hop authorable per spell, counts run 0..5
  (10 at most). **Not settled**: the price (+50% per hop is a lean the owner
  doubts), one forge field or two, split or shared count, what a point buys
  for Fire and Lightning. `forge` ships an element on a cast as a ride only.
  ADR check done (librarian, 2026-11-10): ADR 0073 and 0075 reject reach on
  a *hit*; a shape on the *walk* is what 0075 §2 allows.
- Earlier the same day, already in the doc: the arc released by breaking ice
  reads its power after the breaking hit lands; a node's own go-off fires
  once per hit; an arc transfers its Charge (knob, transfer by default). All
  three are now in `pairs.md`, `resolver.md`, `burning.md`, `lightning.md`.

**The ADR-corrections sibling issue's list** is now: 0081 §1 (transfer for
arcs), §5-§7, §7 and §8 if the cast-shapes issue changes the one element
field or the Ice price, §9; 0082's Context; 0061, 0062, 0070. The bodies'
NOTES still cite the shorter list; the sibling issue's own body is written at
the clerk order from this line.

**Still open, none blocks filing:** overflow-band decay 2 / 3 / proportional
(a knob in `defs.md`, owner: *"idk yet"*). Tentative pass picks: the vertex's
copied state as a "go-off source" argument; the pass-through Charge spent at
the arriving wave's gather head; no int:int seam on `AmmoType`; the catalyst
/ catalyst-blade interim; the three transfer readings in `lightning.md`.

**Blade ledger, verified in code.** The swing lands as it simulates, one
sample's contacts per batch (`attack/melee/swing_resolve.gd:228-240` →
`_land_batch` `:442-529`); a spend is deferred to the end of its batch
(`_flush_spends` `:393`), so `_node_spent` exists only for two contacts of
one sample on one node.

**Not done here:** `BRIEF.md` and the two `anchors-*.md` files still describe
`ice-cast` as a menu and cite this file's old line ranges; they are the
writers' brief, deleted with the folder, never filed. `docs-hygiene` ran green
on this pass.

## 0. Split pass 2026-11-10 (night) — state, supersedes § 3's child list where they differ

**Owner calls, 2026-11-10 (verbatim):**
- Pair rules are their own unit after Fire / Lightning / Ice: *"option 1. or
  whichever fits a DAG."*
- Visuals: small looks ride their mechanics unit, a large display surface is
  its own unit: *"option 1"*, plus *"the drone may offload that work to a
  sub-agent drone of their own … they work on the same thing anyway so they
  can coordinate closely and share a worktree"* (a NOTES line in each spec
  with a visual; a standing drone law would be a `/charter drone` pass).
- Every child goes `Ready` now, with a spec-refresh issue blocking the later
  ones: *"all children ready, but add 1 extra issue … make it be blocking
  later ones. and that issue just tells to update the specs?"*
- The inner-tree shape for elements and the card cadence: filed as its own
  `Needs design` issue (sibling of the hub).
- The count's stat id is `fire_element` / `ice_element` / `lightning_element`,
  shown as "Fire attunement" (owner picked it over `fire_attunement` and a
  bare `fire`).
- Ice on a cast (the concentrate) is `Needs design`: *"yeah needs design that
  one, just stub it as an unconditional ×1 until we fix it/decide on it"* —
  an Ice load on a cast leaves hops alone and scales the seed ×1; the stub
  line sits in the forge unit.

**Owner calls on the forks the spec writers raised, 2026-11-10 (verbatim
where quoted):**
- **World-turn rate**: an exported rate rule on the turn manager (per-carrier
  = today, or integer ceil-sqrt), default per-carrier — *"Same rule, linear
  default"*. ADR 0055 stands; no behaviour change.
- **Charge decays in the world-turn pass** with Heat and Cold (owner picked
  it over decay on read). Terrain is exactly two ints; the doc's build note
  (`elements.md:929-931`) is corrected by the `flow` unit.
- **The blast gap**: Burning's disc lands before the Catalyst retag — *"option
  1 but spare no drones, split if needed"*. Master always has a blast.
- **Firecracker**: its row names Fire and plants Heat; `FuelUse` and
  `FuelBlastReach` die at the retag. Aside: *"btw infusing Firecracker with
  Catalyst naturally makes it more effective!"*
- **Sweep speed on temperature acts per contact** (the factor scales the
  speed the existing speed-to-damage curve reads on that node) — *"option 1
  seems best"*. Parked aside: *"also maybe easiest: tune the PBD weight?"*
- **Starter 1 goes to every entity** (the stat's default) — *"every entity.
  and possibly later we can decide to replace it with statmodifiers innate,
  meaning they can get looted too."*
- **`lightning_bolt` keeps its name** for now; it only gains its Charge row.
- **Dual reach**: *"riders twice, payload twice. charged burning nodes sounds
  like a dangerous concept"* — a node gathered by two reaches is two entries,
  each landing every rider and the damage. Pass reading, unconfirmed: the
  node's own go-off still fires once per hit.
- Tentative pass picks, not owner calls: a vertex's copied state reaches the
  gather as a "go-off source" argument; Lightning's pass-through Charge is
  spent at the arriving wave's gather head; no int:int seam on `AmmoType`.

**The split, final** (handle — blocked by): `defs` — none · `terrain` — defs ·
`flow` — terrain · `terrain-ui` — terrain, flow · `applier` — none ·
`resolver` (the gather) — defs, terrain, flow, applier · `go-off-zero` —
resolver (closes #1733, #1735) · `burning` (Heat ride row + Burning's disc) —
go-off-zero · `catalyst` (retag, conversion, Firecracker, docs) — burning ·
`catalyst-blade` (blade-side explosive teardown) — catalyst · `refresh`
(re-cut the later specs; board only) — catalyst-blade · `blade-elements`
(addons, vertex copy-on-fill, sweep speed) — refresh · `fire` (burn, light,
addon, vertex) / `lightning` / `ice` — blade-elements · `pairs`, `forge`,
`quiver` (closes #1765) — fire, lightning, ice · `forge-ui` — forge, quiver,
terrain-ui · `ice-cast` — `Needs design`, a written menu (cast shapes). Siblings of the
hub, not children: the inner-tree shape + card cadence (`Needs design`); the
element ADR corrections (0081 §5-§7 and §9, 0082's Context, 0061, 0062,
0070). Frostbite #1444 stays its own issue, blocked by `ice`. #1660 / #1695
/ #1696 close into `burning` + `fire`. Milestone: the hub's, "Content depth".

**Where the pass stopped (context budget).** The bodies are drafts in
`docs/handoffs/elements-split/` (one `<handle>.md` each, `BRIEF.md` is the
shared brief with both rounds of rulings, `anchors-*.md` the verified code
anchors at `bd800181`). **Nothing is on the board.** Next session, with board
access: read each body cold (spec skill § 1), check Decisions quote the
owner verbatim and no `OPEN FORK:` line survives outside `ice-cast`, then one
clerk work order: create the children under #1716 with their `blocked-by`
relations, `Ready` (except `ice-cast`), milestone, the two siblings, close
#1733 / #1735 / #1765 / #1660 / #1695 / #1696 into their units with a
pointing comment, post the split as a comment on #1716 and drop its `design`
label, check the drift stamps, hygiene. Then fix the stale facts below,
delete `docs/handoffs/elements-split/` and this file.

**Before filing, in this order** (owner, 2026-11-10: *"yeah add that for
the next session"*):
1. **Verify the blade ledger's timing, before `go-off-zero` is filed.** Both
   spend ledgers were planned to die, but the blade one
   (`attack/melee/sim/blade_pop_resolver.gd` `_node_spent`, spends at
   `:329-341` and `:410-418`, `take_spends` `:402-408`) was deleted on the
   writer's unchecked claim that each contact lands at its own key
   (`attack/melee/swing_resolve.gd:485`) so the previous spend is on the
   world when the next gate runs. Check it: does a contact's hit land before
   the next contact's `LiveGate.admit`, or does the sim decide the whole
   swing first and land afterwards? If the sim runs ahead, the ledger stays
   as the sim's working copy (only the spell-side `detonate_effect.gd`
   ledger goes) and `go-off-zero.md` is corrected before it is filed.
2. **Shocked conduction at 0 hops is settled: the walk still leaves.**
   A spell walk entering a Shocked node leaves without spending a hop, 1
   Charge per pass-through (`elements.md:855-858`), and that holds when the
   walk arrives with 0 hops left — owner, 2026-11-10: *"i forgot i designed
   that as a feature. it's rather powerful, not spending a hop. but might be
   just what it needs"*, then on keeping it including the 0-hops case: *"i
   agree with that lean."* Already applied in `lightning.md` Decisions; the
   conduct cost is the knob if generator keystones (#1787) make wires
   permanent.
   **Parked owner idea, not decided, a NOTES line in `lightning.md`:** *"wires
   might even be draining *too* fast, i think the fix would be to spread 1
   Charge to each affected neighbor instead of voiding as many, but that
   could complicate timings badly if not thought through perfectly"*. Pass
   notes for when it is picked up: the timing is not the hard part — the
   gather already commits every terrain change of a beat as one set of sums
   from one snapshot, so a transfer is a +1 on the reached node in the same
   commit as the -1 on the source, primed states are read pre-hit and the
   once-per-node set bounds the cascade; nothing touches the C++ XPBD solver
   (it is blade physics; terrain and the resolver are GDScript). The hard
   part is balance: it makes Lightning's go-off a redistribution instead of
   a cost, against the one spend law of ADR 0081 section 1 (an interior node
   of a line wire would give 2, get 2 back and lose only the conduct cost
   per spell, so only decay ends a wire). Shape if wanted: where the spent
   Charge goes (void, or the reached node) as one exported choice on
   Lightning's edge go-off, void by default.
3. Then the cold review and the clerk order below.

**Look at these first in the cold review** (the writers' own flags):
- `go-off-zero` deletes the blade's per-swing spend ledger `_node_spent` on
  the reasoning that each contact lands at its own key — unverified; the
  body tells the drone to stop and report a fork if a gate still needs an
  unlanded spend. Its disc class must accept a power source other than the
  old charge formula, or `burning` cannot reuse it.
- `terrain` puts the one live index of terrain-holding nodes on
  `CombatWorld` (shaped like `_lingering`); `flow` must read that index, not
  build its own. `flow`'s Blocks line and `terrain-ui`'s power-line note
  still say `fire` where they mean `burning`.
- `forge` says the resolver reads the cast's `element_of`; `resolver` lands
  long before `forge` and must not assume that accessor.
- `catalyst` only re-points the blade's three explosive id literals, so
  until `catalyst-blade` lands a swung vertex still spends Catalyst as
  charges (tentative pass pick). `catalyst-blade` removes "a node's blast
  pops plain blade pieces" (ADR 0062's node side) with nothing replacing it
  — parked in its NOTES as a possible design issue.
- `pairs`: whether the arc released by breaking ice reads its power before
  or after the breaking hit lands (`elements.md:810-811` vs `:93-96`) is
  unsettled; the test passes under either. Owner call wanted.
- Owner, 2026-11-10 (late): *"butn 1 per stack, light radius same formula
  as explosion size would. overflow decay idk yet 2 or 3 or proportional"* —
  burn is 1 per stack (applied in `fire.md`, read as per stack above T), the
  Burning light radius is √power × node radius (applied in `fire.md`; any
  other light-radius line there needs the same fix), overflow-band decay
  stays a knob at 2, undecided (`defs.md`). Asked and not yet answered:
  whether a spell walk arriving on a Shocked node with 0 hops left is
  conducted onward (`lightning.md` Decisions + Acceptance 4 say yes,
  tentative).
- `ice-cast` is a `Needs design` menu (three forks); `quiver`, `burning`,
  `go-off-zero`, `catalyst-blade` are units the § 3 list never had.

**Pass rulings** (doc beats this file's § 3): a planting hit is a hit and
sets off a primed node (`elements.md:484-487`); the no-parent go-off has no
caller and no unit builds it (`:498-503`) — § 3's "lands with 6 and 7" is
stale; prime conversion of Catalyst is read inside the world-turn settle,
never hooked on `terrain_band_changed` (display-only, `:842-848`); Catalyst
is an aspect status row and keeps its own decay; no stubs on master.

**Stale facts found, to fix when the bodies land:** `aspect_matrix.md:280`
and its Glossary call Catalyst "side-less terrain" and name an element's
"reach load"; `:535` calls resting Cold "Frost"; `elements.md:253` says the
count is `fire`; `:624-625` says Pestilence concentrates "from 4 hops"
(`pestilence.tres:40` is 6); the two seed prices for the concentrate
(`:580-584` per-hop multiplier vs `:610-611` mass beyond the limit — ×3.5
against ×61 for Pestilence 6 → 3) go to the `ice-cast` issue; five
landing-to-hit stampers exist, not three (`haul_effect.gd:47-54`,
`splash_effect.gd:128-146` are not folded); 25 test files name the role, not
31; `blade_pop_resolver.gd:238` and `:421-423` are a declaration and an
accessor, the spends are `:329-341` and `:410-418`.

## 1. Design beats still open

None for the resolver. Spec-time anchors for child 4, verified on master
2026-11-09 (night Explore): `draws_own_crit` is `paired == null`
(`attack/outcome/hit_instance.gd:323-324`; cure and cleanse-price override
it false), read only by `CritRoll.decide` (`crit_roll.gd:59`); spell crit
conditions are stamped at compile (`spell_resolver.gd:551-560`); `detonated`
is per wave (`spell_resolver.gd:297,336`), per landing elsewhere
(`hit_landing.gd:85`); splash scales stacks only (`splash_effect.gd:51`),
the shrapnel fraction is `paired_damage_effect.gd:19`; the spend ledgers are
`detonate_effect.gd:38-40,110-111` and `blade_pop_resolver.gd:238,391`;
`OutcomeApplier.apply` sorts a fresh copy at entry (`outcome_applier.gd:30,
170-181`) and the spell lands a fixed index range through `land_one`
(`spell_resolver.gd:373-374`); the post-compile stamps are two, not three
(`spell_resolver.gd:347-360`, `ranged_damage.gd:104-105`;
`swing_resolve.gd:524-527` only appends sub-outcome hits); the three
landing-to-hit stampers are `status_instance.gd:76-85`,
`detonate_effect.gd:166-177`, `paired_damage_effect.gd:43-51`. Detonation's
tests: `test_explosive_charges.gd` (27), `test_paired_damage_effect.gd`
(12), `test_blast_mark.gd` (6), `test_blast_effect.gd` (5),
`test_heal_spell_blast.gd` (2). **ADR 0082's Context is wrong about today's
code** (it says spell shrapnel's `draws_own_crit()` is false; shrapnel rolls
its own crit) — carry the correction into the next element ADR with 0081
§6's.


Nothing else blocks the split. The Cold spell is filed as **#1789** (Needs design;
the owner wants to go over it again): its open list carries the unconfirmed
pass reading that Thermal shock's "holds a different element" means the
*primed* state (Burning, Shocked, Frozen), not stray stacks under T, plus
the hop count, the Ice form as its own ice pick, and the Lightning form.
Child 7 (Ice) takes the spell from #1789, not from this file.

Seam facts for the picks above (2026-11-09 Explore): a contact hit is
`vertex_damage[i]` × the speed curve (`attack/melee/sim/blade_damage_instance.gd`
`land_on`); `vertex_damage` is `blade_damage` read off the source node at
fill with the swing's overlays (`attack/melee/blade_vertex_fill.gd:30-40,
64-66`, `attack/plan/melee_attack_plan.gd:596` `overlays_for`); no overlay
can attach to a single `HitInstance`; a vertex dies through
`BladePopResolver.LiveGate._kill` (`attack/melee/sim/blade_pop_resolver.gd:603`), and nothing
pops on first contact today, so "brittle" is a new per-vertex flag on
`BladeState` beside `vertex_charges` (`blade_state.gd:91`). Spell crit
conditions are `SpellDef.crit_conditions` (`spell_def.gd:141`), stamped in
`spell_resolver.gd:551-560`; ranged and melee have no condition path. An
element ammo type is the existing shape: `per_reload_stat_id`,
`on_hit_effects` with one `ApplyStatusEffect`, `order`, `max_stock`
(`attack/ammo/ammo_type.gd:38-59`); `explosive_aspect` defaults to 0.0
(`stats_system/defs/explosive_aspect.tres:15`), so the Catalyst starter is a
board value to add.

## 2. Architectural seams — settled (above); the facts below are spec-time anchors (2026-11-09 Explores)

Added by the late pass: a shadow world clones a node lazily on first touch
(`combat/entity_combat.gd:379` `shadow_for` → `combat/node_combat.gd:98-105`,
which clones the `StatusHost` and `NodeState`); `SkillNode.state` is the
`NodeState` (`skill_node/skill_node.gd:84`, `skill_node/node_state.gd:14-45`);
`_lingering` is live-only (`combat_world.gd:191-193`); there is no dense
stable node index (`stable_id` is sparse, `graph/graph.gd:88`); per-node
replication is the `_R_*` slots of `network/graph_snapshot.gd:13-27` plus a
save-version bump and a `command/world_fingerprint.gd:62-73` fold. No
gameplay reads `Identity.kind` (`identity/identity.gd:10,15`; readers are
`ui/identity_badge/`, `ui/concept_card/concept_card.gd:47`,
`infusion_socket.gd:188`, two sandboxes). No code matches on `StatDef.Role`;
`facet_def` callers are `attack/aspect_currency.gd:20`,
`attack/ammo/ammo_type.gd:52`, `effects/status/status_def.gd:93`,
`stats_system/stat_board.gd:168`; 31 test files name the role. `Aspect` is a
flat bag (`aspects/aspect.gd:17-32`: identity, stat, status, ammo,
addon_scene, spells, blast_layer) behind `AspectRoster`
(`aspects/aspect_roster.gd:13-28`). Same-id riders merge today only at the
host (`combat/status_host.gd:76-93`). The intake row is `AspectIntake`
(`attack/spell/aspect_intake.gd:18-39`), 20 authored rows, none sharing a
concept on one spell.

- **A terrain row that survives death** (moot for terrain now it is node
  state; kept for the stale-comment fix). `on_dealloc` is exactly CLEAR |
  LINGER (`effects/status/status_def.gd:31-45`). Voluntary dealloc keeps
  LINGER (`systems/allocation_system.gd:310` → `combat/status_host.gd:277-286`
  with `keep_lingering=true`); node death (`combat/entity_combat.gd:727,
  970-975`), force-deallocate (`allocation_system.gd:337-338`, CAUSE_DEATH)
  and entity death (`entity/entity.gd:1050`, `entity_combat.gd:773`) clear
  both. Core crack moves every row to the entity (`node_combat.gd:430`,
  `status_host.gd:260-268`). There is no retake strip: `force_allocate`
  (`allocation_system.gd:223-250`) keeps the previous rows. Stale comment:
  the `OnDealloc.LINGER` doc block in `status_def.gd:31-45` says a bare
  force_deallocate keeps LINGER — false. Catalyst is
  *not* in this seam any more (aspect status, CLEAR like Poison).
  `NodeStatus` records `camp_id` + `applier_id` of the latest applier
  (`effects/status/node_status.gd:18-19`, written `status_host.gd:153-155`).
- **Row keys.** `Infusion.load_of` / `use_of` key on the concept id
  (`attack/spell/infusion.gd:90,115`; `intake_of` `:50` takes the first row);
  `StatusRoster.by_concept` is a first-match scan on `identity.id`
  (`effects/status_roster.gd:26-34`); `StatusDef._facet_id` =
  `StatRegistry.facet_def(concept, role)` (`status_def.gd:91-94`). Callers of
  `by_concept`: `aspect_intake.gd:57`, `infusion.gd:119`,
  `ai_infusion_picker.gd:28`, `readout_lines.gd:113`. #1660 B2 (the row names
  the status it plants) — rekey by planted status id, or by row.
- **The count's `StatDef.Role`.** Role = {NONE, ASPECT, STACKS_PER_HIT,
  RESISTANCE} (`stats_system/stat_def.gd:14`); the mint loop is
  `EntityStatBoard.mint_facets` (`entity_stat_board.gd:233-238`, sparse
  boards skip); `AmmoType.per_reload_stat_id` falls back to the ASPECT facet
  (`attack/ammo/ammo_type.gd:46-52`). New ELEMENT role vs ASPECT + tag; a
  member keys its own facets (`heat_resistance`).
- **Rider coalescing** (#1741's NOTE): `HitLanding.place` orders BEFORE
  riders, the landing's own block, PRIMARY, rest (`attack/outcome/
  hit_landing.gd:137-156`); `detonated` is a per-node dedupe scope, fresh per
  spell wave (`spell_resolver.gd:297`) and per riding landing
  (`hit_landing.gd:98`), chained blasts share the parent's (`detonate_effect.gd:94`).
- **The two-stage resolver's home.** The blast table is `AttackRecord`
  (`attack/outcome/attack_record.gd:211-217`, rows are `BlastMark`s deduped
  `:700-713`); `CritRoll.decide` (`attack/outcome/crit_roll.gd:53-59`) is the
  one reader of `draws_own_crit`; copies also come from `status_instance.gd:84`,
  `splash_effect.gd:139`, `detonate_effect.gd:175`. `world_turn_ended`
  (`systems/turn_manager.gd:30`, emitted `:408` inside `end_turn`) has **no
  production subscriber**; `_lingering` (`combat/combat_world.gd:187-217`)
  ticks from `turn_manager.gd:406`. `DotTick.mint` (`effects/status/
  dot_tick.gd:24-48`) lands TRUE damage with no record; `CorruptionStatus`
  bursts through it (`effects/status/corruption.gd:27-28`).
- **Explosive artifacts** (retag targets, all verified on master):
  `LoadUse` set = `PlantUse`, `DetonateUse`, `CleanseUse`, `FuelUse`
  (`attack/spell/load_use/`); `DetonateEffect.arm` skips when an effect
  already lands explosive (`detonate_effect.gd:47-58, 69`), blasts via
  `ExplosiveSpread.blast_for` (`:98`; also `blade_pop_resolver.gd:421-423`);
  `BladeVertexFill.fill` copies node charges into `state.vertex_charges`
  (`attack/melee/blade_vertex_fill.gd:42-49`), the barrel adds a stack
  (`explosive_barrel_addon.gd:59-61`); `firecracker.tres:20-27` carries the
  `FuelUse`; `explosive.tres:20` carries tag `charge`; `dexterity.tres:239-271`
  rolls `explosive_aspect`; barrels placed by `first_level/content.tres:17`
  and `coop_versus/content.tres:16`; `explosive_face.tres` preloaded at
  `procgen/modules/blockers.gd:152`. No test guards Aspect:Status 1:1
  (`test/unit/aspects/test_aspect_roster.gd:32` counts 13 only).

## 3. Then the split of #1716 (needs board access)

Children (owner nod 2026-11-09 night: *"looks good to me"*), in dependency
order:

1. **Element counts and the `Element` def** — `Role.ASPECT` → `COUNT`,
   `Identity.Kind.ELEMENT`, the `Element` def with its ordered bands
   (threshold, identity, go-off, admits) + roster, member facets
   (`heat_resistance`), the Aspect:Status 1:1 guard test (`manage-stats`),
   the intake row naming its status.
2. **Terrain substrate** — two ints on `NodeState` + snapshot slot, save bump
   and fingerprint fold; T / k / cap / overflow, decay on read, the
   temperature index + integer Laplacian on the world turn; the band function
   and `terrain_band_changed`; the south-side bars and the `Burning 7/6`
   label.
3. **Applier refactor** — `OutcomeApplier` drains an open worklist, one
   stamping callable replaces the spell and ranged post-compile stamps, the
   three landing-to-hit stampers fold into one; no behaviour change.
4. **The two-stage resolver** — the land-time gather (ADR 0082), crit and
   crit conditions at its head, one terrain snapshot per beat, one share,
   detonation ported as go-off zero (both spend ledgers and the per-wave
   `detonated` scope deleted); #1733 closes into it.
5. **Explosive → Catalyst retag** — list in § 2; `charge` tag freed;
   land-phase conversion and the prime trigger; go-off zero's interim disc,
   `DetonateUse`, `vertex_charges` / `BladeVertexFill`, Firecracker's
   `FuelUse` resolved; `docs/domain/explosive.md` rewritten; Catalyst keeps
   CLEAR.
6. **Fire** — Heat ride row, Burning's disc go-off, burn, light source, the
   Heat blade addon, a Burning vertex; #1660 / #1695 / #1696 fold in.
7. **Lightning** — Charge, Shocked arcs to every neighbour, L² × T ladder,
   conduction, the Charge addon, a Shocked vertex; `lightning_bolt` renamed.
8. **Ice** — Cold, absorption, breakers + corruption-path burst, blade snap
   and the Frozen vertex's concentrate snap, Frostbite #1444, concentrate
   `shape` use, the Cold addon; the Cold spell with Thermal shock comes from
   #1789 (still Needs design — spec Ice without it unless #1789 is settled).
9. **Forge and quiver** — one element field per cast, 3 int:int units, the
   three element ammo types with their 1:1 mint + stock cap, starter counts
   incl. Catalyst 1; #1765 closes.

Order: 1 → 2 → 3 → 4 → 5, then 6 / 7 / 8 in parallel, then 9.
A go-off with no parent hit (a node priming on the world tick) lands with 6
and 7. Later, blocked on these: #1787 generator keystones; #1786 melee crit
condition (P0, independent).

Spec-time, not forks: adversarial (a) row keys → child 1 (the row names its
status) and 9 (the forge budget stays keyed by concept), (b) → child 1, (h)
summed riders → child 4. Parked: "a wire evens itself out"; the arc mirror
(child 7); the spike-pop docs-vs-code check (child 8).

### Coverage audit (2026-11-09 night, five Sonnet readers over the doc and ADRs 0072/0075/0081/0082) — fold into each child's spec

Owner: *"maybe add some visual items in there to fill any gaps in UI or
representation and let a bunch of sonnets verify the proposed split covers
the design"*. Assignments below are pass picks.

**Order corrections.** Child 9 lands **after 5 and 6–8** (element arrows
plant rows those build; the Catalyst starter needs the retag), not "any time
after 1". Child 4 deletes the per-*wave* scope only: the once-per-node-per-hit
guard survives as the gather's set. "Decay on read" (child 2) against the
doc's world-turn decay is checked at child 2's spec. The doc's "nothing
triggers a terrain hit yet … no caller" passage (§ The reach rule) against
"a no-parent go-off lands with 6 and 7" is settled at child 6's spec.

**Proposed child 10 — pair rules** (not yet nodded): what needs two elements
at once and so cannot sit in 6 / 7 / 8 while they run in parallel — Frozen
mutes a node's own go-offs and the breaking hit releases the trapped Charge,
Frozen ends an arc, dual reach concatenated with its dedupe knob, a Heat hit
thawing harder, Heat never touching a Frostbite pack. After 6–8.

**Mechanics no child named.**
- Child 1: `cold_resistance` / `charge_resistance` beside `heat_resistance`;
  the Heat / Cold / Charge `StatusDef`s themselves (identity, facets); the
  band's other answers (travel verb, decay rate, light); the element's
  school field and its pool roll in that school's pool; the Element Matrix
  (`Ammo : Addon : Spell : Infusion`) and the matrix Glossary / vocabulary
  guard ("Volatile" adopted or declined; "Face", "Payload" wording).
- Child 2: the world-turn clock itself (`ceil(sqrt(N))` played turn ends,
  exported; turnless hosts and lingering rows move with it); the diffusion
  pass as the *only* implementation (packed arrays, no GDScript mirror),
  roll-free and inside the transcendental ban; the blade sweep-speed curve
  on signed `t`; the Heat × Cold netting and the shared settle routine
  (child 4 calls it per beat); the sync-model doc line widened to the
  world-turn settle.
- Child 4: the go-off spend law for every element (1 per node reached, no
  other node reached → no go-off, digs under T); a hit carries 0 or 1
  element and a copy carries its root's; summed riders per status id and
  the rider order (element riders, other statuses, damage); the terrain hit
  (damage only, no riders, no crit, attacker = latest applier); the Frozen
  check's seat at the gather head (child 8 supplies *admits*); `PlantUse`'s
  "a planting hit does not trip its medium"; Greed never multiplies Heat /
  Cold / Charge; #1735 closes with #1733.
- Child 5: Catalyst's own cap k × T and slow decay; conversion hooked on
  `terrain_band_changed` for the "primes by any route" trigger; a goo arrow
  on an already-primed node; the item-15 orphans § 2 misses
  (`aspects/defs/explosive.tres` + roster entry, `identity/defs/explosive.tres`,
  `stats_system/defs/explosive_aspect.tres`, `explosive_stacks_per_hit.tres`,
  `attack/ammo/types/explosive.tres`, `entity/ring/aspect_ring.tscn`, the
  matrix's Explosive rows, `.claude/rules/explosive.md`,
  `attack/spell/propagation/reach/fuel_blast_reach.gd`,
  `addons/sandbox_host/tabs/71_blast_panel.gd` + `71_blast_tab.tscn`,
  `test_blade_explosive.gd`, `test_explosive_charges.gd`,
  `test_explosive_barrel_addon.gd`); ADR 0062's two-reservoir blade formula
  and `use_for_status` / `default_face`.
- Child 6: #1660's "death blasts first" is **dropped**, not built (a
  holder's death changes nothing).
- Children 6 / 7 / 8: the generic vertex copy-on-fill (a vertex copies its
  source node's primed state; a go-off spends the copy, never the source)
  lands with the first of them and is reused; the addon budget by element
  count likewise.
- Child 8: deep freeze (the shatter spends the overflow for bonus damage);
  the Ice pricing of existing spells (Venom Burst 2:1, Pestilence 4:1, the
  per-hop multiplier, "refuses Ice until priced by hand").
- Child 9: element bins sit beside the plain pool, not inside its capacity;
  the int:int seam on `AmmoType` and addons.
- Next element ADR (no child): 0081 §5–§7 are stale (Catalyst is an aspect
  status clearing with its holder; an arrow is a subtype *or* an element),
  0082's Context (shrapnel crit), 0081 §9's ADR 0079 scoping.
- No owner yet: which inner-tree shape holds the elements and the card
  offer's cadence; Greed's own spec.

**Visual items, per child** (the doc specifies almost none of these looks).
- Child 1: icon and colour per element (`Identity.Kind.ELEMENT`); the
  element count readout and ring slots.
- Child 2: the bar's full shape (one block = degree stacks, 2 inert +
  2(k − 1) primed blocks, shared red / blue bar, the Charge bar with
  sparkles, flickering overflow blocks), on unowned nodes too; the tooltip
  (excess, power, travel verb); the node glow per band; labels for Frozen
  and Shocked and the blaze / inferno display names; trapped Charge readable
  under ice; a cue for heat spreading on the world turn; a cue for a blade
  speeding or dragging.
- Child 4: the blast rendered from the record's blast table; stagger for a
  cascade; a damage number per copy.
- Child 5: the crystal layer under the bars (violet, taking the landing
  element's colour, with a conversion pulse); the Catalyst status icon, goo
  arrow and barrel restyled (`ui/vfx/blast_vfx.*`, `blast_visual.*`,
  `rider_blast_layer.*`, `ui/vfx/projectile/visual/arrows/explosive_arrow.tscn`,
  `skill_node/addons/visuals/explosive_barrel_visual.gd`,
  `assets/icons/aspects/explosive.png`).
- Child 6: the Burning disc VFX sized √power; the burn tick; the Heat addon
  and Burning vertex looks.
- Child 7: the arc VFX per hop; wire conduction and the Charge spent per
  pass-through; the Charge addon and Shocked vertex looks.
- Child 8: the Frozen node look; feedback for an absorbed copy or an ended
  path; shatter, snap and deep-freeze VFX; the Thermal shock crit read; the
  Cold addon and Frozen vertex looks; the concentrate preview ("4 hops → 0,
  seed × N").
- Child 9: element arrow art, quiver bins and stock cap in the HUD; the
  forge's element field (innate element, add or replace, the units, why a
  spell refuses Ice, the hop change on swap).

Knobs so far (tentative pass picks unless marked owner): T = 2 × degree
(owner); k = 2 + stake_level (owner); shatter fraction 1%/stack; shatter
spend fraction 1.0; ice break threshold 10% max HP; blade sweep-speed
clamp(1 + c·t/T, 1−c, 1+c), c = 0.5; Catalyst ratio 1:1, cap k × T, slow
decay; hop ladder L² × T (owner); disc radius √power × node radius (owner);
decay 1 per world turn; world turn every ceil(sqrt(N)) played turn ends;
element ammo stock cap 2 × the per-reload mint; starter count 1 each, dev
sandbox Player 3 each, Catalyst the same (owner); Frozen vertex snap +10%
per excess stack as its own multiplier, no base term; generator +2 per world tick, Charge ceiling
~4T (owner, tentative).

Delete this file once #1716 is split into children and they are `Ready`.
`docs/handoffs/fuel-to-catalyst-arc.md` is cited by ADR 0081 and stays.

---

## Adversarial review findings (2026-11-05)

Hostile read of elements.md + ADR 0072/0073 against the code and the issue
verdicts. C = contradiction, G = gap, N = nit. Items 1, 2, 8, 9, 14 and 18 were
corrected in elements.md the same day; 7a, 7b, 10, 11, 12 and the per-attack
half of 11 were settled 2026-11-05 (see the doc); the rest are in the doc's
§ Open.

1. C: "a blast copy crits iff its parent did" — false today: `PairedDamageEffect` shrapnel has no paired lead, `draws_own_crit()` is `paired == null`, only `BlastToken` (melee) and riding landings copy. *(doc fixed: open)*
2. C: "land: no rider order matters" vs ADR 0067 (riders before their hit) and owner #1741 (*"elemental riders first … then other status(es), then damage(s)"*). *(doc fixed: order kept, reactions forbidden)*
3. C/G: no "landing unit" exists for read/land/settle: riders are separate `HitInstance`s linked by `paired`/`hit_key`, ordered at `HitLanding.place()`; "a planting hit does not trip its medium" is today only `DetonateEffect.arm`'s PlantUse skip. Copies made at settle bypass `place()` and the `land_mask`/`blast_mark` stamping.
4. C: `Infusion.load_of` keys `{concept id: load}`, `use_of` takes a concept's first row, `by_concept` has no single status for a family — Fuel ride + Heat ride + Fire reach rows cannot all key on `fire`. #1660 B2 is the fix; neither ADR carries it.
5. C: `StatusDef._facet_id` keys on identity; `StatDef.Role` is {NONE, ASPECT, STACKS_PER_HIT, RESISTANCE}, naming rule `<concept>_aspect`, `EntityStatBoard` mints nothing else, `AmmoType.per_reload_stat_id` falls back to the ASPECT facet. A `fire` count needs a new role; members key their own facets (#1660 A1 half must survive).
6. C: ADR 0073 never supersedes 0070 (open set of `LoadUse`), 0061 or 0062; `CleanseUse` fits none of ride/reach/shape; Firecracker is both the "shape" example and "becomes a reach row"; `use_for_status` / `default_face=Detonate` sit on a status that no longer exists; 0062's two-reservoir blade formula spends the hit's load.
7. C: pair table vs owner verdicts — (a) blast power *"is the node's fuel"* (#1660 r2), not Fuel plus load; (b) Charge *"consuming 1 at a time"* (#1733 r3), not absorbed; (c) chain-copy share is #1735 fork 1, open; (d) #1660 r1 B *"the hit never needs to know"* is reversed by the reach entry without a later quote; (e) #1444 called the traveller an aspect status, the 11-04 table makes Frostbite an element mover.
8. C: "a medium leaves only by being spent or cleansed" vs decay (ADR 0048, `explosive.tres` FlatDecay), `ExplosiveSpread.on_removed`, owner "death blasts first". *(doc fixed)*
9. C: "element arrow carries innate + floor(count × affinity)" is the per-hit load the doc rejects. *(doc fixed: count mints arrows, load is authored)*
10. C: Ice raising seed payload breaks "the slot buys reach only"; "at cast time" vs "resolve first on landing"; an Ice reach row on an arrow is dead.
11. G: chain cap is per wave in code (`HitLanding.detonated`) and R3, the doc says per attack; dual reach "one copy per reach" is the double count of #1733 r3 Q3 (that pass proposed a union).
12. G: settle after a world-turn tick has no parent hit — copies' payload, crit (no `resolve_seed` stream), receive vs reproduce (ADR 0002); ceil(r·s)·c ≠ ceil(r·s·c).
13. G: "one rider map keyed by status id" is the round-2 agent restatement, not an owner call; #1741 NOTES still list coalescing as open; an id-keyed map merges a BEFORE rider with an AFTER copy.
14. G: "a test guards the 1:1" — none exists. *(doc fixed)*
15. G: orphans of "no Explosive aspect survives", each needing a destination: `effects/status/explosive.tres` (+ `ExplosiveSpread`), `identity/defs/explosive.tres`, `aspects/defs/explosive.tres` + roster entry, `stats_system/defs/explosive_aspect.tres` + `explosive_stacks_per_hit.tres`, the `explosive_aspect` roll in `procgen/pools/dexterity.tres`, `attack/ammo/types/explosive.tres`, `entity/blocker/faces/explosive_face.tres`, `aspect_ring.tscn`, the barrel addon + `first_level/content.tres`, `DetonateUse`/`DetonateEffect`, blade `vertex_charges`/`BladeVertexFill`, `docs/domain/explosive.md`, the matrix's Explosive row / § Explosive / arrow-look row (superseded passages in a settling doc are deleted).
16. C: "Charge" taken twice (Lightning medium vs explosive `charge` tag, `piece_charges`, `vertex_charges`); matrix Glossary :35 still says Payload = damage + *aspect* riders; "Face" means a matrix cell in docs and DETONATE/PLANT in code.
17. N: stock cap is a stat iff something targets it (stat-knobs-and-bins §1); no int:int seam on `AmmoType`/addons.
18. N: Frost is side-less, so it blocks the freezer's own reach too; matrix :553 still said "fire thaws Frozen". *(both fixed)*

Issue bodies the review used are not in the repo; re-fetch over REST.
