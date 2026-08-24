# Seat policy — who this machine plays

A run's setup splits into two halves, and confusing them is the bug this
document exists to prevent.

| Half | Lives on | Same on every machine? | May level generation read it? |
|---|---|---|---|
| **Run shape** — how many camps, who is on them, which seed | `ParticipantRoster` / `RunConfig` | yes | **yes** |
| **Seat** — who *I* play, what *my* screen shows | `SeatPolicy` (`session/seat_policy.gd`) | **no** | **never** |

> **The invariant: a `SeatPolicy` never feeds anything a peer must reproduce.**
> Not procgen, not an RNG stream, not command application. Two peers answer its
> questions differently *by design*; anything downstream of it that a peer has
> to agree on is a desync. The tempting violation is concrete — "spawn the local
> player at the bottom of the screen" in the coop/versus preset (#516). Camp
> count and camp-relative placement come off the **roster**, which is the same
> everywhere; `roster.camps()` is already the accessor.

This is not merely cosmetic, though. `VisionSystem._recompute` toggles
`SkillNode.input_pickable`, so the seat shapes the legal intent *surface* on
this machine. It shapes what may be **offered** here, never what a command
**does** once submitted.

## The two questions

`SeatPolicy` answers exactly two, plus the vision rule:

1. **`seats(entity)`** — is this one of my heroes, the ones this screen serves?
2. **`follows_active_turn()`** — does the local view re-point when one of them
   takes its turn?
3. **`vision_group(hero, candidates)`** — whose sight unions into the local fog?

## One axis: COUCH or SEAT

|  | `seats` | `follows_active_turn` |
|---|---|---|
| single player | the one hero | (moot — one human) |
| hot-seat coop | both humans | yes |
| hot-seat versus | both humans | yes |
| online, any mode | my hero only | no |

`COUCH` (drive every local human, view follows the turn) and `SEAT` (drive one
hero, view pinned) are the whole axis. **Coop vs. versus never appears** —
that distinction is `Participant.camp` and nothing about seating needs it,
which is why local versus costs a lobby toggle rather than a mode branch.
`RunConfig.Mode` exists for menu presentation and defaults; deriving seating
from it would be a second source of truth against the roster.

Constructors: `SeatPolicy.couch()` (the default a roster-less hand-authored
scene or a GUT fixture gets), `SeatPolicy.seat(entity_id)`, and
`SeatPolicy.from_roster(entities_by_participant_id, roster, local_peer_id)` —
the same dictionary `GameRoot.apply_roster` takes, so the two calls sit
adjacent. `from_roster` returns a couch when every human in the roster sits at
this peer.

The seat is keyed on `Entity.entity_id` — already the host-minted cross-wire
identity (`.claude/rules/multiplayer-sync.md`). Note `entity_id` is `0` until
the entity enters `entities_container`, and `0` is also the spectator seat, so
`seats()` never matches an unminted entity.

## The vision rule, and why it needs no `peer_id`

**Allied humans:** human-controlled, and sharing the bound hero's `faction.id`.
One line, four correct answers:

- **Coop shares** — couch *or* wire. `apply_roster` sets
  `is_human_controlled` from `Participant.kind`, which says `HUMAN` wherever
  that human is sitting, so a teammate on another machine reads human on mine
  and reveals for me exactly as a couch partner does. This is the non-obvious part; the instinct
  to thread `peer_id` through the vision rule is wrong.
- **Versus does not** — rivals are different camps by construction, so each
  group is a single hero. On a hot-seat couch the fog swaps with the handover,
  which is the point.
- **AI never shares**, with a player or with another AI, even standing on the
  human camp. AI recon was never this system's business — `AiRecon` builds its
  own per-entity circles. Faction-shared AI reveal is #394.
- **Blockers never share** — not human, own dormant camp.

### The ordering trap

`GameRoot._apply_seat_vision` skips the write when the viewer set is unchanged,
because `VisionSystem.viewers`' setter unconditionally rebinds every viewer
stat and recomputes — that skip is what stops a coop handover flashing the map.
The comparison is GDScript array equality, which is **element-wise**: both
sides of a handover must produce the identical array, order included. That is
why the candidate walk stays in `GameRoot`, in `Entity.GROUP` order, and why
`vision_group` filters rather than builds from roster order.
`test_hot_seat_handover.gd::test_handover_does_not_re_derive_fog` pins it with
`is_same`, which is the only assertion that distinguishes "skipped" from
"reassigned an equal array".

## What is deliberately elsewhere

- **Submit permission** — whether input may *act*, not merely which hero it
  points at. That is command authority (#463): a client can be seated on a hero
  it may not yet act for, which `PlayerInputController.set_input_frozen`
  expresses. The multiplayer harness's client is exactly that.
- **Camera targeting** (#515) — a consumer of the bound hero, not a second
  opinion about it.
- **Per-machine state fidelity under fog** (#519) — what a peer is *told*, as
  opposed to what it draws.
- **How a run-end reads on this screen** — *closed by #517, and it landed on
  the seat.* `victory_system.local_camp` is gone: `RunOutcome` is
  point-of-view-free, and `HudRoot` gates the loss overlay on `seating`
  (COUCH → winner banner only; SEAT → overlay iff the seated hero's camp lost).
  That is what makes the couch answer independent of turn order, which the old
  `bind_player` assignment never was. See `docs/domain/victory-system.md`.

## Callers

`GameRoot.seat_policy` defaults to `SeatPolicy.couch()`. Live constructors
today: `scenes/procgen_play_sandbox.gd` (`from_roster`) and
`scenes/dev/mp_dev_sandbox.gd` (`seat()` on the client).

**The menu path does reach here** — corrected 2026-08-24 (#553); the older note
claiming otherwise was stale from the moment #457 landed. `scenes/meta/meta_root.gd`
calls `GameSession.start(run_config)` and routes to a level, and since #553 that
level *consumes* `GameSession.roster` rather than building its own and
overwriting the session's with it.

What is still missing is not the path but the **roster**. Every participant a
lobby builds today shares one `peer_id`, and `from_roster` only returns a seat
when some participant's `peer_id` differs from this machine's — so it resolves
to `couch()` by construction, correctly. #553 added `GameSession.local_peer_id`
and passes it; **#554** is what puts a human with a real, foreign `peer_id` in
the roster, and `from_roster` needs no change when it does.

**`Participant.Kind` is `{ HUMAN, AI }` and nothing else (#562).** There is no
local/remote flavour of `HUMAN`, because locality is a relation between a
participant and the machine reading the roster — and the roster crosses the
wire, so the same row is correctly local on one peer and remote on the other.
Ask `Participant.is_local(local_peer_id)`; it is the one named home for the
question, and it is what `from_roster` calls. This is the same rule
`.claude/rules/ownership-vocabulary.md` draws for `owned_by` vs
`SkillNode.ownership_bit`, one layer up.
