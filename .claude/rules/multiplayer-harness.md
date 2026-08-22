---
description: The two-process multiplayer harness — why two OS processes, what mirrors, what deliberately does not
paths:
  - "network/**"
  - "addons/mp_sandbox/**"
  - "scenes/dev/mp_dev_sandbox.gd"
---

The sandbox host's **Multiplayer** tab launches **two OS processes** of
`scenes/dev/mp_dev_sandbox.tscn` over ENet on localhost. Never "simplify" it to
two viewports in one process: `Events` is a process-global bus carrying live
node/entity references and every listener connects unscoped, so world B's
`VictorySystem` would latch on world A's death.

**One direction only, on purpose.** The host broadcasts confirmed commands; the
client applies them through its own `CommandApplier` and is otherwise a frozen
spectator. An intent channel upward is #463 (`Needs design`) — don't open it
here. Two instances prove *host acts → client mirrors*, never two people playing.

**A verb that does not cross is a missing submission site, not a transport gap.**
The link mirrors everything `CommandApplier` handles — grep who raises the
command before suspecting the wire.

**A `✗ DIVERGED` line is the harness working.** Loot picks (unrouted
`PickLootCommand`, #522) still never cross, so the fingerprint is supposed to
disagree after a pick. Chase divergence only on the verbs `CommandApplier`
actually handles — attacks now among them (#511), and `--autopilot` casts one.

See docs/domain/multiplayer-harness.md.
