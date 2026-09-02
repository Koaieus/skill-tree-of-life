---
description: The two-process multiplayer harness and the no-network Outcome playground — what each proves, and what deliberately does not
paths:
  - "network/**"
  - "autoload/wire.gd"
  - "addons/mp_sandbox/**"
  - "addons/outcome_playground/**"
  - "attack/outcome/outcome_fixture.gd"
  - "scenes/dev/mp_dev_sandbox.gd"
  - "scenes/dev/mp_procgen_sandbox.gd"
  - "scenes/dev/outcome_playground_world.gd"
---

The sandbox host's **Multiplayer** tab launches **two OS processes** of
`scenes/dev/mp_dev_sandbox.tscn` over ENet on localhost. Never "simplify" it to
two viewports in one process: `Events` is a process-global bus carrying live
node/entity references and every listener connects unscoped, so world B's
`VictorySystem` would latch on world A's death.

**The socket and the repo's ONE `@rpc` live on the `Wire` autoload, `/root/Wire`
(#713)** — a path that is identical on every peer and survives a scene change, so
a link can exist before a level does. `EnetTransport` is a facade over it and
holds no peer; `Wire.start_host` opens with a `stop()`, so a level ADOPTS a live
link (replaying `peer_joined` for peers already on it) rather than re-starting
one and dropping everybody who joined in the lobby.

**The LOBBY mounts a pair of its own (#714)** — only when `Wire` is already
open; `meta_root._push_lobby` alone decides a route opens a socket, and
`LobbyScreen` hands its link back at START because **`Wire` admits ONE bound
facade** (#715), and a **client runs no procgen**.

**`Transport` + `CommandLink` are still mounted in `scenes/game_root.tscn`
(#531), and a level may only SWAP the transport's script, never author a second
pair** — the seam stays per-level because two worlds in one process need a
transport each, and colliding sibling names mean `$Transport` picks whichever
Godot renamed last, silently. The default is `LoopbackTransport` with the link
`Mode.OFF`; the role comes from `GameSession.network` (`NetworkConfig`), which is
per-machine and deliberately not on `RunConfig`.

**One direction only, on purpose.** The host broadcasts confirmed commands; the
client applies them through its own `CommandApplier` and is otherwise a frozen
spectator. An intent channel upward is #463 (`Needs design`) — don't open it
here. Two instances prove *host acts → client mirrors*, never two people playing.

**A verb that does not cross is a missing submission site, not a transport gap.**
The link mirrors everything `CommandApplier` handles — grep who raises the
command before suspecting the wire.

**A `✗ DIVERGED` line is the harness working.** Chase divergence only on the
verbs `CommandApplier` actually handles — which is now every one of them:
attacks since #511 (`--autopilot` casts one) and loot since #522. As of #527
the fingerprint folds ownership + topology (edges) + accumulated per-node
state (stake/allocation/regen, HP quantized to int) — NOT derived `StatBoard`
totals, so a stat recompute that changes nothing accumulated still won't move
it; every effect the fold DOES cover is pinned by tests, not by the overlay.

**`--probe` measures the RESOLVE half of an attack, never the LAND half (#529).**
The client-only determinism probe re-resolves each received `launch_attack` from
`(plan, seed)` and diffs the hit set, order, arrival clock, crit tiers, costs and
timeline — *not* effective damage, HP numbers, the reclassified kind, the
`FLAG_GATED` bit or the dealloc sets, which `AttackRecord`'s own contract says a
peer cannot re-derive. So don't widen the diff to "the whole record" — that
reports 100% divergence for structural reasons. Its `skipped` column is
`CommandLink` declining to compare (the peer's queue was non-empty when the
command arrived, so its world is not at a command boundary), **not** a pass, and
`exempt` is loot's host-only roll working as designed.

**Since #540 the WORLD compare is pre-state vs pre-state, one command behind.**
The host ships the fingerprint of the world it was *about* to mutate
(`Command.pre_fingerprint`, stamped in `CommandApplier._drain`) and the peer
compares before it submits — because once the authority confirms *before* it
applies, there is no post-mutation world to sample at confirm time. So a `✗` is
attributed to the command AFTER the one that broke it, and a run's last command
is never compared. Don't "fix" a fingerprint mismatch by moving the compare back
after the apply; that reports every command as diverged.

**`--autopilot` is the only flag that goes to BOTH peers, and it is what fattens
Red's budget** (30 SP / 12 AP / 10 DP / 200 mana, so one turn can pay for the
whole sweep). Only the authority sweeps, but the boost must match on every peer
or `_apply_mass_allocate`'s receiving-side affordability re-derivation disagrees
with what the host applied. Without the flag Red is an ordinary level-1 board —
so a plain tab launch you intend to *play* is not supposed to show inflated
stats, and if it does, that gate broke again.

**`--turns=N` above ~10 does not do what it says.** The autopilot stops sweeping
once Red dies (around sweep 10), because `_on_turn_started` only sweeps when
`entity == _red` — Blue's AI then grinds solo until you kill the process. So
`end_turn`'s probe counts are wall-clock-dependent, not run-shape-dependent, and
are **not comparable between two runs**. Compare the sweep-driven verbs.

**Suspect a replay bug? The Outcome playground tab takes the wire out of it
(#539)** — it submits a recorded `LaunchAttackCommand` to a local
`CommandApplier` with no `CommandLink`, so a fixture that replays there clears
the replay path and leaves messaging as the only suspect. The world is rebuilt
from `scenes/dev/outcome_playground_world.gd` rather than carried in the fixture
(ids mint from per-`Graph` child order, so both sides must build it the same
way). **Never hand-edit a `test/fixtures/outcome/*.tres`** — regenerate:
`REGEN_OUTCOME_FIXTURE=1 mise run test:one -- res://test/unit/attack/test_outcome_fixture_replay.gd`,
then read the diff. A moved `world_fingerprint_at_capture` means the builder
drifted; a moved `expected_fingerprint` alone means the replay path changed.

See docs/domain/multiplayer-harness.md and docs/domain/determinism-probe.md.
