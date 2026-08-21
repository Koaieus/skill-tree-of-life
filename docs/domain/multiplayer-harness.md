# The multiplayer harness

**Wave 0 of the LAN work made runnable.** A sandbox-host tab that launches two
OS processes of the same scene — one host, one client — over ENet on
127.0.0.1, so the command layer that landed in #509/#510 can be *watched*
crossing a wire instead of reasoned about.

It is a harness, not the sync layer. The architecture it serves is
[multiplayer-sync-model.md](multiplayer-sync-model.md); read that first.

## What it is

| Piece | Where |
|---|---|
| **Multiplayer** tab | `addons/sandbox_host/tabs/80_multiplayer_tab.tscn` |
| Launcher panel | `addons/mp_sandbox/mp_sandbox_panel.tscn` |
| The scene both processes run | `scenes/dev/mp_dev_sandbox.tscn` (inherits `dev_sandbox.tscn`) |
| Transport seam | `network/network_transport.gd` + `enet_transport.gd` / `loopback_transport.gd` |
| Applier ↔ transport bridge | `network/command_link.gd` |
| Divergence detector | `network/world_fingerprint.gd` |

From a terminal, no editor needed:

```
godot --headless --path . scenes/dev/mp_dev_sandbox.tscn -- --role=host --port=9099 --autopilot
godot --headless --path . scenes/dev/mp_dev_sandbox.tscn -- --role=client --address=127.0.0.1 --port=9099
```

`--autopilot` (host only) allocates one frontier node a second after the client
links, which is the whole slice in one line of log on each side. Everything
after `--` lands in `OS.get_cmdline_user_args()`; put it before and the engine
tries to interpret it.

## The three decisions, and why

### Two OS processes, not two viewports in one

`autoload/events.gd` is a **process-global** bus, its ~25 signals carry live
`SkillNode` / `Entity` **references**, and every listener — `LootSystem`,
`VictorySystem`, `AllocationSystem`, `BattleSystem`, `HudRoot` — connects
unconditionally, scoped to nothing. Two worlds in one process means world B's
`VictorySystem` latches on world A's death. That is not something a placeholder
can work around; it is a refactor of the event bus.

Two processes give two sets of autoloads for free. This is also why the tab is a
`SandboxLiveTab` and not a `SandboxPlayedTab`: the latter's Run button calls
`EditorInterface.play_custom_scene`, which gives you exactly one instance.

The one place two worlds *do* share a process is `test/unit/network/test_command_link.gd`
— legitimate only because nothing in that file kills anything, so none of the
cross-wiring listeners ever fire. A test that kills an entity does not belong there.

### An inherited scene of `dev_sandbox.tscn`, not a copy

The harness needs the **same graph on both peers with no seed on the wire**,
which is what picks hand-authored topology over procgen. A duplicated `.tscn`
delivers that until the first edit to the original; an inherited scene cannot
drift.

`mp_dev_sandbox.gd` changes exactly three things about the base scene:

1. **Blue becomes human.** The AI still calls `AllocationSystem` /
   `BattleSystem` directly (#512), so its turns would mutate the host's world
   without passing through `CommandApplier` and the client would silently drift.
   Both heroes human keeps every mutation in this scene on the mirrored path.
   The host hot-seats between them; the client stays bound to Blue.
2. **The client binds Blue and freezes input** via `set_input_frozen` (#486) —
   the existing "every channel off" seam, no controller change needed.
3. **The client drops the hot-seat handover.** On a networked peer the local
   view is fixed to the local hero; leaving it connected would swing the
   client's HUD onto Red.

### One direction: host down to client

The client is a **spectator with a real applier**. Routing its own input upward
means it must stop applying locally and wait to be told — surgery on
`PlayerInputController`'s submit path and on `BattleSystem`. That is #463, which
`docs/FOCUS.md` gates behind #511 and #512. Wave 0 stops short on purpose.

## What mirrors, and what does not

**Mirrors:** every verb `CommandApplier` handles — allocate, deallocate,
deallocate_set, mass_allocate, stake, extract, move_core, end_turn,
toggle_temp_upgrade, and (since #511) launch_attack. The host broadcasts each
*confirmed* command (refused ones changed nothing, so there is nothing to
mirror) with a world fingerprint attached; the client decodes via
`CommandCodec`, applies through its own applier, and compares.

**Attacks cross as of #511.** The command carries `AttackRecord` — a post-apply
record of what each landing actually did — and the client replays it rather
than re-resolving. `--autopilot` now fires a Spark after its allocate, so a
terminal-driven pair exercises the attack path without a human clicking.
**Read that `✓` carefully:** the fingerprint folds ownership only, so a cast
that damages without killing anything leaves it unchanged either way. What the
`← launch_attack` line proves is that the command decoded and applied on the
client at all; the *effects* are pinned by
`test/unit/attack/test_attack_record_replay.gd`, which compares node HP, AP and
mana across two real worlds through the same wire encoding.

**Does not:** loot rolls (#509's `PickLootCommand` is unrouted). Pick loot in
the host window and the client's overlay reads `✗ DIVERGED`. **That is the
harness working.** The whole point of the fingerprint is that a known gap
announces itself instead of being discovered three weeks later as "multiplayer
feels weird".

## The fingerprint

`WorldFingerprint.compute(graph)` folds the sorted `(stable_id, owner
entity_id)` pairs — exactly what the wave-0 vocabulary can change. Not HP, not
stats: a fingerprint that moves for reasons the harness cannot sync is one
nobody reads.

Two properties are load-bearing:

- **It reads every id through `Graph.get_stable_id`,** which forces the lazy
  mint. Every node in a hand-authored scene reads `0` until a topology rebuild,
  and a command carrying `0` resolves to nothing *silently*
  (`.claude/rules/multiplayer-sync.md`). Comparing fingerprints at link-up turns
  that silent failure into a visible mismatch before a single command crosses.
- **It is folded by hand (FNV-1a), not `Array.hash()`.** The number is compared
  across processes, so it must not depend on engine hashing internals.

## Extending it

- **A different transport** — subclass `NetworkTransport`. Nothing above it
  knows about ENet. Note `EnetTransport` claims the SceneTree's `MultiplayerAPI`
  and resolves its one RPC **by node path**, so both peers must run a scene
  where the transport sits at the same path (they do — same `.tscn`).
- **A different world** — point the panel's Scene field at any scene whose root
  handles the same `--role` / `--port` / `--address` args.
- **The intent channel upward** — that is #463, and it starts by making
  `PlayerInputController` submit to a *link* rather than to the applier
  directly. `CommandLink._applying_remote` already exists so a peer that both
  mirrors and broadcasts cannot echo itself into a loop.
