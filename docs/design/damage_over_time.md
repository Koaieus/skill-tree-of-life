# Damage over time — the DoT family (#952 design session, 2026-09-20)

> Design doc: the *model*. What shipped and how it is wired lives in
> `docs/domain/effect-system.md` (status slice) once the #952 children land.
> Numbers here are **anchors for the owner to tune**, never pins.

## Why a family and not one poison

An entity's node is a point in six defensive dimensions, and each one blocks a
*different shape* of incoming damage. A single DoT that beats all of them is
today's `%max HP, unmitigated` poison: it counters everything, so it is the
only thing worth using. Owner, 2026-09-20: *"yes 100%, and that was kinda the
reason i posted that comment."*

| Axis | Blocks | Growth | Blind spot |
|---|---|---|---|
| **HP bulk** (`node_health = 10 + CON`) | everything, linearly | +1 CON/level for free, +% rolls | anything denominated in % of itself |
| **Armor** (flat per hit) | mid-size hits | battlefield-found only | unmitigated damage; irrelevant vs one huge hit |
| **Floor** (`min_damage_taken`, 3 → 0 → negative) | chip and floods; below 0, chip *heals* | battlefield-found, rare | unmitigated damage; anything that raises the floor |
| **Regen** (gated ramp, reset by any damage) | attrition across turns | node-local stats | anything that shuts the gate every turn |
| **Core heal aura** (ungated, flat, √CON) | chip near the core | class | heal-block; damage above the trickle |
| **Topology** (2-connected, degree) | cascades | play | a *cure* axis, not a damage axis |

Growth makes bulk free and mitigation rare, so the generic late entity is a
big bucket, and the specialists are the **bunker** (armor 50+, floor ≤ 0), the
**fortress** (aura + regen) and the **CON stacker** (hundreds to thousands of
node HP). Each wants its own answer.

## The four members

| Member | Denomination | Answers | Weak against | Feel |
|---|---|---|---|---|
| **Poison** | flat HP per stack per tick, unmitigated | armor, sub-zero floor | bulk | "the green segment fades unless you keep hitting" |
| **Corruption** | % of max HP per stack per tick, unmitigated | bulk (the CON stacker) | nothing but rarity and cure — a fully corrupted node dies, at level 1 too. *"the harsh reality of % damage"* | rare, late, dreadful |
| **Curse** | raises `min_damage_taken` by stacks | bunker: makes every hit land again | deals nothing alone; a multiplier on floods and volleys | safe to spread wide |
| **Wither** | multiplies `healing_received` down, below zero | fortress: the aura heals its own core to death | nodes nobody heals | the "undead" sandbox |

Every member becomes lethal in sufficient amount. Owner: *"like even water can
be poisonous if you drink too much of it. big curse? better watch out. massive
poison stacks? you're DOOMED. high corruption? DOOMED."* There is deliberately
**no per-tick clamp**: a ranged build emptying a quiver of poison arrows into a
node kills it that turn.

## One model for all four: stacks that halve

A status on a node is **one number, its stacks** (`power`). Each tick the def's
`_on_tick` spends the pre-decay stacks, then the stacks **halve** (proportional
decay, tail cleared below 1). Total effect of N stacks applied once is 2N,
linear in what you did; sustained application of N per turn settles at 2N.

Why not the other timers (rejected 2026-09-20):

- **Linear decay with damage ∝ stacks** (what shipped in #874): total is
  N(N+1)/2, quadratic. With uncapped stacks a 40-arrow volley is 820 HP. So
  "uncapped" and "linear decay" cannot both ship, and the owner wants uncapped.
- **Fixed duration refreshed on apply**: linear, but adds a second field per
  row (turns left), a resync column, and the "last applier resets vs max" fork.
- **Per-hit instances** (PoE): linear and faithful, but the slice becomes a
  list and every reader changes.

Stacks are **uncapped**. Blindness and armor-break keep their flat decay and
caps; the decay mode is a per-def knob, not a global change.

## Applying: flat stacks per hit, scaled by percent stats

- **Stacks per hit is a float authored on the applier** (ammo type, on-hit
  effect, blade vertex): a dart 0.5, an arrow 1, a blade contact 2, a venom
  cast 8. Hit size never scales stacks — that would reintroduce the
  pre/post-mitigation legibility problem for no gain.
- **Potency** is an attacker stat per type (`poison_potency`, …), default 1.0,
  multiplying the stacks landed. Procgen rolls it **only as `INCREASE`**
  (+7% / +21% / +49%, the attribute ladder), because a flat +1 on a stat
  designed at 1 is a doubling. A rare keystone roll *may* `ADD_BASE +0.1`, and
  a specialised core class may sit at +0.2..0.5 baseline (owner, 2026-09-20).
- **Resistance** is a defender stat per type (`poison_resistance`, …),
  default 0, a fraction that reduces stacks *incurred*, read node-locally like
  armor. Battlefield-found, universal defence rolls. It mirrors potency and
  snapshots at apply, so the row still holds one number. Faster decay was
  the alternative and stays available as a **class** identity later.

`landed = per_hit × potency(attacker) × (1 − resistance(node))`, computed once
at land, on the landing world.

## Cures

Ordered from "always there" to "a choice":

1. **Fading.** Halving means a status is gone in a few turns unless the
   pressure continues. This is the baseline counterplay and costs nothing.
2. **The topological cure.** Statuses already void on deallocation; deallocate
   and reallocate the limb, or move the core off a corrupted node and drop it.
   DP/MP, never AP. Stated design, but owner: *"not the most satisfying (bit
   hacky)"* — never the only cure.
3. **Connectedness cures** — follow-up issue. Decay scales with the node's
   entity degree: the body fights it, a poisoned leaf lingers, a poisoned
   node deep in territory clears fast. Self-loops ("purity rings") are an
   open question there: special interaction, or simply high degree?
4. **Cleansing / healing fountain addons** — follow-up. The defensive
   counterpart of each type's offensive addon; cleansing and healing may be
   two addons.
5. **One cleanse spell per family**, and possibly a **cure-all** that is
   rare, expensive or costly — never castable willy-nilly.

Regen does not cure by itself: a DoT tick counts as damage and keeps the
regen gate shut (owner, 2026-09-20), so poison is pressure you cannot simply
step back from; the halving does the fading.

## Wither below zero — the special case

`healing_received` is a multiplier stat, default 1.0; wither plants a
node-local `MULTIPLY` below it. Below zero a heal becomes damage, *and that
damage does not close the regen gate* (owner call, 2026-09-20: *"yes special
case. it ruins your healing to making you effectively undead"*). So a withered
node that is left alone ramps its regen up turn after turn and heals itself to
death — a playstyle that must damage nodes to start the ramp and then must
**not** touch them. The core aura is ungated and heals the core's
neighbourhood, so a withered fortress unheals from its own sanctuary.

## Content per type

Each DoT gets, as siblings of the model work: an **arrow ammo type**
(`attack/ammo/types/`), an **addon** (with a blade-copy face for melee, the
#951 shape), and **one to two spells** — whichever creates build variety
(*"oh you're stacking CORRUPTION, not POISON, well we got some spells in store
for that too"*).

## Contagion (parked)

A spreading DoT. Read as a multiplier on any family (like curse), not a fifth
member: a spell that copies or splits the target's stacks onto its owned
neighbours. It makes connectedness double-edged — a dense body cures faster and
spreads faster. Own issue.

## The matrix (proposal, reference points)

Reference: an arrow is `1 + DEX/20` (1–3 early, ~11 at DEX 200); the floor of
3 dominates early; armor 15 already floors a late hit. A 20-arrow poison volley
= 20 stacks = 38.75 HP over five turns (20, 10, 5, 2.5, 1.25 — stacks are floats, never rounded); sustained every turn ≈ 40/turn.

| Node HP | Poison (one 20-arrow volley / sustained) | Direct arrows, armor 0 / 15 / 100 | Verdict |
|---|---|---|---|
| 20 | dead next tick / — | 40 / 60 / 60 per volley | both fine |
| 200 | 19% / dead in 5 turns | 40 / 60 / 60 | poison ≈ doubles output vs armor |
| 2000 | 2% / ~50 turns | 2% / 3% / 3% per volley | poison nil, by design — corruption's job |
| any, floor −3 | as above | **heals 60 / volley** | poison is the only thing that lands |

Corruption at 2% per stack: 10 stacks on a 2000-HP node is 400/tick; on a
20-HP node 0.4/tick. Curse +10 turns a 50-node 1-damage flood from 150 into
650 against any armor.

## The stat vocabulary and the decay shapes (#1060 pass, 2026-09-23)

Owner's model, verbatim: *"each application adds 1 stack (unless 'extra stacks
applied per application' stat value > 0), and damage scales with potency and
reduces with resistance, and total damage is then up to how falloff behaves."*

**Landing:** `landed = (per_hit + Σ extra_stacks(attacker)) × potency(attacker) × (1 − resistance(node))`,
flat before the multiply. The extra-stacks stats are `{poison,corruption,curse,wither}_stacks_per_hit`
(flat, per family, default 0) plus one shared umbrella, `dot_stacks_per_hit`, read by the
four DoT defs and not by blindness/armor-break (`StatusDef.extra_stacks_stat_ids`, one array,
one loop). A flat bonus doubles a 0.5-stack dart and barely touches an 8-stack cast: the
flat-versus-increased axis. The umbrella never scales damage — potency stays per family.

**Falloff and duration are not stats.** Under halving, total effect is stacks ÷ decay
fraction, so a shared falloff stat is +25 % on every family per 0.1 step — the umbrella trap —
and an attacker-side falloff needs the row to carry the applier's decay (the second field
rejected above). The shape is per def instead:

| Status | Effect | Feel | Shape | Total per stack applied once |
|---|---|---|---|---|
| Poison | flat HP per stack per tick | fades unless you keep hitting | FRACTION 0.5 | 2 |
| Corruption | % max HP per stack per tick | rare, dreadful, lingers; cure or die | FRACTION 0.8 | 5 stack-ticks (10 % max HP at 2 %/stack/tick; rescaled with the minting mechanics) |
| Curse | +min_damage_taken per stack | a legible "cursed for N turns" window | FLAT 1/turn | window of N turns |
| Wither | healing multiplier below 1; below zero the node *degenerates* — kept, *"a niche but fun concept"* | must outlast the victim's patience | FRACTION 0.75 | 4 |
| Blindness | vision multiplier on a saturating curve | deeper and longer the more lands; recovers slowly first | FRACTION 0.7, uncapped, ACCUMULATE | see node_subtypes.md D20 |
| Armor break | as shipped | | FLAT | |

Corruption with **no decay, cure-only** was floated as the bold alternative; revisit when the
cleanse lane exists. A defender-side "this ground sheds rot" knob (node-local decay bonus)
stays available for the connectedness cure. Corruption on the health bar and turn-start vs
turn-end proc: #1092.
