# #248 — session handoff (after round 6)

**State as of commit `30ec71b`+.** Rounds 1–6 are done; `docs/design/mvp_decisions.md`
carries **D-1 … D-27** and is authoritative. **#248's own open list is exhausted** —
every remaining fork lives on a child issue with the fork written down.

Read this, then `gh issue view 248 --comments`.

> This file **points**; it does not hold. Every decision below also lives in its
> real home (a decision in `mvp_decisions.md`, a fork on its issue). See
> `.claude/skills/handoff/SKILL.md`.

---

## What round 6 closed

| # | Was | Now |
|---|---|---|
| **#277** | `core_healing` rate + gate | **D-25** — integer heal, placeholder 1/turn, **no gate, no ramp**. `swarmable` |
| **#279** | enemy CoreClass composability | **D-27** — `@export var inherits: CoreClass`, pure append. `swarmable` |
| **#273** | AttributeRadar scale | static log, fixed floor/ceiling, **bounds shared across entities**. `swarmable` |
| **#280** | AI allocation, one pile | split into **tiers 0/1/2**; tier 1 is **#286** (`swarmable`), tier 2 stays `design` |

Also from round 6: **D-26** (`core_health_scaling` knob) rides on **#276**, which
now also carries the requirement that **the CON delta grant be a named method**.

---

## The forks still open, in the order they're worth taking

### 1. #278 — the spell balance pass *(the big one)*

Wants its own session. Balances the whole spell surface together, per-`SpellDef`:
`mana_cost` × `min_degree` × reach (hops vs euclidean) × `seed_damage_fraction` ×
`damage_multiplier_per_hop` × `base_damage` × `int_scaling`.

**The framing already on the issue:** hop distance ignores edge length — every edge
is `1` no matter how far it spans, so hops are *aimbot* while euclidean reach still
demands positioning; hop-BFS coverage also explodes faster than euclidean area.
Target: a shit-tonne of INT makes you **dangerous to be near**, not a one-click map
wipe — though at extreme INT or with a topologically perfect spell choice a
one-shot may legitimately happen, as a rare tail.

D-18 pinned the INT half (×2 cap, `bonus_hops` battlefield-found, added *after* the
multiplier). Don't reopen it. **#283** (cast-time topology snapshot vs
apply-then-walk) is adjacent and worth settling in the same session.

### 2. #280 tier 2 — real AI strategy

AP-aware candidate horizon · beelining vs stretching thin · tactical allocation as
an attack maneuver (must stay behind the `objective` arg, or split the policy) ·
whether v2 restricts candidates to the **sensed** subgraph. Likely a literal
Strategy pattern. ⚠ Tuning the AI reshapes every spawn — same policy runs both.

### 3. #180 — keystone placement v1 → v2

D-23 pinned what the basic keystone *is* (+20 WIS, scattered broadly). It did **not**
claim the placement machinery is done. The v2 notion — keystones as pre-authored
nodes or constellations **stitched into** the generated graph — and the
stitch-marker / arc contract are still this issue's.

### 4. #287 — entity-scope-only stats *(new, round 6)*

`core_health_scaling` is meaningful only on the entity; node-local it is nil or
misleading, and nothing stops procgen rolling it onto a node. Fork: a scope field
on `StatDef` · separate registries · convention only.

### 5. #282 — node HP vs core HP, one honest damage track *(new)*

At the core node they are one damage track with a threshold in the middle (node HP
is shield, overflow hits core HP); at every other node, node HP means *territory
loss*, not damage. Reveal/double-loop and concentric rings are both **rejected**
(the rim already carries allocation/stake arcs). Live: SC2-style stacked ·
segmented single bar · something else.

---

## Ready to dispatch right now

| # | What |
|---|---|
| **#274** · **#275** · **#276** | INT→spell damage · enemy spawn levelling · health scales with CON |
| **#277** · **#279** · **#273** | round 6 output |
| **#286** | AI allocation v1 (after #275) |
| #268 · #269 · #270 · #271 · #272 | earlier rounds |

**Sequencing (a DAG fact for the orchestrator, not a reason to defer):**
#269, #270, #271, #274, #276, **#277** all touch `entity/default_entity_board.tres`.
**#276 additionally depends semantically on #269** (`health = base + CON` needs
`constitution` to exist). **#286 depends on #275.** #275 shares no files with that
lane and runs alongside it.

---

## Habits that have paid off six rounds running

**A. After pinning anything, compute what it implies at the bottom and the top of
the range** — level 1 and level 100, one node and two hundred. Every structural
correction so far came from arithmetic on already-pinned values, not from
discussion — including round 6's finding that `core_healing = 1` is *exactly* the
break-even point against a 1-node-per-turn chip.

**B. When a fork flips, recompute every number derived under the old branch.**
Round 4 shipped a 4×-wrong cumulative-turns figure because the trace predated the
WIS-per-level flip.

**C. Verify "unbuilt" / "broken" claims against `master` before speccing work.**
Round 5's node-local `armor` item had been fixed in `be477f5` for some time.

**D. Numeric values are never yours to invent.** Per D-13, thresholds and balance
ranges are human-supplied; #268 reports, it does not judge. Ship placeholders and
**say** they're placeholders.

**E. Check whether a knob is a *scaling base* before scaling off it.** Round 6
nearly expressed `core_healing` as a fraction of `dealloc_damage` — which is a
curse/debuff lever, not a base. The relationship survives only as a #268 assertion.

---

## Live numbers worth having in hand

```
owned_nodes(L)   = starting_SP + 2(L−1) + floor(L/5)   ≈ 2.2L
                   L20 ≈ 42 · L50 ≈ 108 · L100 ≈ 218

level cost       = 5L                    (xp.tres, unchanged)
xp_per_turn      = WIS // 2              baseline WIS 20 → constant 10/turn
turns_per_level  = 10 × level / WIS      stagnant player: L/2

node_health      = linear in CON         L100 ≈ 110
entity health    = 10 + core_health_scaling × CON   (D-21/D-26)  L100 ≈ 119
dealloc_damage   = 1.0 base              ⚠ curse/debuff knob, NOT a scaling base
core_healing     = 1/turn placeholder    ⚠ break-even vs a 1-node/turn chip
nodes before death = health / dealloc_damage

spell_range      = clamp(INT/10, 0, 100)   # 0-based BONUS
reach multiplier = 1.0 + spell_range/100  → hard cap ×2
effective_hops   = round(base × mult) + bonus_hops      bonus adds AFTER

enemy level      = starting_nodes        (/1, levelled-but-landless)
level_ratio      = √(W_enemy / 20)       ⚠ spawn-time handicap, NOT an invariant
```

---

**Delete this file** once #278 and #180 are settled and #248 itself closes.
