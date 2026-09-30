# Damage over time — what the DoT family could still grow

> Design doc: the *unbuilt* part of the DoT family. The shipped model — the
> four families, stacks that halve, landing, resistance, wither below zero,
> the decay shapes — is `docs/domain/effect-system.md` § "Status effects —
> the DoT model". The *why* is in the ADRs: one DoT per defensive axis with
> uncapped halving stacks ([0022](../adr/0022-one-dot-per-defensive-axis-stacks-halve-uncapped.md)),
> every notable stat gets an addon and an arrow ([0023](../adr/0023-every-notable-stat-gets-an-addon-and-an-arrow.md)),
> the two hosts ([0024](../adr/0024-status-effects-have-two-hosts-and-fall-through-a-cracked-core.md)),
> stacks stats composed through parents ([0029](../adr/0029-related-stats-compose-through-parents-folded-at-read-and-every-stat-takes-every-bin.md))
> and resistance as a live filter on the host ([0031](../adr/0031-status-resistance-filters-the-accumulated-row-at-effect-time-on-the-host.md)).
> Numbers here are **anchors for the owner to tune**, never pins.

## Cures still to build

Fading (halving) and the topological cure (every deallocation path voids a
node's statuses) ship. The owner called the topological cure *"not the most
satisfying (bit hacky)"* — never the only cure. The choices still to come:

1. **Connectedness cures** — follow-up issue. Decay scales with the node's
   entity degree: the body fights it, a poisoned leaf lingers, a poisoned
   node deep in territory clears fast. Self-loops ("purity rings") are an
   open question there: special interaction, or simply high degree?
2. **Cleansing / healing fountain addons** — follow-up. The defensive
   counterpart of each type's offensive addon; cleansing and healing may be
   two addons.
3. **One cleanse spell per family**, and possibly a **cure-all** that is
   rare, expensive or costly — never castable willy-nilly.

## Content per type

Each DoT gets an **arrow ammo type** (`attack/ammo/types/`), an **addon**
(with a blade-copy face for melee, the #951 shape), and **one to two spells**
— whichever creates build variety (*"oh you're stacking CORRUPTION, not
POISON, well we got some spells in store for that too"*). Poison's arrow
exists; the corruption, curse and wither arrows and the per-family spells
do not yet.

## Contagion (parked)

A spreading DoT. Read as a multiplier on any family (like curse), not a fifth
member: a spell that copies or splits the target's stacks onto its owned
neighbours. It makes connectedness double-edged — a dense body cures faster and
spreads faster. Own issue.

## The matrix (proposal, reference points)

Reference: an arrow is `1 + DEX/20` (1–3 early, ~11 at DEX 200); the floor of
3 dominates early; armor 15 already floors a late hit. A 20-arrow poison volley
= 20 stacks = 38.75 HP over five turns (20, 10, 5, 2.5, 1.25 — the row is a float; damage lands whole (#1156)); sustained every turn ≈ 40/turn.

| Node HP | Poison (one 20-arrow volley / sustained) | Direct arrows, armor 0 / 15 / 100 | Verdict |
|---|---|---|---|
| 20 | dead next tick / — | 40 / 60 / 60 per volley | both fine |
| 200 | 19% / dead in 5 turns | 40 / 60 / 60 | poison ≈ doubles output vs armor |
| 2000 | 2% / ~50 turns | 2% / 3% / 3% per volley | poison nil, by design — corruption's job |
| any, floor −3 | as above | **heals 60 / volley** | poison is the only thing that lands |

Corruption at 2% per stack: 10 stacks on a 2000-HP node is 400/tick; on a
20-HP node 0.4/tick. Curse +10 turns a 50-node 1-damage flood from 150 into
650 against any armor.

## Decay alternatives kept open

- Corruption with **no decay, cure-only** was floated as the bold alternative;
  revisit when the cleanse lane exists.
- A defender-side "this ground sheds rot" knob (node-local decay bonus) stays
  available for the connectedness cure.
- Faster decay as a **class** identity, instead of resistance.
- Corruption on the health bar and turn-start vs turn-end proc: #1092.
