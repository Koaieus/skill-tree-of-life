# Combat — Worked Examples & the Battle-Formula Discussion

> **Status:** 🔨 Active design. This is the working document for nailing down the one thing the combat system is missing: **how offensive stats vs. defensive stats resolve into damage (or no damage).** Everything here is a *vehicle for that decision* — the numbers are provisional placeholders chosen to be reproducible, not commitments.

---

## How to use this doc (session handoff)

If you're a fresh session picking this up: the goal is to **choose the damage function** and calibrate it against concrete fights, *before* writing any Godot combat code. Read in this order:

1. This intro + **The Tempo Axiom** (the target we're fitting to).
2. **The Provisional Ruleset** (so every number below is reproducible).
3. **Fight A** — validates the kill-speed anchor and shows tempo is set by positioning.
4. **Fight B** — *the decision fight.* Runs one attack through three candidate defense functions side by side. **This is where the discussion should start.**
5. **Fight C** — positioning & targeting: the core-on-a-leaf trap, dismemberment in real numbers.

Then the open decision is explicit at the bottom: **pick a defense function**, then build a tiny headless damage-calc harness that replays these three fights as assertions.

**Background docs:** GDD §5 + §11a (the plan), `combat_system.md` (the damage pipeline + degree rules + Open Questions), `stat_system.md` (canonical Stat Vocabulary). Where this doc and those disagree on numbers, **this doc's numbers are throwaway** and those docs' *structure* is authoritative.

**Hard requirement for any example:** two real entities of **≥10 nodes each**, with specified per-node stats, *plus the surroundings* — the neutral/contested nodes around and between them. Positioning is key; targeting is key. A fight with no map is not a fight.

---

## The Tempo Axiom (revised — tiered, leaning fast)

The old single-point anchor ("3–4 unbuffed volleys ≈ one node") is replaced by a **tiered** target. Kill-speed should depend on matchup and defense, and the whole curve leans **fast**:

| Tier | Volleys (or equivalent attacks) to dismember one node | When |
|---|---|---|
| **Fast** | **1–2** | Super-effective color, vulnerable/exposed target, low defense, *or converged fire* |
| **Regular** | **3** (≈2–3) | Baseline exchange, even matchup, modest defense |
| **Grindy** | **5+** | Well-defended hub, ineffective matchup, hard armor |

**Design stance (from the designer, load-bearing):**
- **Tempo must be relatively high.** A turn-based game where nodes barely die becomes *static* — death spiral of boredom. Keep it moving.
- **Nodes dying too quickly is better than too slowly.** Fast death forces adaptation: rerouting around lost cut vertices, repositioning leaves, rebuilding broken rings, healing Reservations. That churn *is* the gameplay.
- So when in doubt, **tune faster.** "Regular" sitting at ~3 (not 4) is deliberate, and even 2 is acceptable for the baseline. The grindy tier exists to make fortresses *feel* like fortresses, not to slow the general game.

Everything below is checked against these tiers.

---

## The Provisional Ruleset

> ⚠️ **All numbers are placeholders for these examples only.** They exist so the fights are reproducible and the tiers are checkable. Real calibration is a later Balance-phase activity.

> 🔧 **Predates the //10-spine rewrite — needs re-derivation (flagged, not yet redone).** These fights were authored against the *older* combat model. Since then `combat_system.md` adopted: (1) the **//10 scaling spine** (`attribute//10`, not `floor(attribute/4)`; base counted once); (2) **degree-defense removed** — node HP scales with **CON**, *not* `10 + (degree − 1)`; (3) **melee = phantom blade** — damage counts swept **contacts** (edges + spikes + faces), *not* tapped Buffer nodes. The fights' *structure and conclusions* (tempo tiers, positioning-as-system, the defense-function decision) still hold; the specific arithmetic below should be re-derived under the spine in Balance phase. Left as-is for now so the worked examples stay internally consistent.

Base-10 anchor (⚠️ pre-rewrite numbers — see flag above):
- **Node HP** = `10 + (total_degree − 1)` *(old degree-defense model; under the new model HP scales with CON)*.
- **Attributes** start ≈ **10** (STR/DEX/INT, plus CON/WIS/PER).
- **damage_floor** default **1** (Bulwark 3, can go negative → heal-on-hit).

Provisional **outgoing** (⚠️ old `floor(attr/4)` per the flag; the spine uses `attr//10`):
- **Ranged**, per firing leaf: `2 + floor(DEX / 4)` → DEX 10 = **4**/leaf. Volley = Σ leaves in euclidean range of the target.
- **Melee** *(old tapped-Buffer model)*, per node: `3 + floor(STR / 4)` → STR 10 = **5**/node. *(New model: per swept contact of the phantom blade.)*
- **Magic**, source output: `3 + floor(INT / 4)` → INT 10 = **5**. Then per-spell propagation (e.g. Lightning Bolt: hit target, then all neighbours at ×0.5 per hop).

Provisional **taken** (the open question — three candidates compared in Fight B):
```
taken = max(damage_floor, f(outgoing, armor, resist[attack_color]))
```
Defense applies **once per attack** (combined volley/tap sums first, then subtract once).

Severance bookkeeping (from `stat_system.md`): severing an arm of **N** nodes → `health.decrease(N)` on the entity **and** N points enter SP **Reservation** (heal back 1:1 via `health_per_turn`).

Crits, statuses, the triangle multiplier: **deferred** — layered on later, once `f` exists.

---

## Fight A — Glass vs. Glass (validates the anchor; tempo = positioning)

Two small, lightly-defended, DEX-leaning entities. The point: **the tier you land in is mostly a positioning choice.**

### The board

**Player entity `P`** (Allround, DEX-leaning) — 10 nodes. Spine `P1–P2–P3–P4–P5`, core on **P3** (interior, degree 2). Firing leaves hang off the spine.

| Node | Type | Degree | Role | Notable stats |
|---|---|---|---|---|
| P3 ⊙core | R/G | 2 | core seat (interior, safe-ish) | STR/DEX/INT 10; core aura |
| P1, P5 | G | 1 | leaf / firing port | DEX 10 |
| P2, P4 | G | 3 | connector (holds 2 leaves each) | DEX 10 |
| La,Lb (off P2), Lc,Ld (off P4), Le (off P5) | G | 1 | leaves / firing ports | DEX 10 |

**Enemy entity `E`** — symmetric 10-node mirror: spine `E1–E2–E3(core)–E4–E5`, leaves `Ma,Mb` off E2, `Mc,Md` off E4, `Me` off E5. All armor 0, resist 0 (true glass).

**Surroundings (matters):** a thin band of ~6 neutral nodes lies between P's right flank (P4/P5 leaves) and E's left flank (E2 leaves). Allocating into them is how a leaf gets within **euclidean** range of an enemy node. Whoever advances exposes leaves; whoever over-advances exposes a cut vertex.

```
   La  Lb              (neutral band)            Ma  Mb
     \ /        n — n — n — n — n — n              \ /
P1 — P2 — P3⊙— P4 — P5 · · · · · · · · · E5 — E4 — E3⊙— E2 — E1
                \  \                       /  /
               Lc  Ld·····(in range?)···Me Mc  Md
```

### Resolution (defense = 0, so all three candidate functions agree here)

Target: **Ma** (E's leaf, degree 1, HP 10, armor 0).

- **One** P-leaf in range fires: `outgoing 4` → Ma 10→6→2→dead. **3 volleys** → *Regular tier.* ✓ matches the anchor.
- **Two** P-leaves converged in range (player spent a turn allocating a second leaf into range): `outgoing 8`/volley → Ma 10→2→dead. **2 volleys** → *Fast tier.* ✓
- A **3-leaf** converge (`12`) one-shots Ma. *Fast tier, extreme.*

**Takeaway 1 — tempo is a positioning choice.** Same target, same stats; the only variable is *how many leaves you brought into euclidean range.* That is the core ranged decision and it's entirely topological/spatial.

### Cheap kill vs. valuable kill (targeting)

Killing Ma removes **1** node — minor. Instead target **E2** (degree 4: E1, E3, Ma, Mb), a **cut vertex**: it's the only path from E's core (E3) to the arm {Ma, Mb, E1... }. E2 is HP 13.

- 3-leaf converged volley (`12`) vs E2 (armor 0): 12 → E2 13→1, second volley kills. **2 volleys.**
- On E2's death: the arm {Ma, Mb, E1} (3 nodes) loses its path to E3 → **islands → dissolves immediately.** E drops from 10 → 6 nodes, takes `health.decrease(3)`, 3 SP reserved.

**Takeaway 2 — targeting beats raw damage.** Same two volleys, but aimed at the cut vertex they delete *4 nodes* (E2 + 3 islanded) instead of 1. The enemy is now crippled and must spend its turn healing Reservations / rerouting instead of attacking. *This is the churn high tempo is meant to create.*

---

## Fight B — Spear vs. Wall (THE decision fight: which defense function?)

This is the one that matters. A converged DEX **spear** drives into a fortified **hub**. The wall's defense is exactly where the three candidate functions diverge — so we run the *same* attack through all three.

### The board (abbreviated to the contact point)

**Player `P`** lands a **3-leaf converged volley**: 3 × (DEX 10 → 4) = **outgoing 12** (raw, before the target's defense). (Full 10-node P as in Fight A; here only the volley total matters.)

**Enemy `E`** is a Bulwark-style wall, 12 nodes, built as a dense cluster (so its hub has redundant paths — see Fight C for why that matters). The target is hub **H**:

| Node | Type | Degree | HP | armor | resist_g | Notes |
|---|---|---|---|---|---|---|
| **H** (target) | R | 4 | 13 | varies → | varies → | the wall node; we test 3 armor levels |
| (H's 4 neighbours) | R/W | 2–3 | 11–12 | 2 | 1 | dense inner cluster, no single cut isolates H |

We test H at three defense levels: **light** (armor 2, resist_g 1), **medium** (armor 5, resist_g 2), **heavy** (armor 10, resist_g 3).

### The three candidate functions

**Candidate 1 — Flat subtraction** (the current `combat_system.md` pipeline):
`taken = max(1, outgoing − armor − resist_g)`

**Candidate 2 — Diminishing ratio** (armor never fully stops damage):
`taken = max(1, round(outgoing × outgoing / (outgoing + armor + resist_g)))`

**Candidate 3 — Hybrid** (armor = hard wall, resist = soft matchup scaling):
`taken = max(damage_floor, round((outgoing − armor) × outgoing / (outgoing + resist_g)))`

### Results — `outgoing = 12` vs H (HP 13), volleys-to-kill

| Defense level | Cand. 1 (flat) | Cand. 2 (ratio) | Cand. 3 (hybrid) |
|---|---|---|---|
| **Light** (a2 / rg1) | 12−3 = **9** → 2 volleys | 12²/15 = 9.6→**10** → 2 volleys | (12−2)·12/13 = **9** → 2 volleys |
| **Medium** (a5 / rg2) | 12−7 = **5** → 3 volleys | 12²/19 = 7.6→**8** → 2 volleys | (12−5)·12/14 = **6** → 3 volleys |
| **Heavy** (a10 / rg3) | 12−13 < 0 → floor **1** → **13 volleys** | 12²/25 = 5.8→**6** → 3 volleys | (12−10)·12/15 = **2** → 7 volleys |

### What the table tells us

- **Candidate 1 (flat)** has a **cliff**: once `armor ≥ outgoing`, only `damage_floor` leaks — the node becomes near-immortal to that volley (13 volleys!). Legible and simple, and it *is* how the Bulwark's fantasy works (armor + negative floor = wall). But it makes mid-fight feel binary: either your volley beats the armor or it basically doesn't. Against the tempo stance ("lean fast, churn"), the heavy column is a problem — that's a static slog unless you converge *even more* fire.
- **Candidate 2 (ratio)** **never grants immunity** — armor always *slows*, never *stops* (heavy is still 3 volleys = grindy, not infinite). Beautiful for tempo. But the **Bulwark's "chip immunity / heal-on-hit" identity can't emerge from it** — you'd have to bolt that on as a special case, which is exactly the kind of special-casing we're trying to avoid.
- **Candidate 3 (hybrid)** gives us **both levers cleanly**: `armor` is the *hard wall* (can floor, can go negative — Bulwark lives here), while `resist_g` is *soft matchup scaling* (the emergent triangle — never grants immunity, just bends the curve). Heavy armor is a real wall (7 volleys) but not a brick-wall-of-13, so tempo survives; and the fortress fantasy is intact because `armor` and `damage_floor` still behave like a wall.

**Recommendation to bring into the discussion: Candidate 3 (hybrid).** It maps the two defensive stats onto the two *roles* we actually want — `armor` = the fortress stat (Bulwark, structural), `resist_*` = the situational triangle (emergent, respec-able) — and it keeps tempo high (no infinite walls from resist) while preserving the Bulwark's hard-wall identity (from armor + floor). But **this is the open call** — Fight B exists to make the trade-offs concrete, not to foreclose them.

> Note how Fight B also re-proves Takeaway 1: even the *heavy* wall folds to **converged fire** — a 4- or 5-leaf volley (outgoing 16–20) cuts the volley count sharply under any candidate. The answer to armor is positioning, every time.

---

## Fight C — The Dismemberment (positioning & the core-on-a-leaf trap)

The designer's example, in numbers: *"if an entity's core node is on a leaf node, and you kill that leaf's neighbour, you sever literally ALL of its nodes in one go."*

### The board

**Enemy `E`** — 12 nodes, but **catastrophically mis-positioned**: its core sits on a **leaf** `Lc` (degree 1). `Lc`'s only neighbour is connector **C**, and *everything else* hangs off C.

| Node | Type | Degree | HP | Notes |
|---|---|---|---|---|
| **Lc** ⊙core | R | 1 | 10 (+ core_health) | core on a **leaf** — the whole mistake |
| **C** | W | 6 | 15 | **the only edge** from the core's node to the body; a cut vertex carrying 100% of E's connectivity |
| body ×10 | mixed | 1–4 | 10–13 | hubs, leaves, economy — *all of it* reachable only through C |

```
        ┌── b1 — b2 — b3 (leaves/hubs)
Lc⊙— C ─┼── b4 — b5 — b6
        └── b7 — b8 — b9 — b10
```

**Player `P`** is positioned with melee Buffer nodes and leaves adjacent/in-range to **C** (this took setup — *positioning is the cost of admission*).

### Resolution — don't kill the core; cut C

`Lc` (the core node) is degree-1 and likely the best-defended node E owns (core_health + aura + the player piling armor on it) — a bad target. **C** is the soft underbelly.

Bring C down (HP 15). Options under the provisional ruleset:
- **Melee:** tap **3** Buffer nodes adjacent to C: 3 × (STR 10 → 5) = **15** → if C's armor is low, that's a near-one-shot (one big tap, maybe two). *Fast tier.*
- **Ranged:** a **4-leaf** converged volley = `16` raw → 1–2 volleys depending on C's armor.

The instant **C dies**:
- The graph splits into **{Lc + core}** (1 node) and **{the 10-node body}** (no path to the core).
- The body is an **island → dissolves immediately.** SP Reservation ×10. `health.decrease(10)`.
- **E goes from 12 nodes to 1 node in a single resolved attack.** The core *survived* — you didn't kill the core node — but the entity is gutted: no economy, no attackers, 10 points reserved, effectively dead next turn.

**Takeaway — core placement is survivability, and cut vertices near the core are catastrophic.** One snipe on C did what grinding the core directly never could. Compare to a well-built entity (Fight B's dense cluster, or a **ring** around the core): there, *no single cut* isolates anything — you'd need two cuts on a 2-edge-connected ring, which the tempo/edge-cutting economy makes expensive. **Rings defend; leaves with cores on them die.**

### The race (why high tempo matters here)

A smart `E`, seeing C threatened, will spend its turn **allocating a second path** from the core side to the body (e.g. `Lc` is degree-1 so it can't, but it could relocate the core off Lc, or bridge `b1` back toward Lc) — **removing C's cut-vertex status.** So the attacker must **kill C before E reroutes.** That race — cut-before-they-reroute vs. reroute-before-they-cut — is the adaptation churn the fast-tempo stance is explicitly designed to produce. If kills were slow, the defender would always have time to fix their topology and the dismemberment fantasy would never land.

---

## The Open Decision (for the next session)

1. **Pick the defense function** `f(outgoing, armor, resist)` — Fight B lays out three candidates; **hybrid (Candidate 3) is the current recommendation** (armor = hard wall / Bulwark home; resist = soft triangle). Confirm or override.
2. **Lock the per-attack outgoing formulas** (the `2/3 + floor(attr/4)` sketches) or replace them — but keep them satisfying the Tempo Axiom tiers.
3. **Decide action economy** (1 attack/turn vs. `action_points` vs. one-of-each) — it multiplies tempo directly. (combat_system.md OQ20.)
4. **Then build a headless harness** in Godot (no UI): encode `f`, the outgoing formulas, and the degree/HP rules; replay Fights A/B/C as assertions; confirm hand-math == code. Only after that does combat code touch the real game.
5. **Deferred until 1–4 land:** crit, statuses (poison/bleed), the triangle *multiplier*, and Bulwark's negative-floor extreme.

> **Reminder for whoever runs this:** every new example must use **two ≥10-node entities and their surroundings**. Positioning and targeting are not flavour — they are the system. A damage number without a map is meaningless here.
