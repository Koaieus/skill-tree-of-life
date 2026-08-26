# Dormant Cores

A **Dormant Core** is a single-node entity that holds one SkillNode and never
moves or acts. It has no initiative, no vision, and no AI; it exists to deny a
node until someone kills it, and to pay out when they do. Mechanically it is a
real `Entity` (`entity/blocker/blocker_entity.tscn`) so damage, the allocation
gate, death cleanup, and loot are all existing systems rather than a special
case.

## Two names, and which one goes where (#587)

| | name | where |
|---|---|---|
| player-facing | **Dormant Core** | `Entity.display_name`, tooltips, design docs, anything a player reads |
| internal | **blocker** | every code identifier — `BlockerSize`, `spawn_blocker`, `blocker.tres`, `blocker_per_*`, the `Blocker_*` node names |

`blocker` self-describes the *mechanic* very well, so the code keeps it. It is a
poor name for the *thing*, which is why nothing a player sees uses it.

The rename was deliberately **not** applied to code identifiers. Renaming an
`@export` var makes Godot drop the old key from any saved resource and silently
fall back to the default — for `blocker_per_small` / `blocker_min_hops_from_core`
that would quietly change level generation in every authored `GraphProcgenConfig`
with nothing to catch it. Not worth it for an internal name that is already
accurate.

## Who shoots at one (#604)

A Dormant Core is `targeted_by_ai = false` on its `Faction`, so `AiRecon` drops
its nodes from every NPC target list. Two things that filter is deliberately
NOT:

- **It is not the attitude relation.** A blocker stays `HOSTILE` to everyone,
  which is what lets the *player* clear one and what makes the forced-dealloc
  cascade and XP gating treat a cleared blocker as a real kill. Moving the
  filter into `Entity.attitude_to` would silently disarm the player too.
- **It is not absolute.** It is the NPC's *default stance*, re-decided every
  turn.

The exception is being **growth-capped**: an NPC with no unowned node adjacent
to its territory has nowhere left to allocate. If the thing walling it in is
scenery it refuses to look at, it banks SP forever and its turn does nothing.
So `AIController` asks `AiRecon.is_growth_capped()` once per turn and sets
`Entity.ai_growth_capped` from the answer; `AiRecon.is_ai_target()`
reads it and unlocks blockers for that turn. Kill, relic, expand.

Four details that are load-bearing:

| detail | why |
|---|---|
| asked **after** the growth step | "nowhere left to allocate" is a fact about the post-growth board, not a guess about the pre-growth one |
| **topological only** — never "can I afford it" | an entity banking SP with nowhere to spend it is precisely the case this must answer *yes* for |
| **both** consumers of `is_ai_target` unlock | the target list AND `AiCombatScorer.expected_damage`'s per-hit filter; unlocking only the list enumerates candidates that score 0 EV, so the AI would attack only cores it could one-shot |
| always **assigned**, never only set | the stance must not outlive the turn that earned it, or an NPC that broke out once keeps shooting scenery |

Growth then runs a **second** pass after the attack loop, so the freed node is
allocated on the same turn as the kill — and allocating it is what claims the
relic (NPCs auto-pick each loot round, see `SkillDustAddon`).

### Unlocking is not enough — the door has to win

Making a core *targetable* only fixes the case where it is the only thing in
sight. A capped NPC that also sees a real hostile scores both on raw EV, so a
distant enemy wins the tie and the wall beside it never gets hit: the same
"stuck" complaint in a different costume, and a LARGE core (high HP, no kill
bonus available) loses that comparison every turn forever.

So `AiCombatScorer` carries a **breakout bonus**: while `ai_growth_capped`, any
target that *borders the attacker's own territory* scores `_BREAKOUT_WEIGHT`.
Depleting a node force-deallocates it, so a bordering node is a door — and
nothing about that is blocker-specific, which is the point. A capped NPC walled
in by a real camp punches through it on exactly the same reasoning.

It is ungated by `ai_tier` (like the kill bonus — being stuck is not a tactical
subtlety a naive brain is allowed to miss) and sized to sit *between* the two
things it is ordered against: above any ordinary EV difference, below
`_KILL_BONUS` on a non-door target, since a kill that is right there is still
worth taking and the next AP re-evaluates back onto the door.

Deliberately not built: any analysis of *which* faction is capping the NPC, or
a proximity filter on which cores unlock (preference *among* unlocked
candidates is the breakout bonus's job, above). If an NPC is walled in by camps rather
than cores there is no adjacent core to unlock, so frontier-empty is
behaviourally identical and far simpler; and "unlock all" is self-limiting
because candidate enumeration only ever yields in-reach targets.

## Sizes, boards, and loot tiers

Three sizes (`GameRoot.BlockerSize`), each with an authored stat board (which
sets the held node's HP) and an authored **loot book** — a `SpellBook` whose
spells the killer's relic can offer. Blockers never cast; the book is purely
what they carry.

| size | book | N |
|---|---|---|
| SMALL | bruiser, healing_beam | 2 |
| MEDIUM | leafblower, resonator, trail_blazer | 3 |
| LARGE | reverberator | 1 |

The tiers are a **loot-rarity** axis, deliberately decoupled from `SpellDef.min_degree`
(a cast-time gate). `healing_beam` is the clearest case: cheap to obtain, still
needs degree 3 to cast.

`spark` and `lightning_bolt` are in no book — `spellbook_default.tres` makes them
innate for every entity, and `SkillDustAddon._exclude_permanently_known` drops
innate spells from an offer, so listing one would be a dead entry that still
inflated the book size. `test_spellbook_prune.gd` asserts both that rule and
that every authored spell is in some book or explicitly excluded.

## The loot-book prune (#586)

A relic's claimant picks exactly **one** spell from whatever is offered, so the
only lever on how fast spells spread is **how often a kill offers nothing**.
That is what the prune is for — not narrowing the choice, which
`_exclude_permanently_known` already does for free.

At spawn, each Dormant Core copies its tier book and pops random spells off the
copy until a roll fails (`SpellBook.duplicate_pruned`). With `n` spells left, it
pops with probability `n / (n + m)`:

```
E[kept]      = n * m / (m + 1)
P(kept == 0) = 1 / C(n + m, n)        # integer m
```

`m = 1` is the special case where every outcome in `{0..n}` is **equally
likely** — maximum variation, and `P(empty) = 1/(n+1)`. That makes book size the
whiff dial: 50% for N=1, 33% for N=2, 25% for N=3, 20% for N=4.

**`m` is tuned DOWN to slow spell spread, never up.** Raising it keeps more
spells, so kills offer nothing *less* often — at n=4, P(empty) falls from 20%
(m=1) to 2.9% (m=3). The knob is `GraphProcgenConfig.blocker_spell_prune_m`,
range 0.5–3.0, default 1.0.

The roll is **seeded per placement** by procgen, off the same derived stream as
blocker placement. Every peer re-runs the level scene, so the prune is
reproduced rather than received — an unseeded roll would hand two peers
different offers off the same relic. See `.claude/rules/multiplayer-sync.md`.

## Why the tier ladder is not monotonic

LARGE holds a single rare spell and therefore whiffs ~50% of the time, more
often than SMALL or MEDIUM. That is accepted, not an oversight: with only eight
spells authored there is nothing else rare enough to put beside `reverberator`,
and the spells gated behind LARGE are strong enough that a 50% payout is fair.
The books are plain `.tres` arrays, so re-balancing as spells are added is an
inspector edit. A spell may appear in more than one tier — overlap raises both
tiers' payout rate, since N is the whiff dial.

Weights *within* a tier do not exist. If they are ever wanted, that is the point
to promote the books from `SpellBook` to a dedicated loot-table resource; until
then a plain array of `SpellDef` is exactly what a spellbook already is, and the
loot path reads `victim.spellbook` uniformly for every entity.
