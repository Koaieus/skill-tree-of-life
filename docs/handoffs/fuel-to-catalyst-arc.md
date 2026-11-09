# Fuel → Catalyst: the arc of one status (history, 2026-10 → 2026-11-09)

> Handoff/history file, written 2026-11-09 at the owner's request so the
> supersession ADR's Context can cite it. History lives in ADRs; this file
> is the dig that feeds one. Owner sentences are verbatim and dated; all
> else is reconstruction with a citation.

Citation forms: `#N <date>` is an issue comment (or body) of that date, with
its REST comment id where useful; `ADR NNNN` is `docs/adr/`; a bare sha is a
commit on this branch. This clone's history is squashed at 2026-11-05
(`c0ed26e` carries `elements.md` already whole), so the design doc's
2026-11-03/04 text is read from that snapshot and from the issues, not from
earlier commits. Every issue comment is posted from the owner's GitHub
account; only text marked as owner words (italics, "Owner, <date>") counts as
the owner's; the rest is agent text.

## The owner's own summary (2026-11-09)

1. *"first design posed it as "hit node with stacks of this and it will explode". both defensively (against blade nodes) as well as offensively (bigger booms)"*
2. *"then Elements were introduced which were to be the only holders of reach increasing statuses: fire (AoE, explosive, euclidean spread aka 2D discs), lightning (edge hops, 1D) and ice (isolation/insulation, anti-reach, point-based, 0D)"*
3. *"Fuel was made the "primary" status for Fire. while Ice had Cold stacks and Lightning had Charge stacks for their primary status. this tension sat for long and was just bad design waiting to be improved"*
4. *"later, Heat stacks were made to be the primary status for Fire, instead of Fuel, relieving the tension."*
5. *"Fuel would then only be the "inert, and iff host node AoE-explodes through fire, fuel is spent too for bigger explosion + some residual heat". so basically: it's still a FIRE status, because it works with 1) explosions (== fire) 2) leaves Heat"*
6. *"this gives even more tension: why no "ice-fuel" or "lightning-fuel" counterparts exist? ones that do nothing but if triggered would <do smth> && mint elemental stacks (Cold, Charge, …)"*
7. *"so my relevation yesterday was: maybe we should move Fuel OUT of Fire, and turn it into smth like "Catalyst" instead, and let it act on any incoming elemental-terrain status (Heat, Cold, Charge)"*
8. *"like "3 Catalyst" has incoming hit of "2 Heat" and it turns it into "5 Heat" doing a 1:1 Catalyst→{incoming element} trade. (assuming each hit has at most 1 element else it becomes.. messy. but possibly not impossible.). in essence this is almost like what Greed is for Aspect Statuses, but for Elements (i think Greed shouldn't multiply incoming Heat/Cold/Charge stacks, but Catalyst may?)"*
9. *"either this, OR we add an "inert fuel-like buildup" status for Ice and Lightning too so each has one of them. but i think that'd just be a less comprehensible, more tedious and less fluent way to go about this and that getting just 1 catalyzing status for all elements would work better."*
10. *"other mentions, like "barrels": historically (as in, in designs from the past few months) was meant to be some way to set up reach. and i think Elements should do just that (affect reach, characteristic to each concrete element) and Aspects do anything else"*

## Beat by beat

### 1. "Hit a node with stacks and it explodes" — Explosive as an aspect (2026-09-29 → 2026-10-14)

- **What the design said.** Explosive was an aspect row (#1211, opened
  2026-09-29): charges as a status on a node, a hit spends them as a blast.
  Owner and agent grammar v2 settled on #1608 (2026-10-14): three faces on the
  intake row (DETONATE / PLANT / FUEL), `power = load + present + 2·shared`,
  a blast that carries the hit, and a two-sided blade contact.
- **Owner, 2026-10-14 (#1608, comment 6176828602):** *"it scales detonation just like the rest then right? more explosive, bigger boom."* (comment 6177810352, on the two sides:) *"having this one massive explosion be damaging to both defenders **AND blade nodes** just because of the teensy single explosive stack on the defender, feels off"*; *"the defensive power is stronger (damages friendly blade nodes) *and* offensive too (also damages enemy nodes) according to landing"*.
- **Owner, 2026-11-02 (#1733 body, retrospective origin story):** *"first in a volley put N explosive arrows which apply explosive then the next N arrows explode at N, N-1, N-2, … explosive power (~radius) and apply the riders of those next N arrows to whatever enemy node is caught in the explosion."*
- **Primary sources.** `docs/domain/explosive.md` (charges, `DetonateUse` /
  `PlantUse` / `FuelUse`, spend/power, the blade contact);
  `docs/design/aspect_matrix.md` § Explosive (Explosive row, line 271; section,
  line 359); ADR 0061 and ADR 0062 (both 2026-10-14, the faces; 0062 still
  `superseded-by: null`); #1609 comment 6178627285 (default face on `StatusDef`).
  `docs/adr/legacy-mvp-decisions.md` does not mention explosive or charges.
- **Tension carried forward.** The faces made one status do three jobs
  (spend, plant, shape); #1660 and #1696 were filed four days later to dissolve them.

### 2. Elements arrive as the only holders of reach (2026-10-17 → 2026-11-08)

- **Fire first tried as an aspect.** #1660 (2026-10-17/18) renamed the
  Explosive row to Fire with two statuses. Owner, 2026-10-18 (comment 6249579200):
  *"we ignore fire is an element and just consider it an aspect, can always reshape later if we decide elements need a representation (and or bespoke mechanics/acquisition/etc) as a group"*.
- **The element axis, owner 2026-10-20 (#1716 body):** *"fire -- euclidean reach, AoE circles, already literally what it does"*; *"lightning -- canonically forking, hops based travel?"*; *"ice -- .. i got nothing. Exhausted the types of reach already maybe"*. Same day, comment 6288240628, Ice's blade-drag home. 2026-10-24 (comment 6378528046): *"Commit to ice"*. 2026-11-02 (comment 6590256148): *"i think we would run out of unique metrics long before running out of elements to consider. like fire -> euclidean, lightning -> hops, ice -> ...anti hops? or what does this do?"*
- **Elements become a separate axis:** owner 2026-11-04 (comment 6619816552): *"Separate axis sounds good"*, *"elements not being parents of aspects makes sense"*; ADR 0072 (date 2026-11-04) records it.
- **The 0D / 1D / 2D reading** is the 2026-11-06 "travel triad" (commit `312426b`, 2026-11-06); owner, 2026-11-08 (in `elements.md` § Frozen on a blade, `8e9a730`): *"remember Ice is 0D. Point like. Single target."*
- **Tension carried forward.** Each element now owns "reach"; Fire's reach
  came from Fuel (a medium), while Ice and Lightning reached through Cold and Charge.

### 3. Fuel is Fire's medium; Cold and Charge are the other elements' media (2026-11-02 → 2026-11-08)

- **First written.** "Fuel (today's charges) is Fire's medium; detonation is
  its replicate verb … heat is the moving damaging status" is **agent text**,
  #1716 comment 6590256148, 2026-11-02 ("Explosive under Fire (proposal)"),
  undated by the owner. Round 2 (comment 6590349580, same day, agent text) tabled
  Fire = fuel (medium) + heat (mover), Lightning = Charge, Ice = Frost + Hypothermia.
- **Owner words of the time (2026-11-04).** On the table in `elements.md`
  (`c0ed26e` § One count; ADR 0072 line 35): *"that table looks very good, should be persisted"*. On riders (ADR 0073 line 36): *"if fuel is to be a fire status.. and option 2 says `fire:heat` at exactly one then how could a fuel-planting arrow exist? it couldn't."*
- **The ruling.** ADR 0072 (2026-11-04) decision 3: *"Fire is wholly an element. Fuel is Fire's medium; no Explosive aspect survives."* (a pass sentence, not an owner quote). Its rejected alternative "An Explosive aspect kept beside Fire" is the one the Catalyst move revisits.
- **The "primary" tension.** In that table Fuel was Fire's *medium* (terrain,
  reach), Heat its *mover* (sided, hurts), Burning derived (`c0ed26e` line 42);
  Ice's medium was Cold, Lightning's Charge. The owner's word "primary" is the
  owner's, 2026-11-09 only; the table's word was "medium".
- **Tension carried forward.** Fire's terrain was Fuel, a thing a goo arrow
  plants, while Cold and Charge were what the hit's element *became*.

### 4. Heat becomes Fire's terrain stack (2026-11-08)

- **Owner, 2026-11-08 (ADR 0075 Decision; commit `8e9a730`, `a4b8e27`):** *"make them all inert before some threshold T is passed. when "elemental terrain-reach stacks" (== cold/heat/charge stacks) exceed T, then they become primed -- the derived status … this derived status IS the reach face of the element. without it, no reach effects"*.
- **Result.** ADR 0075 decision 3: *"One side-less terrain stack per element — Heat, Cold, Charge"*, primed past T as Burning, Frozen, Shocked; decision 1: reach is terrain-only. Heat is now terrain *"as Cold is"*: it rests on unallocated ground and cools toward zero (owner, 2026-11-08: *"if we make each node lose e.g. at least 1 heat/cold (towards net 0) per tick, it should eventually cool off"*).
- **Lineage of Heat.** Heat's rules (Metropolis flow, ½ damage per stack, ignition by state check) are #1660 round 2 / #1695 / #1696 (2026-10-18). Owner, 2026-10-18 (#1660 comment 6249579200): *"yes it dissolves cleanly. we could move "fuel" over to be the charges, and heat to be detonate; the hit never needs to know about anything here"*.
- **Tension carried forward.** Fuel stayed in the Fire row with no job of its own.

### 5. Fuel the accelerant (2026-11-08)

- **Owner, 2026-11-08 (`8e9a730`, ADR 0075 decision 6, `elements.md` § threshold model):** *"Fuel would only be a supportive sticky "pre fire but would burn as such" goo … if any fire-related combustion occurs, consume all fuel stacks too add them to the explosive power, and leave residual heat."* And: *"fuel indeed doesnt count towards burning"*; *"burning holding fuel explodes"*.
- **Pass pick the owner chose (2026-11-08, `91ace9c`):** N = 2 Heat per Fuel on its own node, over +1 Heat on every node the disc touched. ADR 0075 line 40 lists "N = 2 Heat per Fuel" as a tunable.
- **Tension carried forward.** Fuel is inert alone and acts only beside an
  element, yet is filed under Fire — "a FIRE status because it works with
  explosions and leaves Heat" (spine 5). Also: `elements.md` `c06f255` § Three things wear the word "explosive" (pass clarification, 2026-11-04) has a goo arrow plant Fuel, "inert until the node is Burning".

### 6. Why no ice-fuel or lightning-fuel? (2026-11-08/09)

- **Agent text, undated by the owner on the question itself:** the pass in
  `c06f255` § Open ("Fuel's place on the element axis") lists three shapes —
  Fuel as Fire's second form, as the family's *subtype* member (the keg),
  or as world terrain only (barrels).
- **Owner, 2026-11-09 (`c06f255`, in that item):** *"the "keg" is very much linked to AoE hence in that sense very "fiery" though. unless we also add a shock and lightning counterpart? or change fuel to be an aspect instead -- an element-generic catalyst for any incoming terrain stack, cold/heat/charge."* This is the first committed appearance of the word catalyst, in the owner's mouth; the pass then wrote it up. The 2026-11-09 summary above dates the revelation "yesterday" (2026-11-08) by the owner's own clock; the commit is stamped 2026-11-09 01:58 +0100.
- **Tension carried forward.** The retired Explosive aspect "blew up by itself"
  (`c06f255`); a per-element counterpart multiplies supplies, a generic one does not.

### 7. Move Fuel out of Fire: Catalyst (2026-11-09)

- **Owner words:** spine items 7–8 only (2026-11-09), plus the `c06f255` sentence in beat 6. No other owner sentence of its own time.
- **Agent analysis, `c06f255` § Open, 2026-11-09:** "the generic catalyst has the game sense; per-element counterparts are grid-filling"; separate *power* from *shape* (the catalyst adds power to whatever go-off spends it, only Fire's go-off turns power into area); Frozen + catalyst ≈ 60 stacks at 1 %/stack = a 60 % max-HP true hit, so a per-element worth knob (default 1 for Burning, lower for Frozen); designer note that a pure amplifier does nothing alone. Four drafted forks: supply, fuse, residual, name and kind.
- **What it overturns.** ADR 0072 decision 3 and its rejected alternative (in part), and ADR 0075 §6 (Fuel the accelerant; "2 Heat per Fuel" becomes a per-element residual).

### 8. The 1:1 trade, and Greed (2026-11-09)

- **Owner words:** spine item 8 only. No dated owner sentence earlier than the summary; no agent text proposed the trade before it (the `c06f255` pass analysis is "adds power", not "converts 1:1").
- **Greed as the analogue.** The shipped Greed row (`docs/design/aspect_matrix.md`, Greed row): *"One Greed stack on the node doubles every negative status the next hit lands, Greed included, then one stack is spent"* (#1459, rounds 5–6). #1733 R2 (2026-11-02, agent) already read a terrain term as "conserved: each unit pays out once"; shipped Greed is named there as the case that fails that test.
- **Edges the owner flagged:** one element per hit (see `c06f255`: *"the spell should carry at most one Element"*, owner 2026-11-09); whether Greed or Catalyst multiplies incoming element stacks.

### 9. One catalyzing status, not three buildups (2026-11-09)

- **Owner words:** spine item 9 only.
- **Agent text (`c06f255`):** per-element counterparts are "three rules, three supplies, the Ice and Lightning ones anchored to neither a concept nor a wanted feel".
- **Alternative on record:** "Fuel as Fire's second form" and "the keg subtype" in `c06f255` § Open; the owner's own alternative is the second half of item 9.

### 10. Barrels and reach: elements set reach, aspects do the rest

- **Owner, 2026-10-14 (#1608 body, "Owner decisions (verbatim, 2026-10-14)", item 2):** *"the barrel addon was only there to form a bridge between addon (no state?) and ESS which then could be homogenized as battlefield use for melee copies and defensive and then also hazard situations"*.
- **Owner, 2026-11-05 (#1765 body):** *"i think what we'd want to somehow allow is that Melee's ease of use of applying a temp Clamp addon (their bread & butter) is matched by Ranged getting some <fuel arrows> one way or another, in a similarly easily obtainable fashion."* Also (`c0ed26e`): *"god i hope i find an explosive addon anywhere in the nearest 20 hops from where i spawned"*; *"storing 1000 heat arrows sounds like bad juju"*.
- **Owner, 2026-11-09 (`c06f255` § The forge):** *"what if the element of each arrow is orthogonal to its subtype? (where subtype often just adds riders for e.g. aspects status stacks?) explore this concept"*, which the pass says dissolves #1765's one-budget question.
- **Carried into the Catalyst model.** `elements.md` § Open ("Ranged's access…") and the explosive barrel addon (`skill_node/addons/defs/explosive_barrel_addon.tscn`) still read as Fuel; if Fuel becomes Catalyst the parity question moves onto the catalyst (`c06f255`).

## What each beat left in the tree today

The last column is the pass's suggestion, not an owner call.

| artifact | path | made by beat | what the Catalyst model does to it (suggestion) |
|---|---|---|---|
| Explosive aspect count stat | `stats_system/defs/explosive_aspect.tres` | 1 | retag as the Catalyst supply, or retire if Catalyst gets its own count (open: supply) |
| per-hit stack stat | `stats_system/defs/explosive_stacks_per_hit.tres` | 1 | retag `catalyst_stacks_per_hit` |
| the status and its spread | `effects/status/explosive.tres` (+ `effects/status/spread/explosive_spread.gd`) | 1, 5 | retag (tag `charge` → catalyst; collides with Lightning's Charge per #1716 round 2); the spread's blast shape moves to the elements' go-offs |
| identity | `identity/defs/explosive.tres` | 1 | retag |
| aspect def | `aspects/defs/explosive.tres` | 1, 3 | retag or retire with the supply call |
| goo ammo | `attack/ammo/types/explosive.tres` | 1 | keep as a Catalyst ride arrow |
| blocker face | `entity/blocker/faces/explosive_face.tres` | 1 | keep, retag |
| aspect ring | `entity/ring/aspect_ring.tscn` | 1 | retag with the aspect |
| barrel addon | `skill_node/addons/defs/explosive_barrel_addon.tscn` | 1, 10 | keep; becomes map-laid Catalyst terrain |
| DEX pool | `procgen/pools/dexterity.tres` | 1 | retag the roll |
| first-level content | `procgen/modules/first_level/content.tres` | 1 | retag |
| Firecracker | `attack/spell/defs/firecracker.tres` (FuelUse row) | 1 | keep the row as a Catalyst-load shaper, retag the use |
| detonate use | `attack/spell/load_use/detonate_use.gd` | 1 | retire with the faces (#1696) or retag |
| detonate effect | `attack/spell/on_hit/detonate_effect.gd` | 1 | retire: the go-off is the element's (ADR 0075) |
| blade charges | `attack/melee/sim/blade_state.gd` (`vertex_charges`) + `attack/melee/blade_vertex_fill.gd` | 1 | retag with the status; blade-lives semantics open |
| domain doc | `docs/domain/explosive.md` | 1 | rewrite once built |

## Open after 2026-11-09

- **Supply.** Whether Catalyst is the Explosive aspect retagged (an aspect, one status, `catalyst_aspect`), or its own count on the board (a fourth attunement), or found only (barrels and loot) (`c06f255` § Open, resolution 1).
- **What colours Catalyst.** Hits only (pass call) versus flow too: a Hearth beside a catalyst field would prime it passively.
- **The trade's edges.** Ratio 1:1 as a knob, one element per hit, whole-store conversion versus per-hit, the per-element worth (Frozen lower), whether Greed or Catalyst multiplies incoming element stacks, and the fuse (a primed Catalyst node going off on the world turn).
