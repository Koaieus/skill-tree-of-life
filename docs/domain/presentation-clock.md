# Presentation clock — engineering reference

Code: `attack/outcome/beat_clock.gd`, `attack/outcome/outcome_applier.gd`,
`systems/battle_system.gd`. See `presentation/README.md` for the parked view-store
design this replaced.

For the ordering rules within a single attack (`arrival_time`, the
resolve/land clocks, the "candidate set frozen, arithmetic live" contract),
see `docs/domain/attack-timeline.md`'s "The clocks" and "Ordering and
`arrival_time`" sections. This doc is about the clock those landings are
paced on, not about what happens at a landing.

## The split — there isn't one

The world mutates on a fixed logical clock owned by the mutation loop:
`OutcomeApplier.apply`, awaiting a `BeatClock` between landings so each hit
lands at its own `arrival_time`. What is drawn is the model, at every beat.
There is no view state, no `shown_*` field, and no second source of truth —
every painter reads live world state, full stop. See `beat_clock.gd`'s class
docstring for the clock's own statement of this; it is the
long-form version of everything in this section.

The clock carries one beat that is **not** a mutation: `BattleSystem`'s
`release_beat`, waited out at the end of `_apply_outcome` before
`is_launching` clears for a coordinator mode (ranged/magic). It is the pause
between the world going final and the player being able to act again, and it
rides this clock rather than a timer of its own precisely so it inherits the
clock's two properties — instant under `instant_mutation`, and cut short by
`drain()` on teardown. Melee doesn't take it: it releases on the visible
swing, because its plan (and the temp-upgrade addons mounted on it) must stay
live until the blade is done.

## Why the await is not frame-ordered mutation

`OutcomeApplier.apply` awaits `BeatClock.advance_to` between landings, which
looks like ordering mutation by animation completion. It isn't:

- The interval is **fixed and logical** — authored `arrival_time`, not wall
  time to an animation's completion.
- The game is turn-based and `BattleSystem.is_launching` guards reentrancy —
  nothing else can act inside the window.
- Nothing times *itself* off the wait. VFX runs unawaited, alongside the
  mutation loop, timing itself off the same `arrival_time` values (see the
  `_seed_source` / VFX timing comments in `battle_system.gd`) rather than off the
  loop's progress.

So only *order* is observable inside the window, and order is code-order. The
rule is **never frame-ordered mutation** — not "never mutate inside an await."

## The intermediate state is valid, not torn

Mid-volley, some hits have landed and some haven't: HP is partially
depleted, some cascades have run, some modifiers are gone. That reads like a
bug — "the world is half-applied" — and it isn't one. It's the exact
sequence of states the code already walked through at t=0 under the old
model, one beat at a time instead of all at once. Nothing reads a field that
lies about where the world is; every reader sees exactly as much of the
attack as has actually landed.

## The one real risk: lost mutations

If the applying loop is interrupted mid-window — a scene change, most
realistically — the hits still in flight never land: a world that is valid
but permanently wrong, not a crash. `BeatClock.drain()` (synchronous,
idempotent) is the whole mitigation: it releases any
parked wait and makes every remaining `advance_to` a no-op, so the rest of
the outcome lands immediately. `BattleSystem.drain_pending_mutations()`
holds the in-flight clock and is called from `GameRoot._exit_tree` — the drain
runs synchronously inside teardown, while the nodes it mutates are still alive.

The same flag doubles as test mode: `BattleSystem.instant_mutation` builds
an instant clock up front (`BeatClock.instant_clock()`) rather than draining
one mid-flight, which is why tests that read world state on the line after
`launch_attack` kept passing unmodified. It is an **explicit flag**,
deliberately *not* inferred from whether `attack_vfx` / `melee_preview` are
mounted — #474's acceptance is precisely that VFX presence must not change
the applied world, so making the clock depend on VFX being wired would be
exactly the coupling that must not exist.

The interrupt surface is small by construction: pause is authority-gated and
nobody holds that authority in multiplayer yet, and a scene change needs
multiplayer coordination regardless — so `_exit_tree` is the one place that
actually needs the drain today.

## Resolve was never pure, and that is load-bearing

Read this before "fixing" the applier to make hits self-contained — the
purity it would be restoring never existed.

`AttackOutcome` is a *plan* of hits, not a result. `DamageInstance` carries
raw, unmitigated damage; `Mitigation.apply` runs inside `NodeCombat.take_damage`
(`combat/node_combat.gd`) at land time and can reclassify a hit from DAMAGE to
HEAL there; `HitInstance.effective_amount` is `0.0` until a hit is actually
applied. `AllocationSystem.force_deallocate` revokes a dead node's granted
modifiers synchronously (via `EntityCombat.revoke_node`).
mitigates against a board an earlier hit's cascade stripped — **before**
design B, and after it. B changes *when* those reads happen (spread across
real time instead of collapsed at t=0); it never changes *what* they read or
in what order. There is no purity to restore, because resolve producing a
plan and land-time producing the actual numbers was always the contract —
see `docs/domain/attack-timeline.md`'s clock table.

## No view store

Nothing is shown-anything: every painter reads live world state, so there is no
read-path to keep in sync. A shown-value store cannot represent
`force_deallocate`'s synchronous modifier revocation (every stat a dead node
granted is gone at once). The old store (`PresentationPlayer`, `RevealRecorder`,
`RevealEvent`, `RevealTimeline`) is parked in `presentation/`, not deleted; what
it was, why it was replaced and what would revive it:
`presentation/README.md`. Consequences:

- The damage number rides `Events.skill_node_damaged` directly, the same live
  signal every other painter reads (there is no `damage_shown` / `heal_shown`).
- The melee spike pop is announced once at the model event
  (`BladePopResolver.LiveGate._kill` emits `Events.blade_vertex_popped`, reached
  from `admit` inside `land_on` inside the applier's beat); `MeleePreview` holds no
  per-swing state.
- **The cascade ripple is presentation-owned.** `AllocationVFX.CASCADE_STEP`
  staggers only the *shatter spawn* off `cascade_started`'s BFS layers; the
  mutation stays synchronous, because `cascade_started` fires from inside
  `take_damage` and an awaiting handler does not block its emitter.

## Two invariants of concurrent VFX and mutation

1. **A committed swing must not be refreshable.** The cascade can fire *mid-swing*,
   and a refresh that tears down the blade `launch()` is awaiting drops the
   coroutine silently in Godot — the plan stays armed forever, a permanent hang.
   `MeleePreview._live_swing` guards it (see its docstring and `launch`'s for the
   general invariant: nothing may free the animating node mid-play); the
   ranged/magic path is covered by `BattleSystem.is_launching`'s docstring.
2. **`BattleSystem.is_launching` must stay adjacent to `_reset()`.** Callers settle
   on it as "is a swing resolving" and expect a cleared plan once it flips false.
