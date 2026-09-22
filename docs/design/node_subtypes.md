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

## The name "Corrupted" is already spoken for — loosely

[skill_node_specializations.md](skill_node_specializations.md) sketches a
**Corrupted Node**. Owner, 2026-09-22: that doc is *"one of the earliest
design docs where spitballing was more prominent than ever — at best see it
as inspiration for mechanics we don't yet have."* So it is not a competing
axis and nothing here needs to reconcile with it.

Worth one line only because the vocabulary could collide: its "Corrupted" is a
rare **per-node** fused benefit-plus-permanent-downside, while a subtype is a
common **territory** flavour that changes which pools procgen draws from,
before any roll happens. If subtypes ship, prefer `blighted` over `corrupted`
in code and UI and the ambiguity never arises.

## Visual language

Owner: *"e.g. 'black-ish rimmed skillnodes'"*. A subtype reads as a **rim
treatment** on the existing node — blighted dark, blessed bright — so the
archetype's colour and carve shape survive untouched and the map stays
readable at a glance. No new emblem vocabulary; one more visual channel on a
node that already has several.

## How subtype content is authored

**Not** by duplicating packs. `6 × 3 = 18` StatPacks would mean authoring the
DEX ladder three times and keeping the copies in sync forever.

**And not by tags alone.** Tags are a flat *flavour* vocabulary (`str`,
`flat`, `crit`, `tier_2`). Encoding subtype membership in them makes tags carry
two unrelated axes, and it forces the default subtype to be expressed as an
open-ended exclusion — *"forbid `blight`, `bless`, and every subtype anyone
adds later."* Add a fourth subtype, forget to extend that list, and its content
silently rolls on every node in the game. An exclusion list that must enumerate
its own future is a footgun, not a design.

So the two jobs get two mechanisms, because they are two different questions:

### ① Membership — a `NodeSubtype` resource, mirroring `Archetype`

Not an enum, and not a bare `StringName`. Subtype crosses three layers —
procgen selects on it, the `SkillNode` carries it, the visuals read it — and
the thing that crosses those layers has to carry *data*: a tint, an emissive
tier, a display name. A `StringName` cannot; an enum forces a `match` block
in every one of those layers, and a new subtype then means editing all three.

`Archetype` is already exactly this shape and is already a `Resource`
(`archetypes/archetype.gd` — `id`, `primary_stat`, `carve_shape`, colour
derived from the stat's `StatDef.tint_color`). Subtype is its peer, so:

```gdscript
class_name NodeSubtype
extends Resource

@export var id: StringName = &""          # &"blight", &"bless"
@export var display_name: String = ""
@export var tint: Color = Color.WHITE     # composed into NodeVisualsComposite.modulate
@export var emissive_tier: StringName     # blessed blooms; blighted stays sub-1.0
@export var forbid_tags: Array[StringName] = []   # ② below, authored with the identity
```

Why this beats an enum, concretely:

- **Typos are impossible.** You pick a resource in the inspector; there is no string to misspell and no silent no-match. An enum also prevents typos, but only in code — an enum stored in a `.tres` still serialises as an int, and remapping ints is the churn #319 complained about.
- **One definition, no `match` blocks.** Visuals read `subtype.tint` and `subtype.emissive_tier`. Procgen compares `subtype`. Nothing switches on identity anywhere.
- **A new subtype is one `.tres` and zero code.** With an enum it is a new enum value plus every `match` that must handle it — and the compiler will not tell you which ones you missed.
- **The visual constants live with the identity**, not scattered across a shader-parameter block far from the thing they describe.

The cost, stated: a `Resource` is heavier than an enum, and if subtype never
grows past "which pools, which tint" an enum would have sufficed. It is the
right call anyway because `Archetype` set the precedent for exactly this fact
and two axes of the same kind should not be two kinds of thing.

**The pool gate** is then a reference, null meaning "any":

```gdscript
# StatPool
@export var subtype: NodeSubtype = null   # null = any subtype; set = that subtype only
```

```
pool is selected for a node iff
    (pool.archetype_stat == &"" or == node.primary_stat)
and (pool.subtype       == null or == node.subtype)
```

**The default needs no list.** A regular node simply fails to match a pool
whose `subtype` is set. A fifth subtype added in a year is excluded from every
existing node automatically, because exclusion is *structural*, not
enumerated. That is the whole reason this is a gate and not a tag.

**The `SkillNode` carries it too** — `@export var subtype: NodeSubtype = null`,
read by `NodeVisualsComposite` to compose `subtype.tint` into its existing
modulate chain. Unlike the procgen-authoring fields #336 stripped off
`skill_node.gd`, this one earns its place: it drives runtime appearance, not
just generation.

### ② What a subtype gives up — `forbid_tags`, doing what tags are for

Membership alone is additive: a blighted node would get every regular pool
*plus* the blight pools, which is the strictly-better problem again. So
`NodeSubtype` also carries a `forbid_tags` list — and now that is an honest
use of tags, a *designer flavour choice* rather than an identity mechanism.
Blighted DEX forbids `crit`; that one line **is** "trades crit% for DoT
stats", stated in the vocabulary `ArchetypePolicy` already speaks and
`GraphProcgen._has_forbidden_tag` already enforces.

Two knobs, each answering its own question: **`subtype` decides what *can*
appear, `forbid_tags` decides what the subtype *gives up*.** Neither leaks
into the other, and both are authored on the one resource that defines the
subtype.

### Authoring ergonomics — and why subtype stays on the pool

The target shape, in the owner's words: *"i could enter all `STR` related
rolls onto a single stat pool … and ideally i could add more elements and just
mark them 'blessed' instead of regular."*

That is what a per-pool gate gives: **one `strength.tres`, pools inside it
marked individually.** No duplicated packs, no parallel files to keep in sync,
and a blessed STR pool sits right next to the regular STR pool it trades
against — which is where you want to read it.

**This reverses an earlier note in this doc.** #751 wants `StatPack` to be the
only archetype gate, deleting `StatPool.archetype_stat` so a pack stops
retyping `&"strength"` on every pool. It is tempting to say subtype should
move up with it. It should not, and the reason is the same reason archetype
*should*: a pack is one archetype by definition, so repeating it is noise —
but a pack deliberately contains **mixed** subtypes, so subtype is real
per-pool information. They are not the same kind of fact. After #751:
archetype at the pack, subtype at the pool, each where it carries information.

## How subtype is generated — a per-node base chance (v1)

**Settled, owner 2026-09-22:** *"easiest would be authoring a base chance for
any node to be blessed, or blighted, or regular."*

Each `NodeSubtype` carries its own share; regular is the remainder:

```gdscript
# NodeSubtype
@export_range(0.0, 1.0) var base_chance: float = 0.0

# GraphProcgenContent
@export var subtypes: Array[NodeSubtype] = []
```

One weighted pick per node during the content loop. No second pass, no
seeding, no policy array. The frequency lives on the identity that defines the
subtype, so authoring a new one is still a single `.tres`.

### Why this is the right v1 and not a shortcut

The earlier draft of this section argued for regions — *"a lone blighted node
reads as noise, a blighted valley reads as a place"* — and proposed
generalizing the BFS-grow clustering pass to run twice. That argument is
weaker than it looked, for two reasons:

1. **The design's own pitch works per-node.** *"Need more poison damage? find and hold BLIGHT nodes."* A single node is findable and holdable. Scattered subtyped nodes are *individual opportunities* along a route rather than *territories to claim* — a different feel, not a worse one, and arguably a better fit for a graph you traverse.
2. **It does not foreclose regions.** Clustering changes *where* subtypes land, not what they are or what they roll. `NodeSubtype`, the pool gate, the tint and the forbid list are all unchanged by an upgrade to clustered placement — and the authored `base_chance` becomes the cluster pass's `target_ratio` more or less verbatim. The upgrade path costs nothing that is authored now.

So: ship the roll, look at a real level, and promote to clustering only if the
speckle actually reads badly in play. That is a question for eyes on a
generated map, not for a design doc.

### If it is promoted later

Do **not** add `ArchetypeStamp`-style placed regions for this — that mechanism
shipped with #163 and no preset has ever authored it (`archetype_stamps` is
*"authored empty in both presets today"*, `test/unit/procgen/test_preset_generation_golden.gd:22`;
see **#1055**). The upgrade is a second run of the existing BFS-grow pass over
subtype policies, not a third region mechanism beside two that already exist.

## How subtype is drawn — and the constraint that decides it

**The hard constraint is instance-uniform slots, not fragment cost.**
SkillNodes are not MultiMesh: each binds ~18 slots (`inner_disk` 11 +
`rim_ring` 7) against a **global 4096-slot cap**. At the 500–2500 nodes a
level carries that is 9k–45k slots, already over — it only works because
fogged nodes skip binding. `RimBonuses` and `RuneRing` were **shelved for
precisely this** (see `docs/domain/rendering-performance.md`).

So **a new per-node instance uniform is the expensive option**, not the cheap
one, and `INSTANCE_CUSTOM` is not an escape hatch — it is a MultiMesh channel
and nodes are not MultiMesh.

Cheapest first:

1. **`modulate` (recommended first cut).** `NodeVisualsComposite.modulate` is already `feedback_tint × status_tint`; a `subtype_tint` composes into that same chain. **Zero new slots, zero new draw calls**, and it follows the established pattern for "same node, different flavour". Blighted = a desaturated, darkened tint.
2. **Blessed blooms; blighted must not.** Per `.claude/rules/hdr-color.md`, a thing glows iff its colour exceeds 1.0, authored as a named tier via `Emissive.at()`. Blessed gets a tier and picks up the existing `WorldEnvironment` bloom pass for free. Blighted is *dark* — it must stay under 1.0, which is the correct visual answer anyway.
3. **A rim-shader branch** — one more instance uniform. Affordable only if something else is freed, and it buys a *shape* difference (cracked band, inverted dial) that modulate cannot express.
4. **An overlay child**, like `blocker_visual.gd`. One extra draw call per subtyped node, no slots. Right if the look is additive geometry rather than a re-tint.

### On the rotating stripe

Tempting, and fragment cost is genuinely free — but `rim_ring.gdshader` has
**no `TIME` and a deliberate "NO SPIN" note**: the shelved version animated
only to hide a parked asymmetric arc, and the spin was removed on purpose.
Animating it again also needs a **per-node phase** or every node in the level
pulses in lockstep — and that phase is another slot. Treat the stripe as a
later upgrade with its own justification, not part of the first cut.

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
3. ~~How is subtype generated?~~ **Settled**: a per-node `base_chance` on each `NodeSubtype`, regular as the remainder. Promote to clustered regions only if the speckle reads badly in play.
4. **Can a subtype's territory be converted?** Does holding blessed nodes cleanse adjacent blighted ones, or is subtype fixed at generation? A conversion mechanic would make the map a battleground in a second dimension; fixed is far cheaper.
5. **Do the four families each need a fifth/sixth sibling** now that PER takes blindness and WIS takes none? Owner noted *"Blight is a good name also for if we ever need a 5th."*
6. **What do the `forbid_tags` lists actually key on?** The membership gate needs no new tags, but each subtype's give-up list does (`crit`, …). Worth a pass over the existing `procgen/tags.tres` vocabulary before adding any — the right forbid list may already be expressible.
7. **Exact stat count.** 14 is the proposal above (12 per-family + 2 shared). Owner's range was 8–16, *"maybe up to 16 if we flesh them out with more bespoke tweakables."*
