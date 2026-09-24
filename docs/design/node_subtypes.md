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

- **Curse on CON.** Curse raises `min_damage_taken` — its whole job is stripping the defender's mitigation. Putting it on the defensive attribute makes blighted CON the dark mirror of blessed CON, one archetype carrying both poles of "does armor work". Before this grid CON hosted wither *and* all four resistances, which was one archetype doing two jobs.
- **Wither on INT.** Wither drives `healing_received` below zero — the "undead sandbox" ([damage_over_time.md](damage_over_time.md)). That reads arcane/necromantic, and INT is the magic attribute. Owner: *"INT is WAY MORE prevalent than WIS; WIS is pure economy."*
- **Blindness on PER.** Already a shipped status with its own flat decay and cap, and PER is already the dedicated home for `scout_arrows_per_reload` (owner, 2026-09-22). Vision offense and vision defense on the vision attribute.
- **Resistances stop being universal.** All four sat in `constitution.tres` as universal pools — a flat roll every node could produce regardless of where you go. [damage_over_time.md](damage_over_time.md) calls them *"battlefield-found, universal defence rolls"*; under this grid they become genuinely battlefield-found: you hold blessed territory of the right archetype. This is a **content-side answer to #975's dilution complaint**, independent of that issue's weighting fix.

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

@export var id: StringName = &""          # &"regular", &"blight", &"bless"
@export var display_name: String = ""
@export var tint: Color = Color.WHITE     # composed into NodeVisualsComposite.modulate
@export var emissive_tier: Emissive.Tier = Emissive.Tier.INERT   # blessed blooms; blighted stays sub-1.0

## The canonical default. A lazy static accessor, NOT `const REGULAR :=
## preload(...)` — regular.tres's own script IS this class, so a class-scope
## preload is a cyclic load. Same idiom StatPool already uses for
## `TagRegistry.canonical()` (stat_pool.gd:335).
static func regular() -> NodeSubtype:
    ...   # res://procgen/subtypes/regular.tres
```

`Emissive` exposes tiers as **floats** on an `enum Tier` (`ui/theme/emissive.gd:26-37`
— INERT 0.0, LABEL 0.5, VALUE 1.0, ALERT 2.0, PEAK 3.0) and `Emissive.at()` takes
`stops: float`. Author the enum, never a `StringName`; there is no string→float map
to invent.

Why this beats an enum, concretely:

- **Typos are impossible.** You pick a resource in the inspector; there is no string to misspell and no silent no-match. An enum also prevents typos, but only in code — an enum stored in a `.tres` still serialises as an int, and remapping ints is the churn #319 complained about.
- **One definition, no `match` blocks.** Visuals read `subtype.tint` and `subtype.emissive_tier`. Procgen compares `subtype`. Nothing switches on identity anywhere.
- **A new subtype is one `.tres` and zero code.** With an enum it is a new enum value plus every `match` that must handle it — and the compiler will not tell you which ones you missed.
- **The visual constants live with the identity**, not scattered across a shader-parameter block far from the thing they describe.

The cost, stated: a `Resource` is heavier than an enum, and if subtype never
grows past "which pools, which tint" an enum would have sufficed. It is the
right call anyway because `Archetype` set the precedent for exactly this fact
and two axes of the same kind should not be two kinds of thing.

**The pool gate is a SET**, empty meaning "any" (owner, 2026-09-22 — decision 12;
this reverses an earlier single-reference draft of this section):

```gdscript
# StatPool
@export var subtypes: Array[NodeSubtype] = []   # [] = any subtype; else exactly these
```

```
pool is selected for a node iff
    (pool.archetype_stat == &""   or == node.primary_stat)
and (pool.subtypes.is_empty()     or node.subtype in pool.subtypes)
```

**The default needs no list.** A regular node fails to match a pool whose
`subtypes` names only blight. A fifth subtype added in a year is excluded from
every existing node automatically, because exclusion is *structural*, not
enumerated. That is the whole reason this is a gate and not a tag.

**And a set, unlike a single reference, can *exclude*.** A pool authored
`[regular, blessed]` is one a blighted node cannot draw — which is how a
subtype expresses what it **gives up**, per-archetype, with no second
mechanism. See ② below for why that killed the `forbid_tags` design.

**The `SkillNode` carries it too** — `@export var subtype: NodeSubtype = null`
(singular: a node has exactly one; `null` means *unset*, as on a hand-authored
sandbox node, and procgen always stamps the resolved default instead) —
read by `NodeVisualsComposite` to compose `subtype.tint` into its existing
modulate chain. Unlike the procgen-authoring fields #336 stripped off
`skill_node.gd`, this one earns its place: it drives runtime appearance, not
just generation.

### ② What a subtype gives up — the same set, not a second mechanism

**Settled, owner 2026-09-22 (decision 12). This section is a reversal**: an
earlier draft gave `NodeSubtype` its own `forbid_tags: Array[StringName]`,
unioned into the `archetype_forbid` that already flows from `ArchetypePolicy`
into `GraphProcgen._roll_modifiers_v4` (`graph_procgen.gd:339`). That is dead.

The objection that killed it: **one list across six archetypes.** Blighted DEX
gives up `crit`. Blighted STR gives up… what? A global forbid works as a union
(forbidding `crit` is a no-op on STR) but cannot express *"blighted DEX keeps
armor, blighted STR loses it."*

The set gate says it without a second mechanism, because **pools are already
per-archetype**. "Blighted DEX trades crit% for DoT stats" is one line of
authoring on one pool:

```
dexterity.tres → crit_chance pool → subtypes = [regular, blessed]
```

The blighted DEX node cannot draw it. STR's armor pool, untouched, keeps
`subtypes = []` and every STR node draws it regardless. One owner, one fact:
**every pool states which subtypes may draw it.** Membership and give-up were
never two questions — they are the same question ("may this node draw this
pool?") answered per pool.

What dies with `forbid_tags`: the second knob on `NodeSubtype`, and the doc's
former claim that the two "each answer their own question". What survives
untouched: `ArchetypePolicy.forbid_tags` and `_has_forbidden_tag`, which are
the *archetype's* give-up and are not in this axis's business.

**The entry-id trap this creates.** `StatPool.to_entries` mints
`<stat>_<op>_<arch>_t<tier>` (`stat_pool.gd:209-213`) and weight profiles
target by that id. Two pools for the same (stat, op, archetype) — a regular
`crit_chance` pool and a blessed one weighted higher — would **collide**. So a
subtype segment is appended **only when `subtypes` is non-empty**: every
already-authored id stays byte-identical and the goldens do not churn.

### The three authoring rows — and the one rule that keeps them safe

`[]` is not a degenerate case, it is **the common one**. A pool shared by every
subtype simply leaves `subtypes` empty, which is the default — the DEX
attribute ladder is never copied, never listed, never touched. That is the
"rolls DEX" that appears in all three rows of the owner's own sketch.

| what you want | how it is authored | copies |
|---|---|---|
| same for every subtype (the attribute ladder) | `subtypes = []` | none |
| present for some, absent for others, identical where present (blighted DEX loses crit) | `subtypes = [regular, bless]` | none |
| present for several **at different values or weights** | separate pools, each gated | yes — unavoidable |

Row 3 is not the gate breaking down. Two different values are genuinely two
pieces of content, and no mechanism expresses them as one pool; the subtype
list is what makes the two copies **addressable** rather than ambiguous, and
the `to_entries` id segment is what keeps them from colliding. The list does
*more* work in row 3, not less.

**THE RULE: leave the shared ladder at `[]` and gate only the flavour.**

Owner, 2026-09-22 (decision 16) — authoring discipline, deliberately not
enforced in code.

**What the rule protects against.** Copy a pool to `[regular, bless]` and
forget `[blight]`, and blighted DEX nodes silently lose that content — with
**no symptom**. Decision 13's fallback does not catch it: blight still has *a*
drawable pool (its potency), so the node stands; it just quietly never rolls
the DEX ladder. A balance bug with nothing to observe.

A coverage warning was considered and **declined** — for any
`(stat_id, operation, archetype_stat)` group touched by a subtype-gated pool,
flag any subtype no pool in that group names. Owner chose discipline over the
mechanism; revisit if row 3 is ever actually authored, since the hole can only
exist there.

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

`subtypes` holds only the **weighted** subtypes; regular is the remainder, and
what a node that rolls nothing gets is the global default —
`NodeSubtype.regular()` — which a preset may override:

```gdscript
# GraphProcgenContent
@export var default_subtype: NodeSubtype = null   # null = NodeSubtype.regular()
```

One weighted pick per node during the content loop, inside the archetype
branch only (`graph_procgen.gd:~340`; the else branch is the budget-0 path and
gets no subtype). No second pass, no policy array. The frequency lives on the
identity that defines the subtype, so authoring a new one is still a single
`.tres`.

### The fallback that makes a ragged grid safe

**Settled, owner 2026-09-22 (decision 13).** A rolled subtype **stands only if
the node can actually draw content for it**:

```
rolled subtype s stands iff  ∃ pool . (pool.archetype_stat == &"" or == primary)
                                  and s in pool.subtypes
otherwise the node gets `default_subtype`.
```

Without this, a node rolls blighted, takes the dark rim, and draws only the
regular pools — it *looks* blighted and *plays* regular. At 800 nodes and a
0.10 blight chance that is ~80 blighted nodes, ~13 of them WIS, which
**decision 6 exempts from blighted content on purpose**. The hole is real and
intentional, so the guard is not optional.

What it buys beyond the WIS cell: the grid may be ragged **anywhere, forever**.
Add a seventh archetype, add a fourth subtype, forget a cell — nothing ever
lies. And it is the correct behaviour at `subtypes = []` for free, so the
mechanism child's unchanged-goldens acceptance already exercises it.

The predicate is per-`(archetype, subtype)`, not per-node: compute it **once
per `generate()`** into a lookup, never inside the node loop.

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
3. **Archetype picks the family, subtype picks the pole.** The mapping already exists from #974's potency homing — two entries move (decision 4), the rest stand as authored.
4. **Wither moves to INT, curse moves to CON.** *"makes sense thematically / gameplay-wise"* — and it stops CON hosting a family plus every resistance.
5. **PER's family is blindness**, an already-shipped status. PER also remains the dedicated home for `scout_arrows_per_reload`.
6. **WIS gets no blighted variant for now.** *"WIS is pure economy… maybe `blessed` version just boosts it's budget slightly (already quite powerful). open for design / good ideas."*

7. **`NodeSubtype` is a `Resource`, not an enum and not a `StringName`** — it crosses procgen, `SkillNode` and the visuals, so it must carry data (tint, emissive tier). Mirrors `Archetype`.
8. **The gate stays on `StatPool`, even after #751 moved `archetype_stat` up to `StatPack`.** A pack is one archetype by definition, so repeating it is noise; a pack deliberately holds *mixed* subtypes, so subtype is real per-pool information.
9. **Placement is a per-node `base_chance` in v1**, regular as the remainder. Clustered regions are an upgrade that changes nothing authored.

### Decisions added 2026-09-22 (second session, the decomposition pass)

10. *(superseded by D17, 2026-09-23 — the archive is the application umbrella, not falloff/duration)* **Blighted WIS is "the blighted archive"** — WIS hosts the **shared** cross-family knobs (falloff, duration) rather than a sixth family. It stays meta-flavoured and needs no new family. This is the recorded *destination*: those two stats do not exist yet, so it is **not v1 content**.
11. **Blessed WIS needs a pool-shaped answer**, not a budget multiplier — the replace-not-add rule holds absolutely. Owner: *"'more budget' is comparable to 'blessed offers similar mods but at lower budget cost' (effectively cheaper). but also open for other niceties or rarities that we could add to such wondrous concept as BLESSED WIS nodes. some rare stat one'd barely touch so far"*. Per-pool cost is not authorable today (cost comes from [TierLadder] per tier), so this too is **not v1 content**.
12. **What a subtype gives up is the same per-pool set, not a `forbid_tags` list.** `StatPool.subtypes: Array[NodeSubtype]`, empty = any. One owner for "may this node draw this pool?"; per-archetype precision falls out because pools are already per-archetype. `NodeSubtype.forbid_tags` is **deleted from the design**. Reverses §① (single ref → set) and §② entirely.
13. **A rolled subtype that has no drawable content demotes to the default.** The guard is structural, computed once per `generate()`, so the grid may be ragged anywhere without any node ever looking like something it does not play.
14. **`regular` is a global default with an optional per-preset override.** Owner: *"a global default subtype const (`regular`/none) and procgencontent could then optionally override"*. `NodeSubtype.regular()` is the canonical one; `GraphProcgenContent.default_subtype` overrides when set. It must be a **lazy static accessor**, not a class-scope `preload` — `regular.tres`'s script is `NodeSubtype` itself, so the preload is cyclic.
16. **Partial coverage is authoring discipline, not a validated invariant.** Leave a pool shared by every subtype at `subtypes = []`; gate only the flavour. A coverage warning was considered and declined — the hole only exists if a pool is copied per-subtype at different values, which the rule keeps rare.
15. **Inspector DX is the typed picker and nothing more.** Owner: *"The typed picker is enough"*. `Array[NodeSubtype]` gets a resource-filtered picker for free (no strings to misspell); no `resource_name` echo and no extra `_get_configuration_warnings` branch in v1.

### Decisions added 2026-09-23 (the #1060 / #1061 pass)

17. **Blighted WIS is the archive as the *application umbrella*, not falloff/duration — supersedes decision 10.** Under the halving model falloff 0.5 → 0.4 is +25 % total on every family at once (a damage umbrella in disguise), and an attacker-side falloff needs the status row to carry a second number. The archive hosts `dot_stacks_per_hit`, the one umbrella `damage_over_time.md` blesses: *knows every plague* — whatever rot you already deal lands harder. Contagion reach (#970) is its later upgrade. Blighted WIS gives up the XP trickle.
18. **Blessed WIS is the XP engine plus recovery.** `wound_heal_per_turn` (*"good pick"*) and a fatter `xp_per_turn` (flat and %), replacing the small `xp_per_turn +%` pool so decision 11 holds. Rejected: `ap_transfer_rate` (*"hard to balance"*), `sp_gain_on_levelup` (*"incredibly OP"*); tempo and initiative_speed are power, not economy. *"xp_per_turn: dont trade away, if anything boost these modifiers."*
19. **PER's cells.** Blighted PER = `blindness_potency`, trading `sensor_range` (blinding others instead of sensing them). Blessed PER = `blindness_resistance`, trading the flat `vision_range +` pool. Scout arrows stay shared.
20. **Blindness potency is depth, and blindness is commutative.** Uncapped, `ACCUMULATE`, one saturating curve on the *total* power easing to a ~10 % floor (`k / (power + k)`, k = 3 keeps today's power-3 dazzle at 0.5), fractional fade ≈ 0.7. A light blind then a heavy one equals heavy then light because the multiplier is a function of the sum. The owner's concern that 10 % of an extreme vision range still sees is parked (an absolute hop cap needs a clamping bin).
21. **"Stack application" is flat +N stacks per hit, one stat per family** (`{family}_stacks_per_hit`), homed with the family's potency. The flat-versus-increased axis: rewards volleys and blade contacts over the big cast.
22. **v1 vocabulary is 7 stats, not 14**: the four flats, the umbrella, and blindness potency/resistance. Falloff/duration are per-def shapes, tabulated in `damage_over_time.md` (2026-09-23), not stats.

## Three things a spec must not miss

### The subtype roll needs its own salted RNG stream

`ScenePlacement` is the precedent, and it states the reason outright
(`procgen/placement/scene_placement.gd:18-21`): *"Draws come off
[PlacementContext.scene_rng], a stream derived from the run seed … the main
stream is untouched, so a preset with and without keystones rolls the same
terrain."*

Roll subtype off the **main** stream and every modifier roll after it shifts,
so both golden fixtures churn on any `base_chance` tweak and it becomes
impossible to tell a placement change from a content change. Off a salted
stream, only the assignment is new and regular nodes roll exactly as before.

### v1 needs **zero** new stats

Worth stating because it is the scoping win. Potency exists per family;
resistance exists per family. The mechanism needs no vocabulary expansion at
all — the 12 + 2 stat build-out is a later, separate lane.

That splits cleanly:

- **The mechanism is inert by default.** With `subtypes = []` no node rolls anything, and every pool's `subtypes` is empty (= any), so the two-key filter selects exactly what it selects today — and `to_entries` appends no subtype segment, so every entry id is byte-identical too. **Unchanged goldens are the mechanism child's acceptance test** (necessary, not sufficient — see the child's own red tests).
- **Authoring the content is a balance change to shipped content** — marking potency pools blighted-only, moving the four resistances out of universal into per-archetype blessed pools. That is `blocked-by` **#975**: resistances leaving the universal pile is precisely the case the fixed slice exists to make safe.

### ~~`forbid_tags` is one list across all six archetypes~~ — resolved, and one premise here was false

**Superseded by decision 12** (the set gate). Kept because the *correction*
matters to anyone re-reading the old argument.

The complaint stands and is what killed `forbid_tags`: a single global list
cannot express *"blighted DEX keeps armor, blighted STR loses it."* The set
gate says it per-pool instead — see ② above.

**The premise that was false:** this section used to claim *"`ArchetypePolicy`
already carries `weight_profiles: Array[Resource]`; `NodeSubtype` probably
wants the same."* It does not. `weight_profiles` lives on
**`GraphProcgenContent`** (`procgen/modules/content.gd:20`) as a **set-wide**
array consumed through `WeightContext` — there is no per-identity precedent to
mirror, and a per-subtype profile would be a new composition path in the draw
loop, not a copy of an existing one.

**And the use case it was reaching for is already covered.** Blessed DEX
rolling crit factor *"more often than on regular"* is a **second pool** for the
same (stat, op, archetype) gated `subtypes = [bless]` with a higher
`pool_weight` — which the set gate expresses directly, and which is exactly
what the entry-id segment in ② exists to keep from colliding. Per-subtype
weight profiles are **not deferred, they are unnecessary**.

## Open questions

1. ~~What is blighted WIS?~~ **Settled** (decision 10): the blighted archive — WIS hosts the shared cross-family knobs. Destination only; the stats do not exist yet.
2. ~~Is blessed WIS a budget bump?~~ **Settled** (decision 11): no — pool-shaped, the rule holds. The shape the owner wants ("similar mods at lower budget cost", or rare barely-touched stats) is not authorable today. Both WIS cells are out of v1 and have their own issue.
3. ~~How is subtype generated?~~ **Settled**: a per-node `base_chance` on each `NodeSubtype`, regular as the remainder. Promote to clustered regions only if the speckle reads badly in play.
4. **Can a subtype's territory be converted?** Does holding blessed nodes cleanse adjacent blighted ones, or is subtype fixed at generation? A conversion mechanic would make the map a battleground in a second dimension; fixed is far cheaper.
5. **Do the four families each need a fifth/sixth sibling** now that PER takes blindness and WIS takes none? Owner noted *"Blight is a good name also for if we ever need a 5th."*
6. ~~What do the `forbid_tags` lists actually key on?~~ **Moot** (decision 12): there are no subtype forbid lists. The give-up is the per-pool set, which keys on nothing — it names resources. No new tags are needed by this axis at all.
7. **Exact stat count.** 14 is the proposal above (12 per-family + 2 shared). Owner's range was 8–16, *"maybe up to 16 if we flesh them out with more bespoke tweakables."*
