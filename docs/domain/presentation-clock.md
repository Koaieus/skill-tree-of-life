# Presentation clock — engineering reference

Code: `attack/outcome/beat_clock.gd`, `attack/outcome/outcome_applier.gd`,
`systems/battle_system.gd`. Design decision: #488. Implementation: #504
(merged `2f08a56`). This is design **B** — see `presentation/README.md` for
design A, which it replaced.

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
docstring (lines 4-19) for the clock's own statement of this; it is the
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

## Why this is not the disease #474 cured

`await attack_vfx.play(...)` used to order mutation by *animation
completion* — a lag spike, a muted animation, or a dropped frame changed
gameplay. #474 killed that. Design B reintroduces an `await` into the
mutation path (`OutcomeApplier.apply` awaits `BeatClock.advance_to`), and on
its face that looks like backsliding. It isn't, because it's a different
mechanism:

- The interval is **fixed and logical** — authored `arrival_time`, not wall
  time to an animation's completion.
- The game is turn-based and `BattleSystem.is_launching` guards reentrancy —
  nothing else can act inside the window.
- Nothing times *itself* off the wait. VFX runs unawaited, alongside the
  mutation loop, timing itself off the same `arrival_time` values
  (`battle_system.gd:226-238`) rather than off the loop's progress.

So only *order* is observable inside the window, and order is code-order —
the same order the plan authored before launch. The rule in its accurate
form is **never frame-ordered mutation** — not "never mutate inside an
await." The over-broad phrasing is the doc bug that drove five rounds of
latches (#479/#481/#482/#483/#485/#487), and undoing it is what this whole
hub existed for.

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
idempotent, `beat_clock.gd:92-96`) is the whole mitigation: it releases any
parked wait and makes every remaining `advance_to` a no-op, so the rest of
the outcome lands immediately. `BattleSystem.drain_pending_mutations()`
holds the in-flight clock and is called from `GameRoot._exit_tree`
(`game_root.gd:154-160`) — the drain runs synchronously inside teardown,
while the nodes it mutates are still alive.

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
raw, unmitigated damage; `Mitigation.apply` runs inside `SkillNode.take_damage`
at land time (`damage_instance.gd:4-9`, `skill_node.gd:1281`) and can
reclassify a hit from DAMAGE to HEAL there; `HitInstance.effective_amount`
is `0.0` until a hit is actually applied. `AllocationSystem.force_deallocate`
revokes a dead node's granted modifiers synchronously
(`allocation_system.gd:267-269`). So a later hit in a volley already
mitigates against a board an earlier hit's cascade stripped — **before**
design B, and after it. B changes *when* those reads happen (spread across
real time instead of collapsed at t=0); it never changes *what* they read or
in what order. There is no purity to restore, because resolve producing a
plan and land-time producing the actual numbers was always the contract —
see `docs/domain/attack-timeline.md`'s clock table.

## Why there is no view store

Design A needed one because `force_deallocate` revokes modifiers
*immediately* and synchronously. A shown-value-per-pool (three fields:
`shown_hp`, `shown_owner`, `shown_health`) can't represent that — the moment
a node dies, every stat it was granting is gone from the model, so a
painter reading three shown fields would already be wrong about everything
those modifiers touched. The honest fix was a shown-value *per stat*, not
three. Three fields was never a resting point on the way to correct; it was
a design that could not finish. B sidesteps the question entirely: nothing
is shown-anything, so there's no read-path to keep in sync.

## What this replaced

Two clocks were deleted, not one:

- The **view store** — `PresentationPlayer`, `RevealRecorder`,
  `RevealEvent`, `RevealTimeline` — parked, not deleted; see
  `presentation/README.md` for what they were and why they're kept on disk.
- **`Events.damage_shown` / `heal_shown`** went with it. Three separate
  coordinators emitted them on their own timers while the model mutated on
  a different one — the same disease as the view store, one layer down, and
  it's why killing the store alone wouldn't have been enough. The damage
  number now rides `Events.skill_node_damaged` directly (`events.gd:9`),
  the same live signal every other painter reads.

Two smaller pieces of design-A machinery went with the same cut:

- **The melee spike pop** used to be re-announced by `MeleePreview` during
  the animation replay — which only worked because design A applied the
  whole outcome before the replay began, so `BladePopResolver.Result.pops`
  was already complete by the time `MeleePreview` walked it. Under B the
  swing animates *concurrently* with the mutation, so that snapshot would
  be empty partway through. The pop is now announced once, at the model
  event itself: `BladePopResolver.LiveGate._kill` emits
  `Events.blade_vertex_popped` inline (`blade_pop_resolver.gd:170-191`),
  reached from `admit` inside `land_on` inside the applier's beat — the same
  clock the damage, health bar, and shatter are on. `MeleePreview` holds no
  per-swing state of its own anymore.
- **The cascade ripple is presentation-owned**, not model-owned.
  `AllocationVFX.CASCADE_STEP` (`ui/vfx/allocation_vfx.gd:82`) staggers only
  the *shatter spawn* off `cascade_started`'s BFS layers — a purely visual
  stagger layered on top of a mutation that stays synchronous. It has to
  stay synchronous: `cascade_started` fires from inside `take_damage`, and
  an awaiting handler does not block its emitter, so there is no clock to
  put the actual dealloc on even if one were wanted.

## `presentation/` is parked, not deleted

`presentation/README.md` covers this in full — what the four classes were,
why B replaced them, and what would revive them (an authoritative or
fog-gated multiplayer mode, per the current-information decision in
`docs/domain/multiplayer-sync-model.md`). Don't restate it here; read that
file if you're about to touch anything in `presentation/`.

## Two hangs found building this, both structural to concurrency

Both are consequences of VFX and mutation overlapping in time — design A,
where mutation finished before any replay began, could not have hit either
of these.

1. **A committed swing must not be refreshable.** The cascade can now fire
   *mid-swing* instead of after the whole outcome lands, and
   `MeleePreview._refresh` used to tear down the blade that `launch()` was
   still awaiting. A coroutine awaiting a freed object is silently dropped
   in Godot — `_vfx_finished` never fires, `_reset()` never runs, and the
   plan stays armed forever: a permanent hang, not a cosmetic glitch.
   `MeleePreview._live_swing` guards it — see `battle_system.gd`'s
   `_vfx_running` docstring for the general form of this invariant (nothing
   may free the animating node mid-play) and its audit of the ranged/magic
   path.
2. **`BattleSystem.is_launching` must stay adjacent to `_reset()`.** Callers
   settle on it as "is a swing resolving" and expect a cleared plan once it
   flips false; moving the reset away from the flag reopens the same class
   of stuck-plan bug from a different angle.
