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
| The scene both processes run — rung 1 | `scenes/dev/mp_dev_sandbox.tscn` (inherits `dev_sandbox.tscn`) |
| The scene both processes run — rung 2 (#533) | `scenes/dev/mp_procgen_sandbox.tscn` (instances `game_root.tscn`) |
| Where the wire is MOUNTED | `scenes/game_root.tscn` → `Transport` + `CommandLink` (#531) |
| Transport seam | `network/network_transport.gd` + `enet_transport.gd` / `loopback_transport.gd` |
| Applier ↔ transport bridge | `network/command_link.gd` |
| Divergence detector | `network/world_fingerprint.gd` |
| Determinism probe (#529) | `network/determinism_probe.gd` |

From a terminal, no editor needed:

```
godot --headless --path . scenes/dev/mp_dev_sandbox.tscn -- --role=host --port=9099 --autopilot
godot --headless --path . scenes/dev/mp_dev_sandbox.tscn -- --role=client --address=127.0.0.1 --port=9099 --autopilot
```

**`--autopilot` goes on BOTH lines even though only the host sweeps** — see
below. Drop it from either and Red's boosted budget stops matching across the
wire; drop it from both and you get a plain hand-driven sandbox, which is the
right thing to launch when you want to *play* the pair.

`--turns=N` (host only, #529) sweeps N of Red's turns instead of one, hooked on
`TurnManager.turn_started` — Blue's AI takes a real turn in between, so the
signal is what knows when the loop comes back around. One sweep is ~17
commands, which is a demo; the probe needs a few hundred before "0 diverged"
means anything. Bare `--turns` runs until the process is killed. The default
stays one, so #532's single-pass proof is unchanged.

`--probe` (client only, #529) arms the determinism probe: the mirroring peer
additionally re-resolves each received `launch_attack` locally and tallies, per
command type, whether it could have *derived* what the host sent. It mutates
nothing and changes nothing about what the client applies. Full scope — what it
compares, what it deliberately does not, and why `skipped` is a finding rather
than a pass — in [determinism-probe.md](determinism-probe.md).

`--autopilot` (#532) drives every verb `CommandApplier` handles from Red's
opening turn — allocate, mass_allocate, stake/extract, deallocate,
deallocate_set, move_core, all three attack modes, a temp-upgrade toggle, a
loot claim (when there is one to claim), then end_turn — one line of log per
verb on each side. A verb that cannot legally fire this turn logs SKIPPED with
the reason rather than being silently dropped. Everything after `--` lands in
`OS.get_cmdline_user_args()`; put it before and the engine tries to interpret
it.

**Pass it to both peers, unlike every other flag here.** Only the authority ever
sweeps (`_start_sweep_if_due` gates on `CommandApplier.is_authority`, so the
client's copy boosts and then sits still), but the flag *also* gates the budget
boost `_boost_autopilot_budget` puts on Red — 30 SP / 12 AP / 10 DP / 200 mana,
because one turn on a level-1 board (3 SP / 2 AP / 3 DP / 10 mana) cannot pay
for the whole sweep. That boost must be identical on every peer:
`CommandApplier._apply_mass_allocate` re-derives affordability from the
*receiving* peer's own board (#458), so a host-only boost desyncs the first
budget-gated verb that crosses.

**And the flag is the whole gate — no flag, no boost.** It used to run
unconditionally, so a plain launch from the Multiplayer tab handed a human a
Red with 30 skill points and 200 mana and read as a stat-system bug. If you are
launching the pair to *play* it, leave the toggle off and Red is an ordinary
level-1 board.

## The mount, and why a level may only SWAP it (#531)

`Transport` and `CommandLink` are direct children of `GameRoot`, so every level
inherits them at the same two node paths. That is not tidiness: Godot's
high-level multiplayer resolves an RPC **by node path**, so two peers running
different scenes only reach each other if the transport sits in the same place
in both. Mounting it in the composition root is what makes that true by
construction instead of by convention.

Three consequences, in the order they bite:

- **The default is `LoopbackTransport`, and the link is mounted `Mode.OFF`.**
  Mounted and inert — nothing is serialized, nothing is sent, so single-player
  is unchanged. A role raises the mode; the mount never does.
- **A level that wants a real socket overrides that node's SCRIPT.** An
  inherited-node property override in the `.tscn`, exactly like any other:
  ```
  [node name="Transport" parent="."]
  script = ExtResource("3_transport")   # enet_transport.gd
  ```
  `mp_dev_sandbox.tscn` does this, and so does `first_level_sandbox.tscn` — the
  level the menu routes to, which would otherwise be asked to host over a
  loopback and link to nobody.
- **Never author a SECOND pair.** Before #531 the harness authored its own
  `Transport` / `CommandLink`; once the pair is inherited, doing that gives you
  colliding sibling names and `$Transport` resolves to whichever one Godot
  renamed last — a dead link with no error anywhere.
  `test/unit/network/test_link_mount.gd` asserts the *count*, not just the
  type, for exactly this reason.

Which role this machine takes is `NetworkConfig` on `GameSession` — the
per-machine half of a run's setup, alongside `SeatPolicy` and deliberately not
on `RunConfig`, which crosses the wire by value (`docs/domain/seat-policy.md`
has the same argument for the same reason). `GameRoot` reads it once: the role
is adopted at the top of `_ready` (before anything can act and diverge), the
socket opens after `_setup_level` (so an arriving command finds a world).

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

## Two ways to measure the wrong process (#546)

The harness exists to produce numbers that settle arguments — #529's probe
decides a sync model *by measurement instead of argument*. So the one failure
mode that matters more than a crash is a run that looks clean and is measured
against the wrong peer. There is no in-band signal for it: the banner says
connected, the probe prints, the totals look plausible.

It happened on 2026-08-23, during #534's acceptance sweep. An orphaned host
from a finished session — hours old, running `dc5ef29`-era code — still held
port 9099. The fresh host failed to bind, **logged it and kept running**, and
the fresh client dialled 9099 and reached the *orphan*, which happily accepted
it and began sweeping. The run compared a months-old host against a
current-master client. It was caught only because the stale process's
backtraces named line numbers `command_applier.gd` no longer has.

Two independent gates now close that:

**1. A `--role=host` that cannot bind exits non-zero.** Binding *is* the job of
`--role=host`; without a socket it is a solo sandbox nobody asked for, and
`--role=solo` already exists for that. Identical headless and in-editor — the
in-editor path is the one that otherwise keeps running in the exact shape that
caused the incident. `solo` and `client` are untouched. The message is the
deliverable, not the exit code, so it names the port and the check:

```
[host] host: FAILED to listen on 9099 (Can't create)
[host] port 9099 is already in use (Can't create) — another harness may still be running:
[host]          ps aux | grep mp_dev_sandbox
[host] a host with no socket is not a host — exiting. (--role=solo runs offline.)
```

Finding the culprit is `ps aux | grep mp_dev_sandbox`, and that is deliberate:
**ENet is UDP**, so `ss -ltn` (TCP) shows nothing for a perfectly healthy host.
A sweep script that checked TCP produced a false "host did not bind" abort on
2026-08-24. If you must check the socket rather than the process, it is
`ss -lunp`.

Rejected: **auto-picking a free port.** It masks the conflict, and it breaks the
documented two-terminal flow outright — the operator types the client's `--port`
by hand and would land on the stale host anyway. The false-positive cost of
fail-fast is a two-second relaunch; the false-negative cost is a clean-looking
table posted to an issue as fact.

**2. Peers on different builds refuse to link.** The fatal bind closes one route
to a wrong-host link; a stale process on another machine, a mistyped IP, or
someone else's session on the same LAN are others. `CommandLink.send_hello`
carries a `BuildInfo` stamp, the receiver compares it, and a mismatch hangs the
link up with both builds printed on both ends:

```
[client] link REFUSED — build mismatch
[client]   peer:   4174f36 (master)
[client]   mine:   54cfcd7 (master @ issue-546-…)
[client] The peers are not running the same code.
```

Details that are easy to get wrong, all covered by
`test/unit/network/test_link_build_check.gd`:

- **The stamp rides the hello, never a `Command`.** The hello is what brings a
  link up today, so nothing in the harness can link without the check running.
  (`KIND_SNAPSHOT` / `KIND_SETUP` are handled regardless of a prior hello, so a
  future #531 lobby that sends a snapshot *first* would want the gate moved
  ahead of it.) A per-checkout sha inside `Command.to_dict()` would re-capture
  every fixture at `test/fixtures/outcome/` on every commit.
- **An absent stamp is a mismatch, not a pass.** The orphan predates the check
  and sends no build key at all — treating that as agreement would sail past the
  one run this was written for. *Present-but-empty* is different and does
  compare equal: an exported build has no `res://.git` and so no sha.
- **Only the sha is compared.** Strictest, and correct for a LAN where everyone
  pulls the same commit. It also refuses when one side has an unrelated
  uncommitted edit — a loud, instantly diagnosable false positive, which is the
  opposite of the failure being killed. Branch and worktree ride along for the
  message only.
- **Refusal is its own latch, not `mode = Mode.OFF`.** The `mode` setter writes
  `is_authority = value != Mode.MIRROR`, so parking a refused *client* at OFF
  hands it authority — the silent-divergence hole `mp_dev_sandbox._ready`
  documents. A refused link goes quiet; it does not become an authority.
- **The stamp catches different commits, not different working trees.** Godot
  loads scripts at startup, so the staggered terminal flow — edit, launch host,
  edit, launch client — gets a green handshake over genuinely divergent code,
  both processes reporting the same sha. That is this same failure class
  arriving through the front door, and a dirty-tree marker would not close it
  (dirty-vs-dirty is an equally silent pass). **For a measurement that matters,
  commit first, or launch both at once.** The Multiplayer tab's *Launch both* is
  safe by construction; the two-terminal path is the exposed one.
- **The reject payload goes out before `transport.stop()`.** A transport drops a
  send once it is no longer linked, so that order is what makes the *other* end
  print anything. The receiving side then only *reports* — it does not stop or
  latch, or a host would close its listening socket over one bad client and the
  operator would relaunch the fixed client into nothing.

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

## Rung 2: the graph and run settings actually cross the wire (#533)

Rung 1's whole value is that NO state crosses — the two peers share the same
hand-authored `dev_sandbox.tscn`, so any divergence there is a *messaging* bug
by construction, never a serialization one. Rung 2 (`scenes/dev/mp_procgen_sandbox.tscn`
+ `.gd`) is the first harness scene where that stops being true: the HOST
procgens a small level from a fixed `RunConfig`, and the CLIENT receives it —
run settings first (#528, `CommandLink.send_run_setup`), then the graph
(#527, `CommandLink.send_graph_snapshot`), then every entity's accumulated
state (#560, `CommandLink.send_entity_snapshot`) — rather than re-deriving any
of it locally. Launch it the same way as rung 1, over `--role` / `--port` /
`--address`:

```
godot --headless --path . scenes/dev/mp_procgen_sandbox.tscn -- --role=host --port=9100
godot --headless --path . scenes/dev/mp_procgen_sandbox.tscn -- --role=client --address=127.0.0.1 --port=9100
```

`--rounds=N` (host only; bare `--rounds` is unbounded) sweeps N of Red's turns,
each an allocate-if-legal followed by `end_turn` — a much smaller sweep than
rung 1's `--autopilot`, because this rung's job is proving the JOIN, not
re-proving every verb crosses (rung 1 already does that). The default is 3.

**Why this is now a correctness requirement, not only a harness milestone
(#547).** `procgen/` leans on `pow` / `exp` / `sin` / `cos` for continuous
placement math — draw weights, a Poisson roll, a Gaussian bump, points on a
circle — real math that would be wrong to rewrite, but whose last bit is not
IEEE-754-portable across platforms' `libm`. Two peers "typing the same seed"
(`HostJoinScreen`'s current lobby hint) can silently generate DIFFERENT maps,
and every command after that lands on a node that isn't there — not subtle
drift, the run failing to start coherently. Sending the graph rather than
regenerating it retires that hazard permanently; `mise run lint-transcendentals`'s
`procgen/` exemption says so explicitly and self-voids if a peer ever goes back
to generating its own map from the seed.

**No hot-seat, unlike rung 1.** Rung 1's HOST hot-seats a human Red against an
AI Blue (`COUCH`); here BOTH peers are pinned with `SeatPolicy.seat()` to their
own participant — host → Red, client → Blue — and never swing, per the owner's
framing (2026-08-22): a client staying bound to Blue through every handover is
a WANTED difference between the two instances, not a divergence to chase. Blue
is still AI-driven and the run still needs no upward intent channel (#463,
unfiled rung 3) — only the authority's `AIController` ever decides, gated by
`CommandApplier.is_authority` exactly as rung 1 documents at length.

**The CLIENT never calls `GraphProcgen`.** It spawns bare placeholder
`Entity` nodes — no `core_location`, so no graph is needed yet — in the SAME
order the host does, so `Graph`'s per-entry `entity_id` minting lands on the
identical numbers. It waits for `GameSession.run_started` (fired by
`GameSession.apply_received`, which `CommandLink._on_run_setup` calls) before
it knows how many participants there are; only once the graph snapshot itself
arrives can ownership resolve — `GraphSnapshot.decode`'s own contract is that
ownership resolves through the RECEIVING graph's entities, so the placeholders
must already exist and be correctly ID'd first.

**`core_location` and the receiving board ride `EntitySnapshot` (#560), which
landed alongside this rung.** `GraphSnapshot` carries which `Entity` owns each
`SkillNode` (by `entity_id`) but rebuilds nothing on the OWNER's side —
#560's own framing: a client whose board never got the starting node's grants
shows the wrong HP/stats from its first frame, silently. `CommandLink
.send_entity_snapshot` is the sibling send this rung also makes: it DECORATES
the entities the roster already spawned (never mints one — #560 D7), and its
own two-pass decode is what resolves `core_location` — pass 1 needs no graph,
pass 2 (entity → node) runs once a graph exists to resolve against. Order
between the graph and entity snapshots does not matter (both passes are
idempotent).

**Send order: run_setup, graph snapshot, entity snapshot, THEN hello —
reversed (and extended) from rung 1.** `CommandLink.send_hello` is what
produces the "✓ in sync at link-up" verdict, comparing `WorldFingerprint` on
both sides, and the CLIENT's graph is empty until the snapshots decode.
Sending hello first (rung 1's order, safe there because both peers already
share a graph) would report a structural, false DIVERGED before any real
state could differ. Sending it last makes "at link-up" mean what it says —
ENet's reliable channel is ordered, so every send before hello arrives before
it does. One accepted consequence, already called out in `command_link.gd`'s
own #546 note: `KIND_SETUP` / `KIND_SNAPSHOT` / `KIND_ENTITIES` are all
handled regardless of a prior hello, so a build mismatch is not caught until
after every one of them has already been applied. That gap is pre-existing
future work, not something this rung closes.

**The opening turn starts AFTER the send, not before — a double-heal trap
this rung's own test caught.** `TurnManager.start_turn` unconditionally fires
`turn_started`, which runs turn-start upkeep (AP/DP/SP/mana/wound-heal/
node-refill). Rung 1 calls it identically on both peers because its graph is
hand-authored and never crosses the wire — both sides start from the SAME
untouched baseline. Here the graph and entity state DO cross: starting the
HOST's opening turn before sending bakes an ALREADY-healed world into the
snapshot, and the CLIENT's own `start_turn` call — load-bearing on its own,
since it's what sets `current_entity` so a later mirrored `EndTurnCommand`
isn't a silent no-op — then heals it a SECOND time on top, unaccounted for by
anything that actually crossed the wire. `mp_procgen_sandbox.gd` defers the
HOST's `_start_opening_turn()` call to `_greet_if_linked_and_ready`, after
every send, so both peers' upkeep applies exactly once, from the identical
pre-turn baseline — the fingerprint mismatch this produced (accumulated HP
off by the wound-heal amount, ownership and topology both fine) is what
surfaced it while writing `test_mp_procgen_join.gd`.

**Automated coverage stops at the protocol, not the scene.** Two full OS
processes can't share a `LoopbackTransport` (the earlier reasoning still
holds: `EnetTransport` claims the SceneTree's one `MultiplayerAPI`), so
`test/unit/network/test_mp_procgen_join.gd` drives two real `game_root.tscn`
instances in one process instead, paired through their own mounted default
transport — the same two-worlds-in-one-process technique
`test_command_link.gd` already established, extended to also exercise
`send_run_setup` / `send_graph_snapshot` / `send_entity_snapshot`. It pins:
ownership + topology + HP match once the join handshake completes,
`core_location` resolves via `EntitySnapshot`, each instance ends up bound to
a different participant (asserted as correct), and fingerprint parity
survives a short scripted SEQUENCE of mirrored commands — the last of those
is what caught the opening-turn double-heal above; it started out red for
exactly the reason described there. It deliberately does NOT exercise `EndTurnCommand` — both
`TurnManager.end_turn` and `_tick_until_ready` read `Entity.GROUP` /
`Entity.READY_GROUP` tree-wide, so with two worlds sharing one SceneTree they
see BOTH worlds' entities regardless of which `TurnManager` is ticking; a real
multi-turn run is exercised manually via the Multiplayer tab, same division of
labour as rung 1's own test coverage (`test_harness_budget_boost.gd` tests
`build_args`, not a spawned process).

## The other harness: replaying an outcome with no network (#539)

The two-process harness proves *host acts → client mirrors*, which means every
failure it reports has two candidate causes: the replay path, or the messaging.
The **Outcome playground** tab (`addons/outcome_playground/`) removes the second
one. It replays a recorded attack against a local `CommandApplier` with **no
`CommandLink` attached** — byte-for-byte the peer path, minus the wire. If a
recorded outcome plays back correctly there, anything still broken over ENet is
a messaging bug and cannot be a replay bug.

The unit of replay is one serialized `LaunchAttackCommand` — `plan` + `record` +
`seed`, exactly what crosses. An `OutcomeFixture`
(`attack/outcome/outcome_fixture.gd`) is that dictionary on disk, plus the
`WorldFingerprint` before and after, plus a note. Fixtures are **captured, never
authored**: a captured one proves the applier reproduces what the game did,
while an authored one would only prove it applies what somebody typed.

**The world is not in the fixture — it is rebuilt from code.** A record names
nodes by `stable_id` and its attacker by `entity_id`, and both mint from
per-`Graph` counters walking container child order, so a fixture only replays
into a world reproduced identically. `scenes/dev/outcome_playground_world.gd` is
that one builder, called by both the tab and the headless test; the alternative
(a `.tscn` plus a copy of "now arm it" on each side) is exactly where the two
drift apart. `test_outcome_fixture_replay.gd` pins the assumption directly: two
builds must mint the same ids.

**A red fixture says which half broke.** A mismatched
`world_fingerprint_at_capture` means the *builder* drifted — regenerate. A
matching pre-state with a diverged `expected_fingerprint` means the *replay path*
changed, which is the failure worth waking up for. Regenerate — never hand-edit —
with:

```
REGEN_OUTCOME_FIXTURE=1 mise run test:one -- \
    res://test/unit/attack/test_outcome_fixture_replay.gd
```

That captures a live attack in the same headless context and rewrites the
`.tres` the tab's Save button writes, so the two authoring paths cannot become
two formats. Read the diff before committing it. **A missing fixture is a
failure, never a silent re-capture** — a test that captured its own golden when
it could not find one would pass on every machine forever while asserting
nothing.

One thing the current fixture does not exercise: every amount in
`spark_cascade.tres` is integral (`h_amt: 9999`, `h_hp0: 10`, `d_chip: 1`), so
whether a text resource round-trips `AttackRecord`'s `PackedFloat64Array`
amounts exactly is **untested**. Those are float64 precisely because a peer's HP
must land on the host's number, so the first fixture whose amount comes back
mitigated or crit-multiplied is where a formatting loss would surface. If one
does, the fix is a binary `.res`, not a change of format.
