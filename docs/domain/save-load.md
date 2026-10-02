# Save / load — one run, one slot, offline

A save is the join world written to disk (ADR 0042): the run's setup
(`RunConfig.to_dict` + `ParticipantRoster.to_dict`), the level scene that owns
the `Graph`, and a `WorldImage` — the same two snapshot halves a joining peer
receives. Single slot (`SaveFile.SLOT_PATH`, `user://save.bin`), offline runs
only; multiple slots, metadata and story-mode suspend-only are not in the
baseline.

## The one rule for new state

**A piece of accumulated world state saves itself iff its snapshot row carries
it.** Add it to `GraphSnapshot` / `EntitySnapshot` (which also fixes a resync
gap — sync and save are one path) and bump `SaveFile.FORMAT_VERSION`; never a
second serializer. `test_save_file.gd` pins a hash of every `_R_*` row index
(plus the `WorldImage` envelope version) per format version, so a row change
without a bump goes red — the failing assert prints the new hash to pin.

What is deliberately *not* saved: an AI's mid-turn controller state (it holds
nothing beyond diagnostics counters; it re-decides from the saved world), and
anything presentation-side.

## The format

`network/save_file.gd`'s docblock is the contract: `"STLS"` | u32
`FORMAT_VERSION` | SHA-256 of the body | ZSTD body of a plain `Dictionary`.

- **Validate before touching the world** — magic, version, checksum,
  decompress, field types, in that order. `LoadResult { OK, MISSING, CORRUPT,
  VERSION_MISMATCH }`; anything but `OK` leaves an empty world, so a refused
  load has nothing to half-apply.
- **Versioning** — another `FORMAT_VERSION` is refused, never migrated. The
  build `short_sha` is recorded for diagnostics only: a dev save survives a
  commit.
- **Atomic write** — `<slot>.tmp`, then rename over the slot.
- **`bytes_to_var` only**, never `_with_objects`: a save file cannot carry code.

## The gate — `SaveGate` (`%SaveGate` in `game_root.tscn`)

- `can_save()` is false only in an online run (`GameSession.network`). Who holds
  the turn is irrelevant: a save between two AI actions, or partway through
  anyone's turn, is allowed.
- `request_save()` writes at once when `CommandApplier.is_quiescent()`; else the
  request is **held** (`is_save_held`, `save_held_changed`) and fires at the next
  quiescent boundary — the world captured then, never at the press. A
  half-replayed `AttackRecord` is never captured. `saved(error)` reports the
  write.
- `blocked_reason()` is the tooltip: the online refusal, or `REASON_LOOT` ("Pick your loot
  first") while a relic pick is open — the one held wait that is on a human.
- The gate reads `is_quiescent()` only, never the applier's flags one by one;
  quiescence is the applier's to define.

## The load path

1. `SaveFile.read_slot()` → a non-`OK` `load_result` stops here.
2. `GameSession.open_saved(save)` — the third entry beside `start()` and
   `apply_received()`: takes the config and roster as concrete (no seed
   resolution, as on a join), sets `world_source = ARRIVES`, parks
   `pending_world`.
3. The caller routes `SceneDirector.goto(save.level_scene_path)`. A sandbox's
   `RunBootstrap` must not open a fresh run over the session `open_saved`
   opened (the path may be a sandbox's: it is `graph.owner.scene_file_path`).
4. `GameRoot`, after `_setup_level` returns with a parked image, calls
   `WorldImage.apply(graph, spawner, turn_manager)` — the same apply the wire
   uses; the disk is just the other deliverer — and clears it.
5. **AI resume.** `TurnManager.adopt_turn` marks the turn adopted and never
   calls `begin_turn()`, so `turn_began` never fires. If this machine is the
   authority and the holder's controller is an `AIController`, GameRoot calls
   its `take_turn()` once. Never `begin_turn()`: the saved board already has
   this turn's upkeep (regen, income, `turns_taken`). A local human holder
   needs nothing — the HUD reacts to the `turn_started` `adopt_turn` emits.

The per-turn fields that make a mid-turn save honest (`volleys_launched_this_turn`,
the turn-start leaves) ride `EntitySnapshot`; see `docs/domain/entity-snapshot.md`.
