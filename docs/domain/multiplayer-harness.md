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

`--autopilot` (host only, #532) drives every verb `CommandApplier` handles from
Red's opening turn — allocate, mass_allocate, stake/extract, deallocate,
deallocate_set, move_core, all three attack modes, a temp-upgrade toggle, a
loot claim (when there is one to claim), then end_turn — one line of log per
verb on each side. A verb that cannot legally fire this turn logs SKIPPED with
the reason rather than being silently dropped. Everything after `--` lands in
`OS.get_cmdline_user_args()`; put it before and the engine tries to interpret
it.

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

`mp_dev_sandbox.gd` changes two things about the base scene:

1. **The client binds Blue and freezes input** via `set_input_frozen` (#486) —
   the existing "every channel off" seam, no controller change needed.
2. **The client drops the hot-seat handover.** On a networked peer the local
   view is fixed to the local hero; leaving it connected would swing the
   client's HUD onto Red.

**Blue stays the AI opponent (#532).** The old justification for making it
human — "the AI still calls `AllocationSystem` / `BattleSystem` directly" — is
stale: #512 landed, and `AIController` emits commands through `CommandApplier`
like everything else, so restoring the AI keeps every mutation on the mirrored
path just as well, and turns the harness into a player-against-an-opponent
rather than two humans hot-seated. Restoring it exposes a real trap:
`GameRoot._ensure_controllers` attaches an `AIController` to Blue on BOTH
peers, and that controller resolves *its own peer's* `CommandApplier` — so a
MIRROR peer's copy would decide and submit independently of the host's AI the
instant a mirrored `EndTurnCommand` hands Blue the turn locally. Closed by
gating `AIController.take_turn` on `CommandApplier.is_authority`
(`network/command_link.gd`'s `mode` setter is the only writer) — the same "a
non-authority peer does not originate mutations" invariant `SkillDustAddon`'s
claim flow already relies on. The host hot-seats between Red and Blue; the
client stays bound to Blue.

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
than re-resolving. `--autopilot` fires all three modes (#532: melee included,
scored via `AiBladeRollout` — the same rollout `AIController` uses, so it never
needs arc geometry hand-authored into the scene). **Read every `✓` carefully:**
as of #527 the fingerprint folds ownership + topology + accumulated per-node
state (HP included, quantized), so a cast that damages without killing DOES
move it now — but never derived `StatBoard` totals (AP, mana, aura
contributions), which stay outside the fold on purpose. What the
`← launch_attack` line proves is that the command decoded and applied on the
client at all; the *effects* are pinned by
`test/unit/attack/test_attack_record_replay.gd`, which compares node HP, AP and
mana across two real worlds through the same wire encoding.

**Also does:** loot, since #522. Each round of a relic's claim rides down as a
`LootRoundCommand` carrying what was granted BY VALUE — the same
two-states-one-type shape as the attack, so a peer grants what is recorded
rather than rolling its own. The ROUND is the wire unit rather than the pick
because two of `SkillDustAddon`'s grant paths (the single-survivor auto-grant
and the NPC auto-resolve) never raise a pick at all; a `PickLootCommand`-shaped
vocabulary would have left every NPC claim diverging while the human-pick case
looked fine. A grant that moves node HP or ownership now moves the fold too (#527); one
that only touches a stat total (e.g. a pure damage-formula modifier) still
does not — `test/unit/systems/test_loot_wire.gd` is what pins the grants
directly, the same division of labour as the attack path above.
`--autopilot`'s loot step only has something to claim if the turn's three
attacks actually killed Blue — this hand-authored graph seeds no relic, and a
default-balanced opponent surviving three hits is the expected, honestly
logged (`SKIPPED`) outcome, not a bug.

**Does not:** anything travelling UPWARD. `PickLootCommand` is the one verb
built for that direction — a remote human's answer to a parked offer — and it is
dormant rather than unrouted: `CommandApplier` answers it for real against
`LootPickRegistry`, but `MIRROR` never sends and the client's input is frozen.
#463 owns the channel and the roster that says which peer seats which entity.

## The fingerprint

`WorldFingerprint.compute(graph)` folds three sorted tiers (#527): ownership
(`stable_id` → owner `entity_id`), topology (edges, endpoints normalized), and
accumulated per-node state (stake level, allocation level, regen stacks, HP
quantized to int). Not derived `StatBoard` totals: a fingerprint that moves
for reasons the sync layer cannot cause is one nobody reads. `describe()`
breaks the fold down per-tier for diagnostics, but `compute()` — the number
peers actually compare — is one fold, not three.

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
