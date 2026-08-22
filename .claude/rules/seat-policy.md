---
description: The per-machine half of a run (who I play, what my screen shows) is SeatPolicy, and it must never feed anything a peer reproduces
paths:
  - "session/**"
  - "scenes/game_root.gd"
  - "scenes/dev/mp_dev_sandbox.gd"
  - "systems/vision_system.gd"
  - "procgen/**"
---

A run's setup has two halves. **Run shape** (how many camps, who is on them,
the seed) lives on `ParticipantRoster` / `RunConfig`, is identical on every
machine, and is what level generation may read. **Seat** (who *I* play, what
*my* screen shows) lives on `SeatPolicy` (`session/seat_policy.gd`), differs
per machine by design, and **must never feed anything a peer must reproduce** —
not procgen, not an RNG stream, not command application. Placement that
consults a seat is a desync; camp count comes off `roster.camps()`.

`SeatPolicy` answers `seats(entity)`, `follows_active_turn()`, and
`vision_group(hero, candidates)`. One axis: `COUCH` (every local human, view
follows the turn) or `SEAT` (one hero, pinned). Coop vs. versus is
`Participant.camp` and never enters seating. Fog is **allied humans** — AI and
blockers never share, and a remote teammate does without the rule consulting
`peer_id`.

**How to apply:** need a per-machine answer, add it to `SeatPolicy`; need one
every machine agrees on, it belongs on the roster. Never un-wire a signal to
express a seat. See `docs/domain/seat-policy.md`.
