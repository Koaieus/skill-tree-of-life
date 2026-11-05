# Network session and command channel

Join handshake and channel details, moved out of source comments. The sync model itself is multiplayer-sync-model.md.

## Joining: the opening step and the resync wait (`network/network_session.gd`)

The whole join-or-host step, called by the root once its world is built —
after `_setup_level` and the HUD compose, before the run is armed. `true`
when there is a world to play on: at once for offline and host, and for a
client once the authority's world has landed; `false` when a client's link
ended first (refused, or the host went away), in which case the root
presents that and stops.

EVERY role opens here, and the reason the host and offline always
did is finally the reason on the joining side too: opening after
`_setup_level` means a command arriving the instant the link comes up finds
a world to apply to. Split from `adopt_role` because the role has to
be known far earlier than the socket may open.

**The drop latch** spans the ONE round trip between adopting the link and the resync
landing: this peer's world is empty until the pull answers, and a
`KIND_COMMAND` that arrives meanwhile would apply against nothing.
The latch is what makes the window safe rather
than merely short, because `apply_remote` enqueues and drains AT ONCE
against whatever world is there. If the command's ids do not resolve,
`CommandApplier._validate` warns and DROPS it. If they DO resolve, nothing
warns at all and it lands on whatever node happens to carry that
`stable_id`. Silence here is not evidence that nothing went wrong.

Either way it is survivable for exactly one reason: `pull_host_world`
asks the authority for its whole world, and the reply carries the
authority's whole state, superseding both shapes above — what this peer
missed and what it misapplied alike. Ordering makes it airtight rather than
probable — `Wire._receive` is an `@rpc(..., "reliable")`, so it is ordered
as well as delivered: the host encodes the resync when the request arrives,
and anything it applies after that is sent after the envelope and lands on
top of it. Nothing this window swallowed can outlive the pull.

So the gate is not a buffer, it is the repair — and the pull must stay
immediately after the link is up. Moving it later (behind a fade, an await,
a turn start) reopens the hole this comment is about.

Then WAIT for the answer, on the joining side only. A client has no world of its own: its graph is empty until the resync lands, and
arming `VictorySystem`, starting a turn or lifting the curtain over nothing
is not "a bit early", it is a level with no map. This wait IS what the
client's loading bar has been covering since `_setup_level` — the host's
generate and ship, rather than this machine's own procgen.

Unbounded for the world, and bounded by the LINK. The run-end overlay is a
layer-100 canvas and `SceneTransition` sits at 101, so a presented overlay
would sit UNDER the curtain; the wait must end the moment the link does.
timeout. The wait ends the moment the link does, and the curtain lifts
on the overlay that says why. While it waits, it re-asks for the world
every `join_pull_retry_sec` rather than trusting one ask.

## Joining client gets its world by resync pull (`network/network_session.gd`)

#463/#715: how a joining client gets a world at all. It does not generate one
— it asks the authority for the serialized one, through the `WorldSyncChannel.KIND_RESYNC` envelope #561 already ships: entities, graph, then
the entity->node pass, in one message.

**#715 made this the ONLY way a client gets a map, and that closed a
window.** Until then the client generated from the host's seed and pulled on
top, because generating from a seed is not the same as playing the host's map
(`procgen/` leans on transcendentals whose last bit is not portable across two
platforms' libm, #547). So there was a period where the link was up and a
WRONG world was present. There is no longer: the client builds nothing, and
`#689`/`#706`'s `pow()` in the seeded draw leaves the LAN critical path with
it, because nothing on this machine re-derives the map.

**A pull, not a push, and that is the whole ordering answer.** A push
races the level's own construction — over a loopback it lands INSIDE
`_on_run_setup`, before the level has spawned anything at all. Asking once
the level is built has no such window, and needs no upward "I am ready"
message: `WorldSyncChannel.request_resync` IS that message.

**The reply's internal order is load-bearing, and it serves BOTH shapes.**
`WorldSyncChannel._on_resync` decodes entities, decodes the graph, THEN
resolves the entity->node refs. On the join path the graph is EMPTY, which is
the #533 harness's old odd case and is now the primary one. On a mid-run
repair (#521/#560/#561) it is POPULATED, and the order is what stops
`EntitySnapshot.resolve_graph_refs` resolving every `core_location`
against nodes `GraphSnapshot.decode` is about to delete. One order,
both shapes — which is the reason this is a resync pull and not the two
pushed snapshots `scenes/dev/mp_procgen_sandbox.gd` sends in the opposite
order. Anyone "fixing" this to match the harness's order will reintroduce the
bug; `test_graph_snapshot.gd` pins both shapes.

## CommandChannel (`network/command_channel.gd`)

Bridges one `CommandApplier` to a `NetworkLink`: the host broadcasts the
commands it confirmed, every client applies them through its own applier.

**It runs BOTH ways.** Host-authoritative intent-up / confirmed-command-down
(owner call, 2026-08-24): a client's `CommandApplier.submit` does not
queue — it emits the command upward as a `KIND_INTENT`, the host puts
it through the same `_validate -> confirm -> apply` a local command takes, and
the confirm comes back down as an ordinary `KIND_COMMAND` the client
applies through `CommandApplier.apply_remote`. There is no local
pre-application and no prediction.

**A refusal has its own leg** (`KIND_REFUSAL`), because a command
the host's gate rejects never confirms and so never crosses down — and a
client waiting on a confirmation that will never arrive is the failure mode
this feature most needs to not ship. There is deliberately NO timeout, retry
or heartbeat for a confirm that is simply lost: ENet's reliable-ordered
channel is the guarantee, and a desync on a one-room LAN is a restart.

**Every verb `CommandApplier` handles mirrors** — launch_attack rides down
with an `AttackRecord` the client replays rather than re-resolving, loot as a
`LootRoundCommand` per round carrying what was granted BY VALUE. This class
mirrors whatever the applier handles, so a verb missing from the wire is
almost always a missing submission site, not a transport gap. Check who
raises the command first.

`PickLootCommand` is the one verb built for the upward direction, and the
exception on both ends: the applier answers it through
`PickLootCommandHandler.apply`, NOT through its queue, so it never
confirms and can never be broadcast back down. For the same reason it opens
no awaiting window and is not watched for refusal; see `_on_intent`.

**The determinism probe hangs off the mirror path here** as two optional
calls into `DeterminismProbe` and no logic of its own; the per-command
compare is `WorldSyncChannel`'s. It never changes what is applied, and it is
off unless a harness turns it on.

This channel is also the one that tells the applier whether it DECIDES or is
told: the core's `NetworkLink.role` reaches it through
`_on_identity_changed`, so the core holds no applier.

See `docs/domain/multiplayer-harness.md` and
`docs/domain/determinism-probe.md`.

