# Testing tiers — which assert goes where

**The unit is the formula; the clock is a consumer.** Owner's call (Koaieus,
2026-09-20, #976, verbatim):

> Tbf such unit tests like "do we dwell blabla+.6s at lv3" should mainly test
> the unit: the formula producing the number. Testing whether a timeout works
> is ehh.. might allow some e2e testing but unit?

Three tiers, decided on #360 (owner, 2026-09-20). Membership is by **what a
test drives, never by how fast it runs**:

| Tier | Runs | Drives | Budget |
|---|---|---|---|
| `test/unit/` | `mise run test:unit` | hand-built objects; a pure method, a resource, a controller stepped by hand | fast, no wall-clock waits |
| `test/integration/` | `mise run test:dir -- res://test/integration/` | a composed scene (`game_root.tscn`, `level.tscn`, a sandbox, `meta_root.tscn`) **or the real clock** — the one designated wall-clock test per feature | **15 s per script**; full suite **≤ 90 s wall** |
| `mp:e2e` | `mise run mp:e2e` | two processes over a real socket, the shipped lobby | ~30 s, the gate for `network/`, `session/`, `command/` |

`mise run test` runs the first two, sharded. The mechanics of GUT (the
silent-skip trap, `wait_until`, `free()` vs `queue_free()`) stay in
`.claude/rules/testing.md`; *whether* a change earns a test is
`docs/domain/red-green.md` §1. This doc is the **discipline**: which tier, and
what the assert is.

## 1. The decision list

Ask in this order; the first "yes" routes the assert.

1. **Does it pin an authored `.tres` number** (a `min_dwell` of 2.0, a
   `vision_range` of 3, a spell's base damage)? → **nowhere.** Owner tunes,
   agents test: assert the formula on a hand-built object with the number as
   *input*, never the shipped value as *expected*.
2. **Is a second process or a socket involved** (a peer must reproduce or
   receive the result, a lobby handshake, `Wire`)? → **`mp:e2e`.**
3. **Does it drive a composed scene** — instantiate `game_root.tscn`,
   `level.tscn`, a sandbox, `meta_root.tscn`, `route_probe_game_root.tscn`,
   and assert something *about the wiring or the emergent end state* (a
   NodePath resolved, a signal connected after compose, an XP total after a
   scripted turn)? → **`test/integration/`.**
4. **Does the behaviour *exist* only under time** — a queue is held until it
   drains, a rebind cuts a flourish that is *live*, a hit lands *after* the
   form beat? Two sub-questions:
   - Can the controller be **stepped by hand** (an `advance(delta)` /
     `_process(delta)` you call with a delta of your choosing, or an instant
     clock such as `BeatClock.instant_clock()`)? → **`test/unit/`**, stepping
     it (§3). If it *cannot* be stepped, you have found a seam — file it or
     open it; do not sleep around it.
   - Is this the **one** "the controller really consumes the schedule on the
     real clock" check for the feature? → **`test/integration/`**, with a
     generous seconds budget. One per feature; the second one is a unit test
     wearing a stopwatch.
5. **Everything else** — a return value, a resolved stat, a schedule's numbers,
   a command applied to a hand-built graph, a signal emitted → **`test/unit/`.**

A file mixes tiers only by accident. If one function in a unit-tier script
needs the real clock, that function moves to `test/integration/`; the rest
stay.

## 2. Schedule as output, clock as consumer

A controller that paces something has two halves: the computation of **how
long / what to show at step k**, and the thing that *consumes* those numbers
on a clock. Extract the first into a pure method or a small resource
(`RefCounted`, no tree) and assert the numbers it returns:

```gdscript
# unit tier — instant, deterministic, a table
var seq := PoolLevelSequencer.new(100.0)
seq.observe(150.0, 200.0)   # crossed one level
seq.observe(250.0, 400.0)   # crossed another
assert_eq(seq.pending().map(func(s): return s.fill_to), [100.0, 200.0])
```

`ui/gauges/pool_level_sequencer.gd` is the house example: the XP pool's
synchronous multi-level cascade becomes an ordered queue of one-level
`Segment`s, tested in `test/unit/ui/test_pool_level_sequencer.gd` with no
clock at all. The `PoolGauge` that plays those segments back on tweens is the
consumer — it gets **one** real-clock test in `test/integration/`, budgeted in
seconds, not seven tests that each sleep between ticks.

Most wall-clock tests collapse into this shape. "For N levels at tempo T the
dwell sequence is D₁…Dₙ and the SP narrated at step k is Sₖ" is a function; a
test that measures D on a stopwatch is testing the OS scheduler.

## 3. Step time by hand

Where sequencing under time *is* the behaviour, the unit test advances the
controller itself instead of awaiting seconds:

```gdscript
flourish.stamp(3, 120, 1)
flourish.release()
flourish.advance(min_dwell - 0.01)   # a chosen delta
assert_true(flourish.is_open(), "still dwelling one tick before min_dwell")
flourish.advance(0.02)
assert_false(flourish.is_open())
```

This requires the controller to **advance on delta** — `_process(delta)` or a
named `advance(delta)` entry — never on `get_tree().create_timer(...)` or
`await timer.timeout`, which only the real clock can move. The same
requirement `docs/domain/presentation-clock.md` already puts on the mutation
loop: the world moves on a fixed logical clock the loop owns, never on
animation completion; a `BeatClock` is exactly a clock you can swap for an
instant one (`BattleSystem.instant_mutation = true`), which is why a
logical-clock cycle test is a *unit* test of what it drives, not a wall-clock
test of when.

Not every controller is there yet. `LevelUpFlourish.release()` still arms a
`create_timer(min_dwell)` and `_play_exit` awaits two more — that seam is what
#981 opens; until it lands, the flourish's dwell tests are integration-tier by
necessity, not by design. `MeleePreview` / `BattleSystem` are already
steppable through the instant clock (#982 moves those tests onto it).

**A unit that cannot be stepped by hand has found a seam, not a fixture.**
That is the same rule `.claude/rules/testing.md` states for cross-unit
writes ("a test whose setup writes ANOTHER unit's internals has found a seam,
not a fixture") — the sleep is the reach-in's temporal twin: both let the test
*get somewhere* the class under test does not expose a way to get.

## 4. Seconds, never ticks

The GUT pre-run hook (`test/gut_hooks/pause_leak_pre_run_hook.gd`,
`HEADLESS_FRAME_SLEEP_USEC := 1000`) drops headless godot's idle frame sleep
from ~12.7 ms to ~1.5 ms per process frame. Frames are cheap **and their
period is a knob**; timers, tweens and physics ticks stay wall-clocked. So a
budget counted in frames is a budget in an unknown unit. The anti-pattern, from
#976 — 13 tests in 6 scripts broke on the pacing change, every one shaped
like this:

```gdscript
while _bs.is_launching and ticks < 900:      # 15 s on one box, 1.4 s on another
    await get_tree().process_frame
    ticks += 1
```

One of them argued for it in a comment — *"Ticks, not seconds, because the
headless frame rate varies by an order of magnitude between machines"* — which
is exactly backwards: the frame rate varying is *why* a tick budget is unsafe.

Wait on the **condition** with a **seconds** cap:

```gdscript
await wait_until(func(): return not _bs.is_launching, 15.0)
```

or a `Time.get_ticks_msec()` deadline when you need the elapsed time back
(`test/unit/attack/test_melee_staging.gd::_await_launch_settle`). That is the
*repair*; it is not yet purity — a repaired wait still belongs to a test that
is waiting for the real clock, and §1 decides whether that test is the
feature's one integration keeper or a unit test that wants §2/§3 instead.

## 5. Worked examples — the four seed scripts of #976

Verified at `cb99152`. "Keeper" is the single real-clock test the feature
retains in `test/integration/`.

| Script | What the file does today | What the unit actually promises | Where each assert goes |
|---|---|---|---|
| `test/unit/ui/test_level_up_flourish.gd` | `_settle()` sleeps 60 × (frame + 10 ms) then `min_dwell + 0.2 s`; `_time_cascade` stopwatches a 2-level vs 4-level cascade with `Time.get_ticks_msec()` | a **schedule**: for N levels and a tempo, the sequence of dwell durations and the SP total narrated at each step | see the per-function table below |
| `test/unit/scenes/test_act_gate_across_turns.gd` | `wait_physics_frames(1)` / `(3)` to hand the turn around and let `player_can_act_changed` fire | the gate's open/closed state as a **function of the AP pool and the turn cursor** | `test_gate_reopens_after_a_turn_that_spent_all_ap` / `_spent_no_ap` → unit: build `PlayerInputController` + a hand-built `TurnManager`, end the turn synchronously, assert `can_player_act()`; `test_pic_listens_to_the_live_ap_pool_not_a_discarded_board` is a wiring fact → the keeper, integration (#983) |
| `test/unit/attack/test_melee_staging.gd` | `Time.get_ticks_usec()` stopwatch on "first hit lands after the form beat"; `_await_launch_settle` pumps frames with a 15 s cap | the staged beat **order and durations** the tempo resolves to (`OutcomeSchedule`) | order/duration asserts → unit on `BeatClock.instant_clock()` (`BattleSystem.instant_mutation = true`); *one* "the real clock serves the form beat before the first hit" → integration (#982) |
| `test/unit/ui/test_xp_track_level_sequence.gd` | `wait_seconds(0.01)` between ticks to let the track animate; `wait_seconds(0.03)` to land mid-replay | **which segment fills at which XP value** — a table | already extracted: `PoolLevelSequencer` + `test_pool_level_sequencer.gd` is the unit half; the gauge-consumer tests collapse to reads of `pending()`/`peek()` on the sequencer the gauge holds, plus one keeper (#981) |

### `test_level_up_flourish.gd`, per function

The class under test is `LevelUpFlourish` (`ui/hud/xp_track/level_up_flourish.gd`):
`stamp(level, sp_total, stack)`, `release()`, `cut()`, `is_open()`, signal
`closed`. Until #981 adds the delta seam, "unit" below means "unit once the
controller advances on delta; integration by necessity today".

| Function | Sleep it uses | Tier | The pure assert that replaces the sleep |
|---|---|---|---|
| `test_a_four_level_cascade_counts_up_on_one_flourish` | `_settle()` | unit | after four `stamp()` calls (or one 4-level `replenish` on a hand-built board), `_stamps == ["L E V E L   U P", "×2", "×3", "×4"]` — the stamp sequence is synchronous; no dwell needed to read it |
| `test_the_sp_total_accumulates_the_levels_actually_narrated` | `_settle()` | unit | the SP total passed to the k-th `stamp()` equals the running sum of the k levels — a table over the stamp arguments |
| `test_the_flourish_is_held_until_the_queue_drains` | `wait_seconds(0.12)` | unit (step by hand) | `stamp()` twice, `release()`, `advance(min_dwell + ε)`: still `is_open()` while the sequencer has pending segments; `advance` past the last drain → closed |
| `test_a_level_landing_during_the_dwell_keeps_counting` | `process_frame` poll on `_stamps.size()` | unit (step by hand) | `stamp()`, `release()`, `advance(min_dwell / 2)`, `stamp()` again → `is_open()` and the count reads ×2; the release timer was cancelled (`_cancel_release` is the seam, `is_open()` the observable) |
| `test_a_single_level_still_dwells` | `wait_seconds(0.25)` against the shipped `min_dwell` | unit (step by hand) | `stamp()` once, `release()`, `advance(min_dwell - ε)` → open; `advance(2ε)` → closed. `min_dwell` is an **input** set on the hand-built flourish, never the `.tres`/`@export` default (§1 q1) |
| `test_rebinding_cuts_a_live_flourish` | `wait_seconds(0.12)` | unit (step by hand) | `stamp()`, `advance(small)`, `cut()` → `not is_open()`, `closed` emitted once, no exit tween scheduled |
| `test_the_per_level_pace_does_not_depend_on_how_many_levels_land` | `_time_cascade` stopwatch, 12 s cap | **split**: unit + the keeper | unit: the schedule for N=2 and N=4 returns the same per-level dwell (`schedule(n, tempo)[k]` constant in n) — instant. Keeper, `test/integration/`: one cascade on the real clock, `wait_until(closed, 15.0)`, asserting only that it closed and narrated N levels — never the pace |

## 6. Smell list — for a sweep

Each of these is a test asserting the clock or the content instead of the
unit. Rank the suite with `mise run test:timings`; the smells cluster at the
top.

- **Numeric frame loops** — `for _i in <N>: await get_tree().process_frame`,
  `wait_frames(N)` used as a *budget* (a single `wait_frames(1)` to let a
  deferred call run is fine).
- **`wait_seconds` / `create_timer` to let a controller *get somewhere***
  rather than to test the timer itself → §2 or §3.
- **`Time.get_ticks_*` stopwatches asserting pacing** ("the second beat is
  ≥ 0.4 s after the first") → the schedule's numbers, §2.
- **Authored-value pins** — `assert_eq(x, 2.0)` where 2.0 is a `.tres` or an
  `@export` default → nowhere; make it an input.
- **Sleep-to-settle helpers** (`_settle()`, `_await_*_settle`) called by every
  test in a file: the file is integration-tier by habit, and the unit under it
  is missing an `advance(delta)` or a schedule method.
- **A handler called by name** (`x._on_turn_started(...)`) instead of the
  signal that connects to it → §7.
- **An arrange-step write into another object's `_field`** → §8.

## 7. The seam is the signal, so the test fires the signal

Owner's addendum (Koaieus, 2026-09-20, #977). A test that calls
`x._on_something(...)` directly has bypassed the seam it should be exercising:
the handler is tested, the `connect` is not. The 2026-09-20 count found the
suite calling `_on_node_left_clicked` ×115 and `_on_turn_started` ×26 by name,
and asserting the `connect` behind them nowhere. **Emit the signal, or drive
the real trigger** (`turn_manager.end_turn()`, a `push_input` click in a
`SubViewport`), and let the connection carry it. The wiring half lives in the
integration tier's smoke (#360: `emitter.signal.is_connected(listener._handler)`
for a named list of pairs); the behaviour half fires the signal in the unit
tier.

The boundary, so this does not become "everything is a signal": a signal is
*the* seam when **several observers of different lifetimes react to one fact**
(`Events.entity_dying` — loot, allocation cleanup, HUD, VFX). It is the wrong
tool for **a single consumer with an ordering or return dependency** — there a
signal hides a call with a contract, and the test that emits it cannot assert
the contract. That is the act-gate bug (#957, `66743f5`): every tab and
Launch dimmed off one broadcast `player_can_act_changed` that folded "any AP"
into flow, when each consumer needed to *ask* two questions with different
answers — `can_player_act()` and `can_afford(plan)`.

## 8. A fact has one owner; the underscore is not an authority model

Owner's addendum (Koaieus, 2026-09-20, #977). Three shapes of cross-unit
write, in order of legitimacy:

1. **The composition root at wiring time** — `GameRoot._ready` /
   `HudRoot.compose` setting `@export` deps and connecting signals.
2. **A named entry point the owner validates** — `begin_mass_action`,
   `force_allocate`, `MeleePreview.launch(plan)`.
3. **Everything else is a reach-in**, whether or not the name has an
   underscore.

In a test: any arrange-step write into an object *other than the class under
test*, outside shapes 1 and 2, is the cross-unit gotcha from
`.claude/rules/testing.md` — **make the owner expose the fact or the entry**,
and test against that. Worked example: `test_melee_replay_resolve.gd::
test_the_pump_keeps_stepping_while_live_swing_is_true` writes
`_preview._live_swing = true` to arrange "a swing is live". That is shape 3:
`_live_swing` is set by `MeleePreview.launch()` (line 266) as a consequence of
a committed swing, and the test has forged the consequence without the cause.
The owner should expose the *cause* — drive `launch(plan)` with an instant
schedule — or, if the fact must be arrangeable on its own, a named entry
(`begin_live_swing()` / a `swing_live` marker the preview validates) that
production code also goes through, so the test and the mirror share one door.

#984 is the production-side design pass (guards on multi-writer facts, the
`Events` bus boundary); this doc states the rule and does not pre-empt its
forks.

## See also

- `.claude/rules/testing-tiers.md` — the one-line breadcrule.
- `.claude/rules/testing.md` — GUT mechanics: the wait-budget paragraph, the
  silent-skip trap, the cross-unit-write gotcha, the wiring pattern.
- `docs/domain/red-green.md` — whether a change earns a test, and RED first.
- `docs/domain/presentation-clock.md` — the fixed logical clock the mutation
  loop owns; why a controller advances on delta.
- #976 (hub), #360 (the tier), #978 (the sweep), #981/#982/#983 (the seams
  the seed scripts need), #984 (ownership, production side).
