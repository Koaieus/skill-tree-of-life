# Node subtypes — an orthogonal axis to archetype (design session 2026-09-22)

> Design doc: the *model*. Nothing here is built. Opened from **#1025**, which
> asked for a seventh "Blight" archetype; the owner reframed it into this.
> The DoT family model it leans on is [damage_over_time.md](damage_over_time.md).

## The reframe

#1025 proposed **Blight** as a seventh archetype hosting the DoT-family stats.
Owner, 2026-09-22, redirecting:

> *"having it as orthogonal axis (like archetype + subtype, subtype default
> none, but thinking 'blighted', 'blessed' which then modifies the pool
> available for procgen; i think that's the best way forward."*

So a node carries **two** identities:

- **archetype** — one of the six, unchanged. STR / DEX / INT / WIS / PER / CON.
- **subtype** — `none` (default), `blighted`, `blessed`. Modifies which pools procgen draws from for that node.

`6 × 3 = 18` territory identities out of eight authored things. That
combinatorial payoff is the argument for the axis.

## The rule that makes the grid legible

**The archetype picks the *family*. The subtype picks the *pole*.**

Every archetype already hosts one status family's potency (#974). So
"blighted DEX" needs no new mapping — it *is* poison territory, because DEX
is where `poison_potency` lives. The subtype then says which end of that
family you get: blighted = the offensive stats, blessed = the defensive ones.

> *"you need more vision? find and hold PER nodes. need more XP? find and
> hold WIS nodes. need more poison damage? find BLIGHT nodes. that's it"*
> — owner, 2026-09-22

## The grid

Owner re-homed two families in this session (see Decisions): **wither → INT**,
**curse → CON**.

| archetype | family | blighted (offense) | blessed (defense) | regular keeps |
|---|---|---|---|---|
| **DEX** | poison | poison potency, stack application | poison resistance | crit chance/multiplier, arrows per reload |
| **STR** | corruption | corruption potency | corruption resistance | strength ladder, armor (pending #1052) |
| **INT** | wither | wither potency | wither resistance | mana, cast range, node_health |
| **CON** | curse | curse potency | curse resistance | node_health, the defensive ladder |
| **PER** | blindness | blindness application | blindness resistance / vision | vision range, sensor range, **scout arrows per reload** |
| **WIS** | — (pure economy) | *open — see below* | budget bump (proposal) | wisdom ladder, xp_per_turn |

Why the re-homing is better than what ships today:

- **Curse on CON.** Curse raises `min_damage_taken` — its whole job is stripping the defender's mitigation. Putting it on the defensive attribute makes blighted CON the dark mirror of blessed CON, one archetype carrying both poles of "does armor work". Today CON hosts wither *and* all four resistances, which is one archetype doing two jobs.
- **Wither on INT.** Wither drives `healing_received` below zero — the "undead sandbox" ([damage_over_time.md](damage_over_time.md)). That reads arcane/necromantic, and INT is the magic attribute. Owner: *"INT is WAY MORE prevalent than WIS; WIS is pure economy."*
- **Blindness on PER.** Already a shipped status with its own flat decay and cap, and PER is already the dedicated home for `scout_arrows_per_reload` (owner, 2026-09-22). Vision offense and vision defense on the vision attribute.
- **Resistances stop being universal.** All four currently sit in `constitution.tres` as universal pools — a flat roll every node can produce regardless of where you go. [damage_over_time.md](damage_over_time.md) calls them *"battlefield-found, universal defence rolls"*; under this grid they become genuinely battlefield-found: you hold blessed territory of the right archetype. This is a **content-side answer to #975's dilution complaint**, independent of that issue's weighting fix.

## Subtype replaces, never adds

Settled. A subtype **swaps out** part of the archetype's pool rather than
layering on top. Owner's own sketch:

> *"regular DEX archetype: rolls DEX, crit %, poison arrows (maybe), crit
> factor (maybe little bit) … blighted DEX archetype: rolls DEX, poison DoT
> stats (duration, potency, …), poison arrows (maybe?) … blessed DEX
> archetype: rolls DEX, poison resistance, crit factor (more often than on
> regular)"*

Note what the sketch does: blighted DEX loses crit%. Every subtype is a
**sidegrade**, so the map holds three genuinely different DEX territories
rather than one good one and two worse ones, and no subtype is a must-route
detour. If subtypes added, blighted would be strictly better and `none` would
become filler.

## The DoT stat vocabulary this needs

Owner's estimate: 8–16 new stats. Today there are exactly eight
(`{poison,corruption,curse,wither}_{potency,resistance}`) and **no umbrella
stat** — that vocabulary is the whole of it.

Proposed split between per-family and shared:

- **Per-family** (what makes the four distinct): potency, resistance, stack application (*"+1 poison stack per poison stack applied"*). 4 × 3 = 12.
- **Shared across the family** (what makes a *territory* read): falloff, duration. 2 total.

Shared knobs are the ones that make blighted territory feel like a place —
"this ground makes *all* rot linger" is a cleaner idea than four separate
falloff stats, and it is the stat that would express a plague-land.

### The umbrella-stat trap

If an umbrella "Blight" stat is ever added (owner floated it as a separate
thread), it must **not** scale damage across all four families.
[damage_over_time.md](damage_over_time.md) exists because the four members
deliberately answer four *different* defensive axes — poison beats armor and
sub-zero floors, corruption beats bulk, curse beats the bunker, wither beats
the fortress. One stat scaling all four would beat every defensive axis at
once, which is precisely the failure the family was designed to prevent. An
umbrella scoped to **stack application** or **falloff** has no such problem:
it makes you land more of whatever you already do.

## Relationship to node specializations — NOT the same axis

[skill_node_specializations.md](skill_node_specializations.md) has a
**Corrupted Node** candidate. It is a different thing and the two must not
drift together:

| | subtype (this doc) | specialization (that doc) |
|---|---|---|
| what it is | a territory flavour: which pools procgen rolls from | a per-node fused benefit + permanent downside |
| how common | common — a normal property of generated regions | *"should feel rare and meaningful"* |
| carried by | the node's generated identity, alongside archetype | intrinsic (type-A) or applied by a costly process (type-B) |
| affects | the draw, before any roll happens | the node's actual modifiers, after |

They could be unified later — that doc's open question 1 already asks whether
the addon/specialization boundary holds. Unifying is not proposed here.

## Visual language

Owner: *"e.g. 'black-ish rimmed skillnodes'"*. A subtype reads as a **rim
treatment** on the existing node — blighted dark, blessed bright — so the
archetype's colour and carve shape survive untouched and the map stays
readable at a glance. No new emblem vocabulary; one more visual channel on a
node that already has several.

## Decisions (owner, 2026-09-22)

1. **Blight is not a seventh archetype.** It is the first value of a new orthogonal **subtype** axis: `none` (default) / `blighted` / `blessed`.
2. **Subtype modifies the pool procgen draws from**, and **replaces** rather than adds — every subtype is a sidegrade.
3. **Archetype picks the family, subtype picks the pole.** Follows from #974's existing potency homing; nothing new to map.
4. **Wither moves to INT, curse moves to CON.** *"makes sense thematically / gameplay-wise"* — and it stops CON hosting a family plus every resistance.
5. **PER's family is blindness**, an already-shipped status. PER also remains the dedicated home for `scout_arrows_per_reload`.
6. **WIS gets no blighted variant for now.** *"WIS is pure economy… maybe `blessed` version just boosts it's budget slightly (already quite powerful). open for design / good ideas."*

## Open questions

1. **What is blighted WIS?** The one ragged cell. WIS is pure economy, so it has no status family to invert. Candidates: (a) it simply does not exist — the grid is ragged and that is honest; (b) WIS hosts the **shared** cross-family knobs (falloff, duration) on its blighted form — "the blighted archive, knowledge of every plague" — which keeps WIS meta-flavoured and needs no sixth family; (c) the economy itself is corrupted — the node still pays XP but taints the holder.
2. **Is blessed WIS a budget bump, and does that break the rule?** Every other blessed cell swaps pools; a budget multiplier is a different *kind* of effect. Either the rule admits a second mechanism or blessed WIS needs a pool-shaped answer.
3. **How is subtype generated?** Per-node roll, or a region/stamp that paints a contiguous patch? Territory flavour argues strongly for regions — a lone blighted node reads as noise, a blighted valley reads as a place. `ArchetypeStamp` is prior art for painting regions post-clustering.
4. **Can a subtype's territory be converted?** Does holding blessed nodes cleanse adjacent blighted ones, or is subtype fixed at generation? A conversion mechanic would make the map a battleground in a second dimension; fixed is far cheaper.
5. **Do the four families each need a fifth/sixth sibling** now that PER takes blindness and WIS takes none? Owner noted *"Blight is a good name also for if we ever need a 5th."*
6. **Does subtype interact with `forbid_tags`?** The existing ArchetypePolicy rows already use `forbid_tags` to keep archetypes off each other's content — subtype's pool-swap may be expressible in that same vocabulary rather than a new one.
7. **Exact stat count.** 14 is the proposal above (12 per-family + 2 shared). Owner's range was 8–16, *"maybe up to 16 if we flesh them out with more bespoke tweakables."*
