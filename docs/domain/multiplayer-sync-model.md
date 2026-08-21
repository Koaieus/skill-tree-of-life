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
     `Array.shuffle()`. **Not a hazard under the chosen model** (owner call
     2026-08-21, below): the roll is host-only and its *result* is what crosses
     the wire, so there is nothing for a peer to reproduce. It was a hazard
     under lockstep, which is why it is listed here — see the rejection below.
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
  *This clause is specific to lockstep and no longer describes the codebase's
  risk profile:* under the chosen model those rolls are host-only and the pick
  travels as a result, so they need no seeding (owner call 2026-08-21, below).
  **The rejection stands regardless** — it rests on the absence of authority,
  not on the shuffles.
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
| launch attack | the plan: mode, pivot + blade member `stable_id`s, or target + spell (`AttackPlan.to_dict`) | the same command **plus `AttackRecord`**, a post-apply record of what each landing actually did, stamped by `BattleSystem` during application (#511) | `resolve()` is already pure and side-effect free, but the swing sim is order-dependent and crits roll. Clients reconstruct the recorded effects and replay VFX; they never re-simulate and never re-derive a number |
| loot pick / relic roll | the pick intent | the resolved result | The host rolls; the shuffles stay host-only |
| end turn | the command | the command | The host's `TurnManager` is the clock, so `_tick_until_ready`'s group-order tiebreak stops being a hazard |

**Loot is rolled host-side and only the pick travels.** The candidate list is
already known to whoever received the request, so the pick command carries
`(entity_id, request_id, chosen_indices)` and nothing more (#509).

> **Owner call 2026-08-21:** *"loot picks are just 'hey i picked <this
> statmodifier>', users cannot distinguish a same-seed roll from a random roll
> given that looting is done by 1 player and invisible to others -- the
> resulting pick however needs to be communicated back to host so they can
> broadcast or whatever if needed"*

This supersedes the earlier reading — carried in §"Four facts" fact 3 and in the
lockstep rejection — that the loot/skill-dust `Array.shuffle()` calls were a
per-client divergence hazard needing a seeded RNG.

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

**The applier is `command/command_applier.gd` (#510).** One serial, **async**
queue: `submit(cmd)` enqueues, and drains only if no drain is running. Two
guards exist and are nested, answering different questions —
`BattleSystem.is_launching` ("an attack is in flight", owning the plan's
lifetime across mutation *and* VFX) and `CommandApplier.is_applying` ("a command
is being applied", covering every verb). `PlayerInputController.can_player_act()`
reads **both**. Outcomes come back as `command_applied(cmd, success)`, emitted
*inside* the guard so a fallback handler that submits — the deallocate →
cascade-offer path — queues rather than re-entering; `applying_changed` fires
*after* the flag clears, matching `is_launching`'s deliberate ordering.

**`command_confirmed(cmd)` is the mirror seam, and it is not `command_applied`.**
Application spans more than mutation: `BattleSystem._commit` keeps awaiting
`_vfx_finished` after the world has settled, because `is_launching` owns the
plan's lifetime through the swing (#406). Mirroring off `command_applied`
therefore made a peer wait out the *host's animation* before it could start its
own — lag proportional to spell length, for a payload that was final much
earlier. So a verb with such a tail calls `applier.confirm(cmd)` at its settle
point (BattleSystem does, on the line after `AttackRecord.capture`), and
`CommandLink` broadcasts off that. For every other verb the drain confirms on
its behalf, immediately before `command_applied`, so the seam costs nothing.
`confirm` is idempotent and only ever called for a command that succeeded —
which is where "a refused command changed nothing, so mirror nothing" now
lives. Ordering across commands is untouched: the queue is serial, so a
mid-apply confirm still lands between its neighbours'.

Routed so far: every `PlayerInputController` mutation (#510) and
`battle_system.launch_attack` (#511 — it builds a `LaunchAttackCommand`,
submits it, and parks on `applying_changed`, so every existing caller still
awaits the whole action). Still direct, by plan: `ai_controller` (child D).
`PickLootCommand` exists but is not routed — correlating `request_id` back to a
live `LootPickRequest` needs a registry nobody has built yet.

**Identifiers.** `SkillNode.stable_id` and `Entity.entity_id` are the only
legal references on the wire. Both are minted by `Graph` — `entity_id` eagerly
on entry to `entities_container`, resolved with `Graph.get_by_entity_id` (#509).
Under host authority that means *the host's* `Graph` decides; if peers assign
their own, two clients disagree about which entity a command targets.

**Transport.** A `NetworkTransport` seam with `LoopbackTransport` (the default —
single-player and hot-seat) and `ENetTransport`. ENet is chosen because it is
built into Godot and zero-config on a LAN, **not** because it is the only
option: `WebSocketMultiplayerPeer`, `WebRTCMultiplayerPeer`, and raw
`PacketPeerUDP` / `StreamPeerTCP` all exist. The transport choice is close to
free and reversible behind the seam. Lobby: type-an-IP.

**One command type, two states (#511).** `LaunchAttackCommand` is the only
asymmetric verb in the vocabulary, and that is deliberate. An EMPTY `record`
means *initiate*: the authority stamps the seed, resolves, gates on
affordability, and applies naturally, then stamps the record it produced onto
the same object — which `CommandLink` broadcasts, because it encodes on
`command_confirmed`, raised the instant that record is stamped. A POPULATED `record` means *replay*:
a peer rebuilds the plan (for the animation only) and the recorded deltas (for
the world), and lands them through the same `OutcomeApplier` on the same
`BeatClock`. Two types would need the receiver to know its own role to refuse
the wrong one; one type whose payload says which half of the work is already
done needs no role at all — and when #463 adds the intent channel upward, a
client's intent IS this command with an empty record.

**A peer re-simulates to DRAW, never to derive.** Melee reforms a bit-identical
blade from the plan (`blade_sim.gd` is a pure fixed-dt XPBD loop, no frame
delta, no RNG) so the swing animates; the damage it shows comes off the record.
That is not the re-simulation this model forbids — nothing is mutated and no
number is computed. `docs/domain/attack-timeline.md`'s land-time re-read
contract is host-side only, and now says so.

**Payload size.** Most commands are a few dozen bytes. **The attack record is
the outlier and magic is its worst case:** `trail_blazer.tres` authorises
`max_hops = 20` and `reverberator.tres` allows `max_visits_per_node = 6`, so a
single cast can genuinely produce ~100 landings, each carrying a
post-mitigation amount plus its crit/gate flags. That is kilobytes, not
hundreds of bytes — still a trivial one-shot burst on a LAN, but it is why the
record encodes as **parallel arrays of scalars with the timeline holding
indices into the flat hit list**, not ~100 dictionaries with string keys. The
indices are required for correctness anyway (a `PropagationEvent`'s hits are
shared references into `AttackOutcome.hits`, never copies); the size just makes
the same encoding the obvious one.

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
  and the entity id only. And read a node's id with `Graph.get_stable_id(node)`,
  never `node.stable_id` — node ids mint **lazily** (unlike `entity_id`), so a
  container-added or hand-authored node reads `0` until something forces a
  topology rebuild, and a command carrying `0` resolves to nothing, silently.
- **A command raised during another command's application queues, never
  re-enters.** This is the bug class that eats a week; the guard ships on day
  one, not as a hardening pass.
- **Combat reproducibility is the per-attack seed stamp, not a run-level
  stream.** `launch_attack` stamps `attack_plan.resolve_seed` before resolving
  and `outcome.resolve_seed` carries it back out (`8dc6f77`); that stamp rides
  down with the outcome so a peer can verify by re-resolving. Loot rolls are
  **host-only** and need no determinism guarantee at all — their unseeded
  `Array.shuffle()` calls are not a hazard under this model.

  This supersedes what this section said before 2026-08-21 — *"`Array.shuffle()`
  with no argument is a desync. Every gameplay-affecting roll draws from a
  `GameSession` sub-stream."*

  > **Owner call 2026-08-21** (`docs/handoffs/lan-wave-0.md`): *"we don't care
  > about that seed beyond the procgen using it, for now. possibly forever."*

  Consequence, and it is deliberate: **the same seed reproduces the same map,
  not the same fights.** #457's `GameSession` seed is a procgen input; it is not
  a determinism contract over combat or loot.

- **Still never roll from a null RNG on anything a peer must reproduce.** The
  narrower rule that survives: if a result crosses the wire as something a peer
  re-derives rather than receives, it draws from the seed it was handed. What
  changed is the *scope* — host-only rolls (loot, relics) are exempt, because
  nothing re-derives them.
