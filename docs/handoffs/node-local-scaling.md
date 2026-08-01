# Handoff — node-local modifier scaling (#332 cluster)

Written against `7f54c0b`. **This file points; it holds nothing.** Every decision
below lives on its issue — if this file disappeared, nothing would be lost except
the ordering.

## State

#322 landed and is reviewed (`9550569`). `StatBoard.cycle_from(m)` / `would_cycle(m)`
exist, are candidate-rooted, and have **no production caller yet** — #323 is the
first one.

Design session opened four coupled threads. None are `swarmable`; all have open
forks the user has not settled.

## The forks, in the order worth taking them

1. **#332 — slots vs. multipliers.** *Take this first; it decides whether the
   other two are on the critical path at all.* Does `allocation_level` scale a
   node's local modifiers (multipliers), or buy addon slots (slots)?
   - Recommendation on the issue is **slots**: the rim already renders an M-of-N
     dial (`rim_bonuses.gd`), `skill_points.stake(1)`/`extract(1)` already price
     and reverse it, and it avoids an exponential-armor collision with D-10.
   - **The coupling that matters: if slots wins, #333 stops being a blocker and
     the formula/binding work in #332 is never needed.** They are alternatives,
     not complements — doing both makes investment pay twice on one axis.

2. **#333 — `StatFormula` can only read a pool's cap, never `current`.**
   Only on the critical path if #332 lands on multipliers. Real gap regardless
   (blocks mana-fraction and low-health scaling). Open fork is naming; the
   preferred option and the reasoning that eliminates the other three are on the
   issue.

3. **#287 — stat scope (entity-only / node-only).** Independent of the above and
   worth settling on its own. Cross-posted: a `NodeStatBoard` subclass is a
   stronger version of its second fork than the issue assumed, and
   `StatBoard._ensure_stat` is a leak that *either* fork has to close.

4. **#323 — loot lootability re-cut.** Adjacent, not blocked by the above. The
   `would_cycle` draw filter is specified in a comment; the user settled the
   pick-N question themselves (batched single picks, so joint cyclicity can't
   be constructed).

## Facts a fresh session would otherwise re-derive

- **Node-local formula modifiers are inert, not merely ungated.**
  `SkillNode.add_local_modifier` never calls `bind()`, so a formula there is
  silently ignored. This is why the cycle gate and the binding are **one
  decision, not two** — see `.claude/rules/stats-system.md`.
- `allocation_level` / `stake_level` are plain `SkillNode` fields, not stats.
  Promotion is a live proposal (#332), not the status quo.

## Delete this file when

#332 settles slots-vs-multipliers. At that point the dispatch order collapses to
"do the winning branch" and the issues carry everything on their own.
