# The multiplayer harness

A sandbox-host tab launches two OS processes of the same scene — one host, one client — over ENet on 127.0.0.1, so the command layer can be *watched* crossing a wire instead of reasoned about. It is a harness, not the sync layer; the architecture it serves is [multiplayer-sync-model.md](multiplayer-sync-model.md) — read that first.

## What it is

| Piece | Where |
|---|---|
| **Multiplayer** tab | `addons/sandbox_host/tabs/80_multiplayer_tab.tscn` |
| Launcher panel | `addons/mp_sandbox/mp_sandbox_panel.tscn` |
| Rung 1 scene (both processes) | `scenes/dev/mp_dev_sandbox.tscn` (inherits `dev_sandbox.tscn`) |
| Rung 2 scene | `scenes/dev/mp_procgen_sandbox.tscn` (instances `game_root.tscn`) |
| Rung 3 — no scene, the real menu | `MetaRoot._drive_lobby_from_cmdline`, `--lobby=host\|client` |
| Rung 4 — rung 3 played to a verdict | `mise run mp:e2e` (`.mise/tasks/mp/e2e`) |
| Argv vocabulary | `network/harness_flags.gd` (`HarnessFlags`) |
| Per-level mount of the wire seam | `scenes/game_root.tscn` → `Transport` + `NetworkLink` and its channels |
| Socket + the single `@rpc` | `autoload/wire.gd`, `/root/Wire` |
| Transport seam | `network/network_transport.gd` + `enet_transport.gd` / `loopback_transport.gd` |
| Link core (role, build gate, pre-world latch, dispatch) | `network/network_link.gd` |
| Applier ↔ link bridge (command down, intent up, refusal down) | `network/command_channel.gd` |
| World sync (snapshot / setup / entities / resync) | `network/world_sync_channel.gd` |
| Divergence detector | `command/world_fingerprint.gd` |
| Determinism probe | `network/determinism_probe.gd` |

From a terminal, no editor needed:

```
godot --headless --path . scenes/dev/mp_dev_sandbox.tscn -- --role=host --port=9099 --autopilot
godot --headless --path . scenes/dev/mp_dev_sandbox.tscn -- --role=client --address=127.0.0.1 --port=9099 --autopilot
```

Everything after `--` lands in `OS.get_cmdline_user_args()`; put it before and the engine tries to interpret it.

- **`--autopilot` goes on BOTH lines.** It drives every verb `CommandApplier` handles from Red's opening turn — allocate, mass_allocate, stake/extract (each a pledge that opens a channel; the cap moves on later turns, not in the sweep), deallocate, deallocate_set, move_core, all three attack modes (melee scored via `AiBladeRollout`, the rollout `AIController` uses), a temp-upgrade toggle, a loot claim when there is one, then end_turn — one log line per verb per side. A verb that cannot legally fire logs `SKIPPED` with the reason. Only the authority sweeps (`_start_sweep_if_due` gates on `CommandApplier.is_authority`), but the flag also gates `_boost_autopilot_budget` (Red gets 30 SP / 12 AP / 10 DP, since a level-1 board can't pay for the sweep), and that boost must be identical on every peer: `CommandApplier._apply_mass_allocate` re-derives affordability from the receiving peer's own board, so a host-only boost desyncs the first budget-gated verb. **No flag, no boost** — to *play* the pair, leave the toggle off and Red is an ordinary level-1 board.
- **`--turns=N`** (host only) sweeps N of Red's turns, hooked on `TurnManager.turn_started` (Blue's AI takes a real turn in between); bare `--turns` runs until killed. One sweep is ~17 commands; the probe needs a few hundred.
- **`--probe`** (client only) arms the determinism probe: the mirroring peer re-resolves each received `launch_attack` locally and tallies whether it could have derived what the host sent. It mutates nothing. Scope and why `skipped` is a finding: [determinism-probe.md](determinism-probe.md).

## The mount, and why a level may only SWAP it

`Transport` and `NetworkLink` (with its channels) are direct children of `GameRoot`, so every level inherits them at the same node paths. Godot resolves an RPC by node path, so two peers running different scenes only reach each other if the transport sits in the same place in both; mounting it in the composition root makes that true by construction.

- **The default is `LoopbackTransport`, and the link is mounted `Role.OFFLINE`**: mounted and inert, so single-player is unchanged. A role raises it; the mount never does.
- **A level that wants a real socket overrides that node's script** — an inherited-node property override in the `.tscn` (`[node name="Transport" parent="."]` / `script = ExtResource("3_transport")` pointing at `enet_transport.gd`). `mp_dev_sandbox.tscn` and `level.tscn` do this; `first_level_sandbox.tscn` inherits it from the latter.
- **Never author a second pair.** Inheriting plus authoring gives colliding sibling names and `$Transport` resolves to whichever Godot renamed last — a dead link with no error. `test/integration/network/test_link_mount.gd` asserts the count, not just the type.

Which role this machine takes is `NetworkConfig` on `GameSession` — the per-machine half of a run's setup, alongside `SeatPolicy`, deliberately not on `RunConfig`, which crosses the wire by value (`docs/domain/seat-policy.md`). `GameRoot` adopts the role at the top of `_ready` (before anything can act and diverge) and opens the socket after `_setup_level` (so an arriving command finds a world).

## The socket outlives the scene

**`Wire` (`autoload/wire.gd`, `/root/Wire`) owns the socket and the repo's only `@rpc`** (`_receive`). Its path is identical on every peer and survives `SceneDirector.goto`. `multiplayer.multiplayer_peer` belongs to the `SceneTree`, so an open socket already survives a scene change; what died with a freed `GameRoot` was the RPC target, the signal connections and the peer list — `Wire` keeps those. `EnetTransport` is a facade over it and holds no peer; the per-level `Transport` mount, the `LoopbackTransport` default and every two-worlds-in-one-process fixture keep working (a process-wide transport could not serve two worlds; a process-wide socket always did).

**A level adopts a link it did not open.** `start_host` / `start_client` bring the socket up only when there is not one; when the lobby already opened it they bind and **replay `peer_joined` for the peers already on it**, so an adopting host still stamps roster seats and ships run setup. `Wire.start_host` opens with a `stop()`, so a level that blindly re-started would tear down the link it was handed. `test_wire_outlives_the_level.gd` pins the mechanism.

**Exactly one facade may be bound at a time.** The lobby and the level each mount an `EnetTransport` over this one socket; two bound at once each re-emit `Wire.message_received`, so every packet is handled twice with no error. `Wire` hands out a single binder token (`claim_binder` / `release_binder` / `has_binder`), `EnetTransport._bind` answers `ERR_ALREADY_IN_USE` when refused (a `push_warning`, never a `push_error`, which GUT counts as unexpected), and both lobby roles hand their link back before routing (`LobbyScreen.release_link`, off `GameSession.run_started`).

**The run's shape crosses at START, not on JOIN.** `LobbyScreen` broadcasts `run_setup`, and **a joining client never runs `GraphProcgen`**: it seats the roster, builds an empty graph, and `NetworkSession.pull_host_world` brings the authority's serialized world. A joined level with an empty graph is the normal shape, and the `_pending_entities` park in `WorldSyncChannel` is the primary path. Procgen spawns entities the roster never names (one per removable blocker, ~120 on the shipped preset); `EntitySnapshot` asks `WorldSyncChannel.entity_spawner` (`EntityFactory.spawn_snapshot_entity`) to rebuild any row it cannot resolve, at the authority's `entity_id` — without it their nodes decode as *unowned* and the first compare disagrees in a way that looks exactly like a procgen desync.

**The world is pushed AND pulled, and applied once.** The host pushes on `peer_joined` and also answers the client's `request_resync`, because either leg alone can be dropped in silence (the client's level is up in milliseconds while the host spends 5-10 s generating). Both legs carry `WorldSyncChannel.KEY_JOIN`; the client's `_join_world_arrived` latch drops the loser. The latch is keyed off the message flag, not a fingerprint compare, because the fold covers neither tags nor effects, so a mid-run repair must still apply when the fingerprints already agree. While waiting, the joiner re-asks every `GameRoot.JOIN_PULL_RETRY_SEC` (3 s) via `WorldSyncChannel.renew_join_pull`. `test_join_world_applies_once.gd` pins both halves. A joining client's `_ready` awaits `resync_applied` before arming `VictorySystem`, starting a turn or lifting the curtain — unbounded on purpose, with `SceneDirector`'s 30 s reveal timeout as the backstop.

## The decisions, and why

### Two OS processes, not two viewports in one

`autoload/events.gd` is a process-global bus whose ~25 signals carry live `SkillNode` / `Entity` references, and every listener (`LootSystem`, `VictorySystem`, `AllocationSystem`, `BattleSystem`, `HudRoot`) connects unconditionally. Two worlds in one process means world B's `VictorySystem` latches on world A's death. Two processes give two sets of autoloads for free — also why the tab is a `SandboxLiveTab`, not a `SandboxPlayedTab` (whose Run button gives exactly one instance). The one place two worlds share a process is `test/unit/network/test_command_channel.gd`, legitimate only because nothing there kills anything.

### An inherited scene of `dev_sandbox.tscn`, not a copy

The harness needs the same graph on both peers with no seed on the wire, which picks hand-authored topology over procgen; an inherited scene cannot drift. `mp_dev_sandbox.gd` changes two things: the **client binds Blue and freezes input** via `set_input_frozen`, and the **client drops the hot-seat handover** (on a networked peer the view is fixed to the local hero).

**Blue stays the AI opponent.** `AIController` emits commands through `CommandApplier` like everything else, so the AI keeps every mutation on the mirrored path. `ControllerFactory.ensure_all` attaches an `AIController` to Blue on BOTH peers, and each resolves its own peer's applier — so a mirror's copy would decide independently the instant a mirrored `EndTurnCommand` hands Blue the turn. `AIController.take_turn` is therefore gated on `CommandApplier.is_authority` (`NetworkLink.role`'s setter, through `CommandChannel`, is the only writer). The host hot-seats Red and Blue; the client stays on Blue.

### Both directions

The command channel runs both ways. **Down:** the host broadcasts each confirmed command (refused ones changed nothing) with a world fingerprint; the client decodes via `CommandCodec`, applies through its own applier and compares. **Up:** a client's input is emitted as `KIND_INTENT`; the host runs it through its applier and either confirms it down as a command or answers `KIND_REFUSAL` naming the intent id the client minted. A mirror never opens its own turn or originates a mutation; the harness scenes freeze the client's input so the autopilot and AI are the only drivers (`.claude/rules/multiplayer-sync.md`, ADR 0002). `CommandChannel._applying_remote` keeps a peer that both mirrors and broadcasts from echoing itself.

## What mirrors

Every verb `CommandApplier` handles: allocate, deallocate, deallocate_set, mass_allocate, stake, extract, move_core, end_turn, toggle_temp_upgrade, launch_attack, and loot.

- **Attacks** carry `AttackRecord` — a post-apply record of what each landing did — and the client replays it rather than re-resolving. The fingerprint folds ownership + topology + accumulated per-node state (HP quantized), so a cast that damages without killing moves it, but derived `StatBoard` totals (AP, aura contributions) stay outside the fold on purpose. The `← launch_attack` line proves the command decoded and applied; the *effects* are pinned by `test/unit/attack/test_attack_record_replay.gd`, which compares node HP and AP across two real worlds through the same wire encoding.
- **Loot** rides as `LootRoundCommand` carrying what was granted by value, so a peer grants what is recorded rather than rolling its own. The round, not the pick, is the wire unit because two of `SkillDustAddon`'s grant paths (single-survivor auto-grant, NPC auto-resolve) never raise a pick. `test/unit/systems/test_loot_wire.gd` pins the grants. `--autopilot`'s loot step only has something to claim if the turn's attacks killed Blue; a surviving opponent logs `SKIPPED`, which is expected.
- **`PickLootCommand`** is a remote human's answer to a parked offer, the one verb built for the upward direction: the applier answers it through `PickLootCommandHandler.apply` against `LootPickRegistry`, not its queue, so it never confirms, is never broadcast back down, and is not watched for refusal.

## The fingerprint

`WorldFingerprint.compute(graph)` folds three sorted tiers: ownership (`stable_id` → owner `entity_id`), topology (edges, endpoints normalized), and accumulated per-node state (stake level, allocation level, regen stacks, HP quantized to int) — never derived `StatBoard` totals, since a fingerprint that moves for reasons the sync layer cannot cause is one nobody reads. `describe()` breaks it down per tier; `compute()` — the number peers compare — is one fold. Two load-bearing properties:

- **It reads every id through `Graph.get_stable_id`,** which forces the lazy mint. Hand-authored nodes read `0` until a topology rebuild, and a command carrying `0` resolves to nothing silently (`.claude/rules/multiplayer-sync.md`); comparing at link-up makes that a visible mismatch.
- **It is folded by hand (FNV-1a), not `Array.hash()`,** because it is compared across processes.

## Two ways to measure the wrong process

A run that looks clean against the wrong peer has no in-band signal: the banner says connected, the probe prints, the totals look plausible. (An orphaned host from a finished session once held port 9099; the fresh host failed to bind, logged it and kept running, and the fresh client reached the orphan.) Two gates close it.

**1. A `--role=host` that cannot bind exits non-zero**, headless and in-editor alike; `--role=solo` is the offline option and `solo`/`client` are untouched. The message names the port and the check (`ps aux | grep mp_dev_sandbox`). **ENet is UDP**, so `ss -ltn` shows nothing for a healthy host; to check the socket rather than the process use `ss -lunp`. Auto-picking a free port is rejected: it masks the conflict and breaks the two-terminal flow where the operator types the client's `--port` by hand.

**2. Peers on different builds refuse to link.** `WorldSyncChannel.send_hello` and the lobby's `NetworkLink.announce_self` carry a `BuildInfo` stamp; a mismatch hangs the link up with both builds printed on both ends. Covered by `test/unit/network/test_link_build_check.gd`; easy to get wrong:

- **The gate runs in the lobby, host-side, per peer.** The client announces its stamp (`KIND_HELLO` with `KEY_BUILD` + `KEY_PEER`) the instant its dial completes and the host answers `peer_cleared` or `peer_refused`. `LobbyScreen` seats on `peer_cleared` and never on bare `peer_joined`, so a refused peer never appears in anyone's roster by wiring, not by memory.
- **After START the door is shut, and the refusal says so.** Joining happens in the lobby before START; there is no drop-in. `NetworkSession._on_peer_joined`'s host branch checks the new peer's id against `GameSession.roster` first and turns a seatless peer away through `NetworkLink.refuse_peer`, ahead of `LobbyScreen.stamp_pending_remote` and the join-world push. Refusing the peer rather than the socket keeps the message truthful (a sealed socket makes ENet reset silently and the joiner sit out its connect timeout).
- **Refusing a peer is not refusing the socket.** `_refuse_peer` sends the reject, then `transport.drop_peer`s that one peer — no latch, no `transport.stop()`, so other seated players keep their link. A refused *client* latches and loses its link. `test_link_lifecycle.gd` states both halves.
- **The stamp rides the hello, never a `Command`.** A per-checkout sha in `Command.to_dict()` would re-capture every `test/fixtures/outcome/` fixture on every commit.
- **An absent stamp is a mismatch; present-but-empty compares equal** (an exported build has no `res://.git`).
- **Only the sha is compared**, strict and right for a LAN pulling one commit; it also refuses over an unrelated uncommitted edit — a loud, diagnosable false positive. Branch and worktree ride along for the message only.
- **Refusal is its own latch, not `role = Role.OFFLINE`**: the role setter writes `is_authority = role != Role.CLIENT`, so parking a refused client at OFFLINE would hand it authority (the hole `mp_dev_sandbox._ready` documents).
- **The stamp catches different commits, not different working trees.** Godot loads scripts at startup, so edit-launch-edit-launch yields a green handshake over divergent code. For a measurement that matters, commit first or launch both at once (the tab's *Launch both* is safe by construction).
- **The reject payload goes out before the hang-up** (`transport.stop()` on a client, `drop_peer()` on a host), because a transport drops a send once the recipient is gone. A host receiving one only reports; it never stops its listener over one bad client.

## The socket stops on every leave

`GameSession.end()` calls `Wire.stop()` (both level exits route through it: `GameRoot.route_to_meta_now`, `PauseMenu.leave_run`); `meta_root._leave_lobby()` nulls `GameSession.network` and stops the wire on both ways out of a lobby (`FrontmatterPanels.panel_dismissed`, a `focus_started` onto a non-lobby leaf). Every route in passes through a teardown, so `_open_wire_for` always (re)opens on the typed endpoint. Client-side loss surfaces on the lobby's status line off `NetworkTransport.link_lost`; `Wire` tears down *before* announcing, so `EnetTransport._on_wire_status` never sees a role about to be wrong.

## A link that ends mid-run

`NetworkSession.open_link` connects `link_lost` and `peer_left`, and the two cases differ:

- **This machine's link died** (`link_lost`): there is no rejoin, so the run is over here. `NetworkSession._on_link_lost` abandons the intent parked in `CommandApplier` (`abandon_pending_intent` — a mirror's `is_awaiting_confirmation` derives from it, and with the authority gone every click would stay gated closed), then raises the run-end overlay with its `LINK_LOST` reading (`HudRoot.present_link_lost`), which already carries the one way out, `route_to_meta_now`. It is not a `RunOutcome`.
- **A seated peer left the host** (`peer_left`, host only): the run goes on. `SeatHandover.hand_seat_to_ai` flips the seat's `Participant.kind` to AI on the host's roster copy first (`LootPickRegistry.is_remote_collector` reads it, and a HUMAN seat with a dead peer would park every relic on a pick nobody sends), swaps its `PlayerController` for an `AIController`, and kicks `take_turn()` by hand if it is that hero's turn. The AI's turns cross the wire as ordinary confirmed commands; mirrors' roster copies still say HUMAN, which only makes their `is_local_collector` answer false.

`test/integration/scenes/test_game_root_link_loss.gd` pins both.

## Two machines

Loopback either connects or errors synchronously; a real LAN adds **silence** (wrong IP, host not up, firewall eating UDP), and ENet's own `connection_failed` takes 15–30 s.

- **`Wire.DIAL_TIMEOUT_SEC` (8 s).** `Wire.start_client` arms a one-shot `Timer`; if nobody answers it tears the dial down and reports `link_lost` with the endpoint in the reason ("no answer from 192.168.1.7:9099"). The lobby shows it and START stays refused. `test_dial_watchdog.gd` pins it, including real time — a closed loopback port produces silence, not a refusal, even on Linux.
- **The join panel's address box starts blank, and blank is refused** (`NetworkConfig.join_address_problem`) rather than falling back to `NetworkConfig.DEFAULT_ADDRESS` (loopback — a joiner who left it alone dialled itself). Loopback typed on purpose still dials; the command-line rungs keep the default.
- **The host's port must be open.** ENet is UDP on `NetworkConfig.DEFAULT_PORT` (**UDP 9099**); a joiner getting "no answer" from a host that is up is almost always this. On Windows the first Host pops a Defender prompt; dismissed, every dial times out. Allow it, or `netsh advfirewall firewall add rule name="Skill Tree of Life" dir=in action=allow protocol=UDP localport=9099`; on Linux `sudo ufw allow 9099/udp` or `firewall-cmd --add-port=9099/udp`. The client side needs nothing.
- **A joiner never sits on a black screen.** `NetworkSession.join_world` ends on `link_lost` / `link_refused` as well as `resync_applied`, lifts the curtain and leaves the run-end overlay's reason on screen (`test_game_root_join_wait.gd`). Re-hosting the lobby's AI-opponent count after a join keeps every stamped `peer_id` and rebroadcasts the shape (`LobbyScreen._rebuild_participants`; `test_lobby_replication.gd`).
- **The wire trace prints on every online run.** On Linux: `~/.local/share/godot/app_userdata/Skill Tree of Life/logs/godot.log`; a report from another machine comes with both machines' files. The rung-3 `FIRST TURN` hook is connected before `_open_link`, since the host's first turn arrives inside the resync (`adopt_turn` fires `turn_started` from within `_on_resync`).

## Extending it

- **A different transport** — subclass `NetworkTransport`; nothing above it knows ENet. `EnetTransport` claims the SceneTree's `MultiplayerAPI` and resolves its one RPC by node path, so both peers need the transport at the same path.
- **A different world** — point the panel's Scene field at any scene whose root handles the same `--role` / `--port` / `--address` args.

## Rung 2: the graph and run settings actually cross the wire

Rung 1 shares one hand-authored scene so no state crosses; any divergence is a messaging bug by construction. Rung 2 (`mp_procgen_sandbox.tscn`) is the first scene where state does cross: the host procgens a small level from a fixed `RunConfig` and the client receives run settings (`WorldSyncChannel.send_run_setup`), then the graph (`send_graph_snapshot`), then every entity's accumulated state (`send_entity_snapshot`).

```
godot --headless --path . scenes/dev/mp_procgen_sandbox.tscn -- --role=host --port=9100
godot --headless --path . scenes/dev/mp_procgen_sandbox.tscn -- --role=client --address=127.0.0.1 --port=9100
```

`--rounds=N` (host only; default 3, bare is unbounded) sweeps N of Red's turns (allocate-if-legal then `end_turn`) — this rung proves the JOIN, not every verb.

**Why this is a correctness requirement.** `procgen/` uses `pow` / `exp` / `sin` / `cos` for continuous placement math whose last bit is not IEEE-754-portable across `libm`s. Two peers "typing the same seed" could generate different maps, and every later command lands on a node that isn't there. Sending the graph rather than regenerating it retires that hazard; `mise run lint-transcendentals`'s `procgen/` exemption says so and self-voids if a peer ever generates from the seed again.

- **No hot-seat, unlike rung 1.** Both peers are pinned with `SeatPolicy.seat()` to their own participant (host → Red, client → Blue) and never swing — a client staying on Blue is a wanted difference, not a divergence. Only the authority's `AIController` decides Blue, gated by `CommandApplier.is_authority`.
- **The client never calls `GraphProcgen`.** It spawns bare placeholder `Entity` nodes (no `core_location`) in the same order as the host, so `Graph`'s per-entry `entity_id` minting lands on identical numbers. It waits for `GameSession.run_started` (fired by `GameSession.apply_received`, called from `WorldSyncChannel._on_run_setup`) to learn the participant count; `GraphSnapshot.decode` resolves ownership through the receiving graph's entities, so the placeholders must already exist and be correctly ID'd.
- **`core_location` and the receiving board ride `EntitySnapshot`.** `GraphSnapshot` carries which entity owns each node but rebuilds nothing on the owner's side; a client whose board never got the starting node's grants shows wrong HP/stats from its first frame. `send_entity_snapshot` decorates the entities the roster spawned (and, for blockers no roster names, rebuilds them via `entity_spawner`); its two-pass decode resolves `core_location` (pass 1 needs no graph, pass 2 runs once a graph exists). Snapshot order does not matter; both passes are idempotent.
- **Send order: run_setup, graph snapshot, entity snapshot, THEN hello** — reversed from rung 1. `send_hello` produces the "✓ in sync at link-up" verdict by comparing `WorldFingerprint`, and the client's graph is empty until the snapshots decode; hello first would report a false structural DIVERGED. ENet's reliable channel is ordered, so everything sent before hello arrives before it. Accepted consequence: `KIND_SETUP` / `KIND_SNAPSHOT` / `KIND_ENTITIES` are handled regardless of a prior hello, so a build mismatch is not caught until after they apply.
- **This harness is its own composer**, one of two exceptions to "a level consumes a run, it never invents one": it opens the session itself (`GameSession.ensure_started`) and writes the roster because the run it builds is what it SENDS. The other exception is the client half, which receives its run from the host.
- **The opening turn starts AFTER the send.** `TurnManager.start_turn` fires `turn_started` and runs turn-start upkeep (AP/DP/SP/wound-heal/node-refill). Starting the host's opening turn before sending bakes an already-healed world into the snapshot, and the client's own `start_turn` (load-bearing: it sets `current_entity` so a mirrored `EndTurnCommand` isn't a no-op) heals it a second time. `mp_procgen_sandbox.gd` defers the host's `_start_opening_turn()` to `_greet_if_linked_and_ready`, after every send.
- **Automated coverage stops at the protocol.** `test/integration/network/test_mp_procgen_join.gd` drives two real `game_root.tscn` instances in one process over their mounted loopback transport. It pins ownership + topology + HP after the handshake, `core_location` via `EntitySnapshot`, distinct participant binding per instance, and fingerprint parity across a scripted sequence of mirrored commands. It deliberately does not exercise `EndTurnCommand`: `TurnManager.end_turn` and `_tick_until_ready` read `Entity.GROUP` / `Entity.READY_GROUP` tree-wide, so two worlds in one SceneTree see each other's entities. A real multi-turn run is manual (the Multiplayer tab).

## Rung 3: the REAL lobby, driven from the command line

Rung 3 is not a scene: it drives the shipped menu, so what it proves is the product's own route.

```
godot --headless --path . -- --lobby=host --port=9300
godot --headless --path . -- --lobby=client --address=127.0.0.1 --port=9300
```

`run/main_scene` is `scenes/meta/meta_root.tscn`, so both processes boot the frontmatter menu as an exported build does; nothing is stubbed. `MetaRoot._drive_lobby_from_cmdline` reads `--lobby=host|client`, `--address`, `--port` and presses the same buttons a human would: the host walks its HOST leaf, waits for a peer, and presses START (`MetaRoot._press_start_when_seated` → `LobbyScreen._on_start_button_pressed`, after one deferred hop so `_on_link_peer_joined` has stamped the waiting seat); the client walks JOIN and is routed by the broadcast that follows.

**What it proves that rung 2 cannot:** the live two-process behaviour of the menu-opened socket, of the level adopting that socket, and of a join with no peer running procgen.

**The verdict line is `MpHarness._announce_first_turn_for_rung_3`**, printed once per process on `turn_started` (a client that decoded a world and never got a turn has not proved the thing), beside `WorldFingerprint.describe`. Green means both print the same `fp` at their first turn.

**Both halves read nothing by default.** The flags are scanned through `HarnessFlags` (`network/harness_flags.gd`: `LOBBY`, `ADDRESS`, `PORT`, `AUTOPLAY`, `LETHAL`, `MAX_TURNS`, `AI_DELAY`); `MetaRoot` and `MpHarness` return immediately when `--lobby` is absent, so an ordinary launch, an exported build and every test parse no arguments.

## Rung 4: the run plays itself, and the two processes are compared

Rung 4 keeps rung 3's two processes going to a **verdict** — the wire's automated coverage past turn one:

```
mise run mp:e2e                     # spawn, play, compare
mise run mp:e2e -- --max-turns 80   # entity-turns, not rounds
mise run mp:e2e -- --no-lethal      # normal stats: a long game, may outrun --timeout
```

`.mise/tasks/mp/e2e` spawns rung 3's command line plus `--autoplay`:

```
godot --headless --path . -- --lobby=host   --port=9412 --autoplay
godot --headless --path . -- --lobby=client --address=127.0.0.1 --port=9412 --autoplay
```

- **Lethal by default.** Both processes get `--lethal`: four `SET` modifiers on every entity (`MpHarness._LETHAL_SETS`: `node_health` 1, `health` 3, `dealloc_damage` 1, `core_healing` 0), so each entity survives about three node losses. A normal-stats run lasts as long as its seed decides and can outrun the 180 s default — a game length, not a failure; `--no-lethal` plays that game.
- **`--autoplay` is the host handing every human seat to the AI.** At the first `turn_started`, `MpHarness._autoplay_every_human_seat` calls `SeatHandover.hand_seat_to_ai` on every `Participant.Kind.HUMAN` (the peer-left primitive, so the handover is broadcast and the mirror's roster learns the seat is the AI's). It suppresses exactly one thing on both peers (`SeatHandover.quiet`, riding `seat_handed_over`): the "somebody left" announcement. The client acts on nothing — a second AI deciding locally is the divergence this run exists to detect; the flag reaches it for the zero AI turn delay and its verdict line.
- **The small preset is pressed on the same rows a human would.** `MetaRoot._apply_autoplay_preset` picks the smallest Map size rung and sets AI opponents to zero through `LobbyScreen.pick_option` / `set_ai_opponents` (public doors that move the widget and record the pick, so `build_run_config` sees a real override). It is applied **before anybody joins**, because changing the AI count rebuilds the roster and every rebuilt remote seat is born back on `_PENDING_PEER_ID`, discarding the peer id the host waited for. It is the first lobby override to cross a real socket.
- **Both ends print one greppable line and quit:** `RUNG4 VERDICT — winner=<camp id> | turns=<n> | <fingerprint>` on `Events.run_ended`, synchronously (routing tears the graph down after `run_end_route_delay`, so a later fingerprint would describe a vanished world). A run that cannot end spends its `--max-turns` budget (default 400 *entity*-turns; `TurnManager.turns_taken` counts each entity's turn) and prints `RUNG4 TIMEOUT`, exit **2**, so the task tells "never ended" from "fell over".

**What `mp:e2e` asserts** — six lines, not one fingerprint compare: both processes exit 0 · both printed a verdict · same winner and turn count · same first-turn fingerprint · **no mid-run divergence** · same run-end fingerprint. The fifth is the one a naive compare misses: the host force-overwrites the mirror with a whole snapshot whenever it finds divergence, so two peers that disagree every turn still end up holding similar worlds. **A repaired run is not a synced run**; the count of `✗ DIVERGED` lines in the client log says so (the one at link-up is excluded — a joining client holds no world). It does not cover the platform: same binary, same libm, one machine (#665).

**Two rules the mirror lives by**, both found when the first run reported 15–40 force-repairs per run:

- **The mirror never starts a turn on its own; the cursor is received** — first as a `StartTurnCommand`, then inside every resync. `GameRoot._ready` must not open the first turn on the local seated hero on every peer, or each later `EndTurnCommand` reproduces `_tick_until_ready` from a different cursor and turn-start upkeep runs for the wrong entity.
- **A peer that decoded a world reconciles what the decode bypassed.** `GraphSnapshot._decode_node` assigns `owned_by` directly (a snapshot is a world, not a sequence of moves), the write `EntityNavigator`'s mutation contract says drifts the mirror; `Entity.begin_turn` runs the D-9 regen sweep over `navigator.get_mirrored_nodes()`, so a node missing from the mirror never heals there.

**The divergence check runs on the mirror's own stamp.** The host's stamp travels as the transient `Command.host_fingerprint` (never in `to_dict` — see `Command.pre_fingerprint` for why the outcome fixtures forbid it) and is compared at the mirror's `pre_fingerprint` stamp inside `CommandApplier._drain`, where no world is unsettled. Nothing is skipped, and the first `✗` names the first command that actually disagreed.

## The other harness

Replaying a recorded attack with no network, to separate replay bugs from messaging bugs: `docs/domain/outcome-fixtures.md`.
