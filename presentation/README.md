# `presentation/` — parked, not dead (#488 / #504)

**Nothing in this directory is wired up.** All four classes are unreferenced by
production code, deliberately. Do not delete them as dead code, and do not
mistake them for live machinery.

## What they were

This is design **A** of the presentation clock: the world mutated at `t = 0`
and a `PresentationPlayer` owned a parallel *view store* (`shown_hp` /
`shown_owner` / `shown_health`) that every painter read instead of the model,
replayed later off a recorded `RevealTimeline`.

`RevealRecorder` was the ambient recorder, `RevealEvent` the payload,
`RevealTimeline` the ordered schedule, `PresentationPlayer` the store and the
replayer.

## Why they are parked

#488 decided design **B** — the world mutates on the reveal clock, and what is
drawn is the model at every beat. #504 implemented it. Under B there is no view
store to keep in step, so the whole read-path question disappears rather than
being answered per painter. See `docs/domain/presentation-clock.md`.

Design A was not wrong so much as unfinishable: because `force_deallocate`
revokes the dead node's modifiers synchronously, A needed a shown-value *per
stat*, not three. Three fields was never a resting point.

## Why they are kept

`RevealEvent`'s `from_value` / `to_value` is precisely the self-contained
payload an **authoritative or fog-gated** mode would want — "here is what dies,
and what their stats were" — which is a different problem from the one B
solves. If multiplayer ever needs the host to ship a reveal rather than a
command, this is the shape it wants, already prototyped and tested once.

Delete them in a later cleanup once B has proven out in real play; restore them
intact if B hits a wall.
