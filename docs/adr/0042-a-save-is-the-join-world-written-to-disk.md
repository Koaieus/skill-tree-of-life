---
id: 0042
title: A save is the join world written to disk; WorldImage is the one capture/apply owner and the wire and the disk are its transports
status: accepted
date: 2026-10-02
deciders: owner+agent
supersedes: []
superseded-by: null
revisit-when: "WorldImage's home in network/ is a tentative pass call — revisit if a save needs something network/ cannot hold without a new network→ edge"
sources:
  - "#23"
  - "#1332"
  - "network/world_image.gd"
  - "docs/architecture.md"
  - "docs/domain/multiplayer-sync-model.md"
tags: [save, multiplayer, netcode, architecture]
---

# ADR 0042 — A save is the join world written to disk; WorldImage owns capture and apply

## Context

Since #527 / #560 / #715 the mid-run join and the desync backstop already ship a whole world: `send_resync` encodes `EntitySnapshot` + `GraphSnapshot` (turn cursor and round state included), and `_on_resync` applied it in a five-step dependency order that lived inline on the channel. Save/load (#23) needed a format; `docs/architecture.md` already named the join-time snapshots in `network/` as the save seed, on the condition that a save pulls no new `network→` edge.

## Decision drivers

- Type safety, data safety, composability.
- A future piece of state that needs saving does nothing, or one minimal edit.
- One serializer of the three-tier contract (authored by ref, accumulated by value, derived never) — not two.
- The apply order is one fact and gets one owner.

## Decision

Owner, 2026-10-02 (#23): *"i want it in whatever's the cleanest way. best type safety, data safety, composability (and once it's there, future additions that need saving ideally have to do nothing or a minimal job if they need saving too."*

Resolved on #23 as: **a save is the join world written to disk.** One transport-free owner, `WorldImage` (`network/world_image.gd`), does both capture and apply; `WorldSyncChannel` (the wire) and the disk are its two transports. `WorldImage.apply` owns the order — entity decode, graph decode, entity graph refs, HP, turn cursor — and the wire keeps only its own flags (join-world, awaiting-resync, defer-until-world).

## Consequences

- Any state the multiplayer join carries is saved for free; a new piece of accumulated state needs exactly one edit, its snapshot row, which the join already requires.
- The capture → apply → capture round-trip is a testable invariant: bytes, fingerprint, and every entity stat value and pool `current` equal.
- A save inherits the snapshot codecs' limits: anything the join does not carry, a load does not restore either.

## Alternatives considered

### `ResourceSaver` + `@export_storage`

Rejected on #23: a second serializer of the three-tier contract; `RefCounted` ledgers like `ModifierBins` and `EffectInstance` cannot ride it; loading a `.tres`/`.res` from `user://` can execute embedded scripts.

### Command-log replay

Rejected on #23: needs a no-reveal-clock mode that does not exist, load time grows with the run, and every balance change breaks every save.

### Keeping the apply order inline on the channel

Rejected: the disk would need a second copy of the five-step order, and two copies are two chances to disagree.
