# #248 — session handoff (after round 5)

**State as of commit `0d6bf77`+.** Rounds 1–5 are done; `docs/design/mvp_decisions.md`
carries D-1 … D-23 and is authoritative. **#248's own open list is exhausted** —
every remaining fork lives on a child issue with the fork written down.

Read this, then `gh issue view 248 --comments` (round 5 comment is the index).

---

## The forks still open, in the order they're worth taking

### 1. #277 — `core_healing` rate + gate

Shape is pinned (heals the **entity** pool, stays a sliver). Open:

- Exact rate — a #268 value, but the *order of magnitude* is a design call.
- **Does it obey a D-9-style damage gate** (reset on damage, ramp on disengage),
  or heal unconditionally like the D-10 aura?
- UI sliver on the core health bar.

⚠ **The coupling to watch:** if `core_healing ≥ dealloc_damage × nodes_lost_per_turn`,
camping becomes viable and D-10's structural anti-camping guarantee is silently
undone. And a substantial rate would require **reversing D-21's grant-the-delta**
decision — the two are near-exclusive. Don't settle this one in isolation.

### 2. #278 — the spell balance pass *(the big one)*

Deliberately deferred out of round 5. Balances the whole spell surface together,
per-`SpellDef`: `mana_cost` × `min_degree` × reach (hops vs euclidean) ×
`seed_damage_fraction` × `damage_multiplier_per_hop` × `base_damage` ×
`int_scaling`.

**The framing already recorded on the issue:** hop distance ignores edge length
— every edge is `1` no matter how far it spans, so hops are *aimbot* while
euclidean reach still demands positioning; hop-BFS coverage also explodes faster
than euclidean area. Target: a shit-tonne of INT makes you **dangerous to be
near**, not a one-click map wipe — though at extreme INT or with a topologically
perfect spell choice a one-shot may legitimately happen, as a rare tail.

D-18 already pinned the INT half (×2 cap, `bonus_hops` battlefield-found and
added *after* the multiplier). Don't reopen that here.

### 3. #279 — enemy CoreClass composability

Every enemy needs a mostly-similar batch of offensive/defensive/attribute/WIS
modifiers. Hand-authoring one `.tres` per enemy duplicates the shared 80%.
Floated: factory helpers producing `StatModifier`s (probably doesn't scale
either), a layered base+delta CoreClass, a template+override pair. Unsettled.

Worth taking **before** more enemy classes get hand-authored — each one added
first makes the refactor bigger. Does **not** block #275.

### 4. #280 — AI allocation behaviour

D-24 pinned the shared `AllocationPolicy` seam and "the AI spends all its SP".
Open here: the **scoring heuristic** (weighted growth — was mis-filed as a #275
follow-up, it's the same work as AI v2 scoring) · **AP-aware candidate horizon**
(N unspent AP = N hops worth checking) · **beelining vs. stretching thin** ·
whether tactical attack-allocation needs its own policy rather than an
`objective` arg · whether v2 restricts candidates to the **sensed** subgraph.

⚠ Tuning the AI now reshapes every spawn — same policy runs both.

### 5. #273 — `AttributeRadar` scale

D-18 settled the substance (INT in the thousands next to CON in the tens ⇒ three
orders of magnitude ⇒ **log is forced**). The surviving fork is pure UX: static
log · per-entity dynamic · log with a fixed floor/ceiling · a toggle. Blocks
nothing.

### 6. #180 — keystone placement v1 → v2

D-23 pinned what the basic keystone *is* (**+20 WIS, scattered broadly** — a
doubling of baseline income, √2 on the level ratio). It did **not** claim the
placement machinery is done. The v2 notion — keystones as pre-authored nodes or
constellations **stitched into** the generated graph — and the stitch-marker /
arc contract are still this issue's.

---

## Ready to dispatch right now

| # | What | Label |
|---|---|---|
| **#274** | INT → spell damage (D-20) | `swarmable`, ready |
| **#275** | enemy spawn levelling (D-19) — greedy BFS ball | `swarmable`, ready |
| **#276** | entity `health` scales with CON (D-21) | `swarmable` — **after #269** |
| #269 · #270 · #271 · #272 | earlier rounds | `swarmable` |
| #268 | balance harness | `swarmable` |

**On sequencing:** #269, #270, #271, #274, #276 all touch
`entity/default_entity_board.tres`, and **#276 additionally has a semantic
dependency on #269** — `health = base + CON` needs the `constitution` stat to
exist. #275 shares no files with that lane and can run alongside it. That is a **DAG fact for the swarm
orchestrator to wave**, not a reason to defer anything — see the reworked
`swarm` skill (§2, "Decompose, and own the DAG"). Drones commit in their
worktrees and stop; the orchestrator rebases and fast-forwards.

---

## Habits that have paid off five rounds running

**A. After pinning anything, compute what it implies at the bottom and the top
of the range** — level 1 and level 100, one node and two hundred. Every
structural correction so far (the aura sanctuary bubble, the armor dead zone,
the XP tempo gap, the level-cost-curve reframe, and round 5's flat-health-pool
finding) came from arithmetic on already-pinned values, not from discussion.
Every time the fix was structural, not a tuning nudge.

**B. When a fork flips, recompute every number derived under the old branch.**
Round 4 shipped a 4×-wrong cumulative-turns figure because the trace predated
the WIS-per-level flip. Grep your own draft for figures whose provenance is a
rejected branch before committing.

**C. Verify "unbuilt" / "broken" claims against `master` before speccing work.**
Round 5's hub item 5 (node-local `armor`) had been fixed in `be477f5` for some
time; only a stale rule block survived. A stale item closes with a doc
correction, not a new issue.

**D. Numeric values are never yours to invent.** Per D-13, thresholds and
balance ranges are human-supplied; #268 reports, it does not judge. Ship
placeholders and say they're placeholders.

---

## Live numbers worth having in hand

```
owned_nodes(L)   = starting_SP + 2(L−1) + floor(L/5)   ≈ 2.2L
                   L20 ≈ 42 · L50 ≈ 108 · L100 ≈ 218

level cost       = 5L                    (xp.tres, unchanged)
xp_per_turn      = WIS // 2              baseline WIS 20 → constant 10/turn
turns_per_level  = 10 × level / WIS      stagnant player: L/2

node_health      = linear in CON         L100 ≈ 110
entity health    = base + CON  (D-21)    L100 ≈ 119
nodes before death = health / dealloc_damage

spell_range      = clamp(INT/10, 0, 100)   # 0-based BONUS
reach multiplier = 1.0 + spell_range/100  → hard cap ×2
effective_hops   = round(base × mult) + bonus_hops      bonus adds AFTER

enemy level      = starting_nodes        (/1, levelled-but-landless)
level_ratio      = √(W_enemy / 20)       ⚠ spawn-time handicap, NOT an invariant
```
