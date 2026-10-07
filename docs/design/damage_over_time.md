---
status: exploring
---

# Damage over time — what the DoT family could still grow

> Design doc: the *unbuilt* part of the DoT family. The shipped model — the
> five families, per-def decay, landing, resistance, wither below zero,
> the decay shapes — is `docs/domain/effect-system.md` § "Status effects —
> the DoT model". The *why* is in the ADRs: per-def decay, uncapped stacks and
> rows that differ in character ([0048](../adr/0048-status-decay-is-authored-per-def-rows-differ-in-character-not-numbers.md)),
> every notable stat gets an addon and an arrow ([0023](../adr/0023-every-notable-stat-gets-an-addon-and-an-arrow.md)),
> the two hosts ([0024](../adr/0024-status-effects-have-two-hosts-and-fall-through-a-cracked-core.md)),
> stacks stats composed through parents ([0029](../adr/0029-related-stats-compose-through-parents-folded-at-read-and-every-stat-takes-every-bin.md))
> and resistance as a live filter on the host ([0031](../adr/0031-status-resistance-filters-the-accumulated-row-at-effect-time-on-the-host.md)).
> Numbers here are **anchors for the owner to tune**, never pins.

## Cures still to build

Fading (each def's own decay) and the topological cure (every deallocation path voids a
node's statuses — a spreading status such as Curse spills onto the node's
owned neighbours first) ship. The owner called the topological cure *"not the most
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
exists, and so do the corruption, curse, wither, armor-break and blindness
arrows (#1349, the matrix's ranged column, `aspect_matrix.md`); the
per-family spells are designed in #1318.

## Contagion (parked)

A spreading DoT. Read as a multiplier on any family (like curse), not a fifth
member: a spell that copies or splits the target's stacks onto its owned
neighbours. It makes connectedness double-edged — a dense body cures faster and
spreads faster. Own issue.

## The matrix (proposal, reference points)

Reference: an arrow is `1 + DEX/20` (1–3 early, ~11 at DEX 200); the floor of
3 dominates early; armor 15 already floors a late hit. A 20-arrow poison volley
= 20 stacks = 210 HP over twenty turns (20, 19, 18 … 1 — Poison decays −1 flat).
**The table below was computed under the retired halving decay** (38.75 HP over five
turns per volley, ≈ 40/turn sustained); its verdicts are stale under −1 flat
decay and await a re-read.

| Node HP | Poison (one 20-arrow volley / sustained) | Direct arrows, armor 0 / 15 / 100 | Verdict |
|---|---|---|---|
| 20 | dead next tick / — | 40 / 60 / 60 per volley | both fine |
| 200 | 19% / dead in 5 turns | 40 / 60 / 60 | poison ≈ doubles output vs armor |
| 2000 | 2% / ~50 turns | 2% / 3% / 3% per volley | poison nil, by design — corruption's job |
| any, floor −3 | as above | **heals 60 / volley** | poison is the only thing that lands |

Corruption at 2% per stack: 10 stacks on a 2000-HP node is 400/tick; on a
20-HP node 0.4/tick. Curse +10 turns a 50-node 1-damage flood from 150 into
650 against any armor.

## Decay knobs kept open

- Corruption ships with **no decay** (`corruption.tres`, `decay = null`):
  cure-only until the cleanse lane exists.
- A defender-side "this ground sheds rot" knob (node-local decay bonus) stays
  available for the connectedness cure.
- Faster decay as a **class** identity, instead of resistance.
- Corruption on the health bar: #1092 (readout). Proc timing is settled —
  statuses tick at the afflicted entity's **turn end**, so every tick, the
  first included, can be answered; a last action before a DoT death is
  intended ([ADR 0040](../adr/0040-statuses-tick-at-the-end-of-the-afflicted-entitys-turn.md), #1256).
