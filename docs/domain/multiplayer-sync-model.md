# The multiplayer sync model

**Decided 2026-08-18 in #473.** This is the architecture every networked and
hot-seat feature hangs off. It also rewrites what #458 (`CommandBus`) and #463
(versus) are for. Read this before touching input routing, `BattleSystem`'s
launch path, or the AI controller.

The game-design side of what a player is *allowed to know* lives in
[../design/info_gating.md](../design/info_gating.md); this doc covers the code
shape.

---

## The decision

**Host-authoritative, intent-up / confirmed-command-down.**

One peer — the host — is the only thing that decides anything. A client sends an
*intent*. The host validates it, applies it, and broadcasts the *confirmed
command*, plus a resolved payload for anything the client cannot recompute.
Every peer, the host included, applies world changes through one applier.

Single-player and hot-seat are not a special case: they run the same path
through a loopback transport. That is the whole point — if offline play works,
the networked path is already exercised.

```
click / AI decision
        │
        ▼
   Intent ──(transport)──▶ Host: validate → apply → broadcast
                                                       │
        ┌──────────────────────────────────────────────┘
        ▼
  ConfirmedCommand (+ resolved payload) ──▶ CommandApplier (every peer)
                                                       │
                                                       ▼
                                            world mutation (synchronous)
                                                       │
                                                       ▼
                                            VFX — pure observer
```

---

## Why, and why not the alternatives

### Four facts about this codebase that decided it

1. **The mutation surface is ~9 verbs, not 863 lines.** `PlayerInputController`
   is mostly *local plan-building* — the armed-mode stack, hover, pin, the
   core-drag ghost, blade member toggling. None of that crosses a wire. What
   actually mutates the world is `allocate`, `deallocate`, `deallocate_set`,
   `stake`, `extract`, `move_core`, `launch_attack`,
   `apply_armed_temp_upgrade_to`, `end_turn`, plus loot picks. Every
   `AllocationSystem` entry point is synchronous, gated, `-> bool`, and takes
   `(node, entity)` — already wire-shaped once `SkillNode` becomes `stable_id`.

2. **Mutation used to be entangled with animation; #504 fixed that
   specifically, and the fix is required under *every* model.** Before design
   B, `BattleSystem.launch_attack` resolved a pure `AttackOutcome` but landed
   damage *inside* `await attack_vfx.play(...)` / `await melee_preview.launch(...)`,
   so the authoritative world change happened at animation time, ordered by
   frames — exactly what lockstep, host authority, and state diff all forbid.
   As of #504 the VFX call is un-awaited and mutation runs on its own
   `OutcomeApplier`/`BeatClock` loop, paced by authored `arrival_time`, not by
   animation completion — see docs/domain/presentation-clock.md. VFX is now a
   pure observer in fact, not just in intent, which is what this section's
   architecture assumed all along. `BattleSystem.is_launching` is already the
   reentrancy guard #458 asked for.

3. **Combat is nearly RNG-free — but not entirely.** Initiative, allocation
   gating, mitigation, blade hit-scan and AI scoring are pure arithmetic. Three
   real exceptions:
   - `attack/spell/propagation/propagation_context.gd:47-55` — crit RNG falls
     back to `crit_rng.randomize()` when none is injected.
   - `systems/loot_system.gd:335,449,461` and
     `skill_node/addons/skill_dust_addon.gd:173` — global unseeded
     `Array.shuffle()`. **Killing-blow relics would differ per client.**
   - `attack/spell/propagation/step/random_pick_step.gd:24-26` — same null-RNG
     fallback.

4. **AI is frame-shaped and calls systems directly.**
   `entity/controller/ai_controller.gd:70,85,124` awaits
   `create_timer(turn_delay)` between decisions, then calls
   `allocation_system.allocate()` / `battle_system.launch_attack()` straight.
   Its *decisions* are deterministic; its *timing* is not.

### Rejected: lockstep on the shared seed

Cheapest wire by far, and #463 guessed it was "nearly free" given #457's
determinism contract. It isn't, for two reasons that are not about cost:

- **There is no authority at all**, so the later move to fog-filtered state —
  the only way hidden information becomes technically real — is a rewrite rather
  than a payload swap.
- **The unseeded `Array.shuffle()` calls** in loot / skill-dust would make
  killing-blow relics differ per client — a one-line fix (inject the seeded
  RNG), not an architectural blocker, but a real one as the code stands today.
- **`blade_arc_driver.gd:41`'s libm trig** is a residual caveat: transcendental
  functions aren't guaranteed bit-identical across platforms/compilers, which
  only matters for *bit-exact* lockstep, not for this rejection on its own.

`MeleeAttackPlan.resolve()` itself is **not** the blocker it looks like.
`attack/melee/sim/blade_sim.gd:28-31` is a pure fixed-dt XPBD loop
(`steps = ceil(duration/dt)`, `t = float(step)*dt`) with no frame delta and no
RNG; `blade_hit_scan.gd:35` walks `trajectory.sample_dt`; every call site
passes constants; `ai_blade_rollout.gd:37` already documents `simulate()` as
pure so it can run on `WorkerThreadPool`. `BladePopResolver` resolving
defensive-spike pops *during* the scan makes the hit set order-dependent
within that one deterministic call — but **order-dependence inside a
deterministic function is not a divergence risk**: given the same inputs,
every peer's re-simulation produces the same order and the same set. That
was the doc bug here, not a property of the sim.

Add the AI's frame-shaped timing, and the determinism budget buys nothing the
host could not simply tell us — the real blockers are hidden information and
the absence of authority, not re-simulability.

**Current information decision: every client gets full world state; hiding
is a UI concern.** No fog gating exists anywhere in planning today, so this
matches what the code already assumes, and it's acceptable on a LAN. If that
ever needs to change, it's a payload swap (ship less than full state) on top
of this model, not a rewrite of it — `RevealEvent`'s `from_value`/`to_value`
in the parked `presentation/` classes is already the shape a fog-gated or
authoritative-reveal payload would want; see `presentation/README.md`.

### Rejected: full state replication / snapshots

The largest model change on the table. No `StatBoard` wire format exists;
`Stat._modifiers` is memory-only; `EffectInstance` grant-ledgers carry no
provenance for revocation; addons are dynamically-spawned children. And it is
2000 nodes × boards × addons per sync.

Its one genuine upside is that the serializer *is* save/load (#23) — but that is
a separate, parked feature, and buying it here to get versus is backwards.

### Deferred, not rejected: fog-filtered state deltas

The only model where hidden information is *technically* enforced: the host
sends each client only what its `InfoLevel` permits. This is the correct
destination and it is where this design is aimed. It is deferred because it
needs the same `StatBoard` wire format that state replication needs.

The owner's call was **"socially real now, structured so this is reachable"** —
every peer holds the full world and the UI declines to draw what your fog does
not cover. Because the host already owns every decision and clients never mutate
directly, moving here later swaps *what gets broadcast* (confirmed command →
filtered delta) behind one seam, without touching input, AI, or the systems.

### Not a separate option: event sourcing

Effectively the chosen model plus persistence. If a run log is ever wanted, the
confirmed-command stream **is** the event log. Nothing extra to design.

---

## What crosses the wire, per action

| Action | Up (intent) | Down (confirmed) | Why |
|---|---|---|---|
| allocate / deallocate / deallocate_set / stake / extract / move_core | the command | the same command, nothing more | Fully deterministic, no RNG — every peer re-applies it identically |
| launch attack | the plan: mode, pivot + blade member `stable_id`s, or target + spell | the command **plus the serialized `AttackOutcome`** | `resolve()` is already pure and side-effect free, but the swing sim is order-dependent and crits roll. Clients apply the outcome and replay VFX; they never re-simulate |
| loot pick / relic roll | the pick intent | the resolved result | The host rolls; the shuffles stay host-only |
| end turn | the command | the command | The host's `TurnManager` is the clock, so `_tick_until_ready`'s group-order tiebreak stops being a hazard |

**Mass actions are one atomic command, never N.** `deallocate_set` and
mass-allocate paths serialize as a single command with a node list — splitting
them would let a peer observe an intermediate state that never legally existed.

---

## Where each subsystem sits

**AI runs on the host only and emits commands into the same queue.** That
deletes the frame-shaped problem outright: `turn_delay` becomes host-local
pacing with no sync meaning, and clients see an AI turn as an ordinary
confirmed-command stream. `ai_controller.gd` must stop calling
`allocation_system` / `battle_system` directly.

**Fog is a view concern**, computed per-client from state that client already
holds. The authority does not own fog. #459's camp-wide `VisionSystem.viewers`
becomes "my camp" on each client. Fog gains authority meaning only under the
deferred filtered-delta model, where the host uses it to decide what to send.

**Identifiers.** `SkillNode.stable_id` shipped for this and is the only legal
node reference on the wire. `Entity` has no id yet (`Participant.id: int`
exists); one gets added, and **the host mints it**, the way `Graph` mints
`stable_id`. If peers assign their own, two clients disagree about which entity
a command targets.

**Transport.** A `NetworkTransport` seam with `LoopbackTransport` (the default —
single-player and hot-seat) and `ENetTransport`. ENet is chosen because it is
built into Godot and zero-config on a LAN, **not** because it is the only
option: `WebSocketMultiplayerPeer`, `WebRTCMultiplayerPeer`, and raw
`PacketPeerUDP` / `StreamPeerTCP` all exist. The payload is a few hundred bytes
per turn, so the transport choice is close to free and reversible behind the
seam. Lobby: type-an-IP.

---

## Explicitly out of scope

- Fog-filtered state deltas and any `StatBoard` wire format.
- Save/load (#23).
- Reconnect and desync recovery. LAN, one room: a desync is a restart.

---

## Traps

- **Never frame-order a mutation** — never let animation completion, a
  dropped frame, or wall-clock timing decide *when* the world changes. That
  is the bug this design exists to prevent. This is narrower than "never
  mutate inside an await": `OutcomeApplier.apply` awaits a fixed logical
  `BeatClock` between landings (#504, design B) and that's fine — the
  interval is authored, not animation-derived, and nothing else can act
  inside the window. VFX observes; it never mutates and never gates a
  mutation on its own progress. See docs/domain/presentation-clock.md.
- **Never put a `SkillNode` or `Entity` reference in a command.** `stable_id`
  and the entity id only.
- **A command raised during another command's application queues, never
  re-enters.** This is the bug class that eats a week; the guard ships on day
  one, not as a hardening pass.
- **`Array.shuffle()` with no argument is a desync.** Every gameplay-affecting
  roll draws from a `GameSession` sub-stream. A null rng is an assert, never a
  `randomize()` fallback.
