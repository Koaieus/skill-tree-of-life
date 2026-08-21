# Handoff: what does a StatBoard actually need to serialize?

**Opened 2026-08-21.** An open design question, not a settled decision — this
file exists so a fresh session starts from the investigation instead of redoing
it. Delete it once the forks below are settled into their durable homes (#23,
#506, and whatever new issue comes out of it).

Triggered by `StatBoard.clone_live()` landing in `7675195` (#498 step 2): a bare
`duplicate(true)` silently loses a live board's state, and the fix raised the
bigger question of *what a board's durable state even is*.

---

## The question

`Stat.bins` and `StatBoard._extra_stats` are plain (non-exported) vars, so they
do not survive `duplicate()` and would not survive a `.tres` round-trip either.
The obvious fix is `@export_storage` — hide from the inspector, keep on disk.

Owner's two instincts, both worth taking seriously:

1. **Maybe bins should not be saved at all** — they are *derived* from
   `_modifiers[]`, so persisting them stores a cache next to its source.
2. **`_extra_stats` sounds like something we would not want in this codebase**
   (uncertain, wanted checking).

---

## Finding 1: bins are derived, and the derivation function already exists

**This is settled by the code and needs no further investigation.**

`Stat._resync_bins_if_trivial()` (`stats_system/stat.gd:212-231`) is already a
from-scratch rebuild of the bins from `_modifiers`. It short-circuits to the
0-or-1-modifier case purely as free anti-drift ("at 0 or 1 modifiers the bins
have a known exact form"), not because the general case is impossible.

Every bin is a pure fold over `_modifiers`:

| Bin | Derivation | Reference |
|---|---|---|
| `base_add` / `increase_sum` / `bonus_add` | Σ `m.get_effective_value(_board)` per op class | `stat.gd:201-210` (`_apply_bin_delta`) |
| `multipliers` | the MULTIPLY modifiers, kept as a list on purpose | `stat.gd:156-157` |
| `winning_set` | `_find_winning_set()` — a pure fold | `stat.gd:236-242` |
| `_last_contrib` | explicitly a cache of "what each modifier last contributed" | `stat.gd:70` docstring |

So the incremental delta maintenance in `add_modifier`/`remove_modifier` is an
**optimisation over a rebuild**, and the rebuild is ~15 lines that already
exist in miniature.

**The one wrinkle:** the derivation is not *pure* — it reads
`m.get_effective_value(_board)`, so a formula modifier needs its board coherent
before it can be rebuilt. Chicken-and-egg on load if stat A's formula reads
stat B.

**The saving grace:** `StatBoard.find_cycle` / `cycle_from` already guarantee
the formula dependency graph is a **DAG** (#322, and
`test_stat_dependency_graph.gd` pins it for shipped content). A topological
rebuild order therefore always exists. `StatBoard.end_batch` already sorts a
flush by formula dependency depth (`.claude/rules/stats-system.md`, "the flush
is ordered by formula dependency depth, and that ordering is load-bearing") —
**that ordering logic is probably reusable as the load order.** Look there
first rather than writing a second topological sort.

### What that implies for the durable state

If bins are derived, a board's authoritative state is:

- `base_value` per stat — already `@export`ed ✅
- `PoolStat.current` (and `SkillPointStat`'s `wounded`/`staked`,
  `SurplusPoolStat`'s `surplus`) — **check each; `current` is ephemeral game
  state, not modifier state**
- **`Stat._modifiers`** (`stat.gd:51`) — non-exported, and this is the real gap
- which stats exist at all (see `_extra_stats`, below)

`StatModifier` **is** a `Resource`, so `@export_storage var _modifiers` is
mechanically possible — unlike bins (see the next section). That single change
would give save/load, `duplicate()`, and the combat shadow the same thing at
once.

### ⚠️ The trap in doing that naively

`Entity._ready` does `stat_board = stat_board.duplicate(true)`, and the board's
`intrinsic_modifiers` are **inline** sub-resources, so they are already
deep-copied there (`.claude/rules/stats-system.md`, "Keep the formula in its own
`.tres`"). After `apply_intrinsics()`, `Stat._modifiers` holds *references to
those same modifier objects*.

Make `_modifiers` storage-flagged and `duplicate(true)` copies them a **second
time** — you get two distinct copies of what should be one object, with
`board.intrinsic_modifiers[i]` and `stat._modifiers[j]` silently diverging.
Anything that revokes by identity (`EffectContext`'s grant ledger,
`remove_modifier`) then misses.

This is the thing to design around, and it is why "just add the annotation" is
not the whole answer.

## Finding 2: `@export_storage` cannot apply to `bins` at all

`ModifierBins extends RefCounted`, **not `Resource`**
(`stats_system/modifier_bins.gd:2`). A bare `RefCounted` is not serializable;
`@export` and `@export_storage` both refuse it. Promoting it to `Resource` is a
prerequisite for even having the conversation.

Three reasons not to want that promotion, beyond Finding 1:

1. **`ModifierBins.board` is a back-reference to the owning `StatBoard`**
   (`modifier_bins.gd:29-33`). Serializing it makes a reference cycle in the
   `.tres`: board → stat → bins → board. It would need excluding, so you would
   be hand-picking storage flags per field regardless.
2. **Scale.** `node_board` is `duplicate(true)`d **per node**, 500–2500 per
   level (`.claude/rules/skill-node-scale.md`). Every `Stat` would gain a
   serialized sub-resource.
3. **It is the derived-value-into-`@export` pitfall by name.**
   `.claude/rules/gdscript-pitfalls.md`: *"Never write a DERIVED value back into
   an `@export` — the editor serializes the computed value, and the next load
   computes again from there."* A template `.tres` that round-trips through the
   editor with non-empty bins loads pre-filled, and `apply_intrinsics()` then
   adds on top. Double-counted intrinsics, silently.

**So: bins should almost certainly NOT be persisted.** Owner's instinct 1 is
correct and the code proves it. The remaining question is only whether to
rebuild them on load or ship a cached snapshot — see the forks.

## Finding 3: what `_extra_stats` actually is

Owner was unsure. The honest answer: it is **a sparse-storage optimisation for
node boards, and nothing else.**

- `EntityStatBoard` declares all ~40 stats as typed `@export` fields and
  **refuses to mint** (`entity_stat_board.gd:148-153` overrides `_mint_stat` to
  warn and return null). So `_extra_stats` is **always empty on entity boards**.
- `NodeStatBoard` declares exactly **two** typed fields — `stake_level` and
  `addon_slots` (`node_stat_board.gd:35-53`), the node-*owned* stats — and mints
  every *borrowed* stat on demand.
- What actually lands there at runtime: `node_health` (special-cased into a
  `PoolStat` off the `node_combat_health` def), plus whatever node-local
  modifiers target — `armor`, `min_damage_taken`, `node_healing`,
  `blade_damage`, `range`, `vision_range` are the ones addons use today. A node
  rarely holds more than 4–8.
- **Nothing depends on the dynamic-vs-typed distinction behaviourally.**
  `get_stat`, `collect_formula_edges` and `get_stat_ids` treat both identically.
  `get_dynamic_stat_ids()` is the only reader of the distinction and no
  production code path uses it (the node stats panel calls `get_stat_ids()`).

So eliminating it is *possible* — declare ~38 null-initialised fields on
`NodeStatBoard` — and would be behaviourally invisible.

**Do not do that on the scout's say-so.** It reported the memory cost as
"negligible", which is a per-instance-reference estimate and is not the cost
that matters. `docs/domain/stat-board-classes.md` records a **+153 ms per 2500
nodes** measurement against the *rejected* sub-board-array alternative — the
same family of change. `node_board` is deep-duplicated per node, so field count
drives per-node duplication work, not just memory. **Read that doc and measure
(`test/perf/bench_allocation_cost.gd`) before touching NodeStatBoard's field
count.**

For serialization specifically, `_extra_stats` matters only because *which
stats exist* is itself state a load must reconstruct. If `_modifiers` round-trip
and minting is driven by modifier targets, minting may reconstruct it for free.

## Finding 4: multiplayer does NOT need this — correcting the premise

Owner recalled stat-board serialization being needed "to sync most of the world
to each client". **Half right, and the half that is wrong changes the priority.**

- Every client *does* get full **world** state — nodes, ownership, HP
  (`docs/domain/multiplayer-sync-model.md:120-126`).
- But stat boards were **deliberately carved out**.
  `docs/design/info_gating.md:86-100`, settled 2026-08-18 in #473: *"No stat
  board is ever synced or revealed wholesale."* Node modifiers are public, so a
  viewer **reconstructs** an opponent's build from scouted territory — "+30 STR
  (estimate)".
- Attacks ship a **serialized `AttackOutcome`**, not board state
  (`multiplayer-sync-model.md:163`): *"Clients apply the outcome and replay VFX;
  they never re-simulate."*

What keeps it on the table:

- `multiplayer-sync-model.md:138-143` — *"Deferred, not rejected: fog-filtered
  state deltas… deferred because it needs the same `StatBoard` wire format that
  state replication needs."*
- The same doc's rejection of full state replication names the blocker in the
  owner's own terms: *"No `StatBoard` wire format exists; `Stat._modifiers` is
  memory-only"* — and notes the upside that *"the serializer **is** save/load
  (#23)."*

**Conclusion: save/load (#23) is the only live driver.** Multiplayer is a
deferred second customer, so design the format for save/load and let versus
inherit it — not the other way round.

## Finding 5: #23 already anticipated this, in the owner's own words

`gh issue view 23 --comments`, comment of **2026-06-25**: *"likely need to check
if we need to add `@export_storage` to some non-exported variables; ones that
need to be saved/serialized."* Same instinct, two months earlier.

#23's acceptance already commits to persisting *"graph topology, node ownership
+ HP + addons, **entity stats** + position + core node, turn-manager state,
vision state"* — but "entity stats" is exactly the unresolved word.

**#23 also carries an unsettled scope fork** (comment 2026-07-19): *"What
exactly to save/load? Levels only, or levels + metagame?"* It sits in
`Needs design`. That fork should probably be settled in the same session as
this one — the answer changes whether a save is a level snapshot or a run.

---

## The forks to settle

1. **Persist `_modifiers` and rebuild bins on load, or persist bins as a
   snapshot?** Finding 1 says rebuild is possible and the DAG makes ordering
   tractable. Rebuild is the principled answer; the cost is load-time work
   proportional to modifier count, and the `Entity._ready` double-duplication
   trap above must be designed around either way.
2. **Is a modifier persisted by value, or by seed-replay?** Procgen mints
   modifiers at runtime from `StatPool`s. A seeded run (#457, `Needs design`,
   *"the determinism contract"*) could regenerate them instead of serializing
   them — which would shrink a save enormously and is the same machinery versus
   wants. **#457 is likely a prerequisite decision, not a parallel one.**
3. **Does `_extra_stats` stay?** Behaviourally invisible either way (Finding 3).
   Do not decide it on aesthetics without the `stat-board-classes.md`
   measurement — and note it may be moot if minting reconstructs itself from
   round-tripped modifiers.
4. **Does `PoolStat.current` (and the SP `wounded`/`staked`, surplus bins) count
   as durable state or ephemeral?** Not investigated. Save/load says yes for HP;
   surplus is explicitly per-turn and overwritten (`.claude/rules/stats-system.md`).

## Durable homes, once settled

- **#23** — save/load. Owns the format decision and the levels-vs-metagame fork.
- **#506** — *"A cloned StatBoard computes but does not react"*. Already filed,
  `Ready`, child of #498. **Its fix is a strict subset of this question:** if
  `clone_live()` carried `_modifiers` and rebuilt/rebound instead of copying
  bins, #506 closes. Do not solve #506 in a way that contradicts whatever gets
  decided here.
- **#457** — seed determinism. Fork 2 depends on it.
- **`.claude/rules/stats-system.md`** — already carries the `clone_live` gotcha
  under Gotchas; update it with whatever is decided.
- **`docs/domain/stat-board-classes.md`** — the +153ms measurement and the
  rejected alternative. Read before any NodeStatBoard field-count change.

## Do not re-derive

Everything in Findings 1–5 is checked against the code as of `56ca48f`. In
particular: bins-are-derived is proven, `ModifierBins` is `RefCounted` (so the
`@export_storage` idea cannot apply to it), `_extra_stats` is node-board-only,
and multiplayer explicitly does not want board sync. Start from the forks.
