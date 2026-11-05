# CommandApplier queue

Queue and confirmation-window details, moved out of source comments. The sync model itself is multiplayer-sync-model.md.

## CommandApplier queue (`command/command_applier.gd`)

The one place a `Command` becomes a world mutation (#510,
`docs/domain/multiplayer-sync-model.md`). Every peer — host included — runs
its confirmed commands through exactly one of these, in submission order.

**One serial queue.** `submit` enqueues and, if nothing is being
applied, drains. If a drain is already in flight it just enqueues and
returns: a command raised from inside another command's application is
QUEUED, never applied re-entrantly. That is not a hardening pass bolted on
later — the codebase already re-enters on the temp-upgrade path
(`ui/gauges/capacity_blips.gd`'s `pip_clicked -> ... -> _rebuild()` note),
so the guard ships on day one.

**The queue is ASYNC.** Two verbs are not synchronous:
`MoveCoreCommand` waits a beat between hops so the slides read as a cascade,
and `EndTurnCommand` runs `TurnManager.end_turn`, which ticks
initiative and can start an AI turn. A command may therefore take seconds,
and `is_applying` must survive the whole await. This copies the shape
`BattleSystem.is_launching` already proved works; it deliberately
does not reuse that flag, which keeps answering the narrower question "is an
attack in flight" (owner's clarification on #510).

**Signal order is load-bearing.** `command_applied` fires INSIDE
the guard, so a fallback handler that submits (the deallocate -> cascade
offer does exactly this) is queued rather than re-entering.
`applying_changed` fires after the flag clears — the same ordering
`battle_system.gd:282-289` documents for `is_launching`, and for the same
reason: the listener reads the flag the instant the signal arrives.

The flip side of that ordering: a `command_applied` handler that
submits UNCONDITIONALLY never lets the drain end. The queue is FIFO and
terminates exactly when handlers stop feeding it — there is no re-entrancy
depth to run out of, so a runaway handler is an infinite loop, not a stack
overflow. Every fallback here latches (PIC's cascade offer fires only on a
failed deallocate, and the request it opens waits on the player).

## CommandApplier is_awaiting_confirmation (`command/command_applier.gd`)

**Submitted, awaiting confirmation** (#541) — a command has been handed to
this applier and the authority has not yet decided it is going ahead. The
world has not moved and the player must not act.

**Zero-length locally for every verb (#545).** `submit` drains
synchronously down to `_validate`, so on a peer that DECIDES this is
true for a stack frame. It is not dead code: it is the round trip on a peer
that is told, which is what #463 opens, and it is the only phase name that
fits the window — `BattleSystem.is_launching` means "an attack is in
flight" and `is_applying` means "a mutation is under way", and neither
is true yet.

**#548 opened that round trip.** On a peer that is TOLD, this is true from
`_submit_upward` until the authority's confirm lands in
`apply_remote` carrying the same `Command.intent_id` — or until
`refuse_intent` closes it on a refusal. Still zero-length on a peer
that decides.


**Nested inside `is_applying` everywhere but one place.** The gate
is an OR (`PlayerInputController.can_player_act`) and on every path but
that one the OR cannot change the answer. The exception is the first
`submit` of a drain: this flips true BEFORE `is_applying` does, which
is both the honest reading — the command is submitted, nothing is applying
yet — and the only moment the third gate is the sole reason the player cannot
act. Do not "simplify" it to a read after the pop.
