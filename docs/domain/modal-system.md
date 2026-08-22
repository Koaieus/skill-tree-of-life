# The modal system

Every full-screen "answer this before you carry on" surface in the game is one
[`ModalBase`](../../ui/modal/modal_base.gd) inherited scene plus one
[`ModalBodyBase`](../../ui/modal/modal_body_base.gd) body scene, serialized
through HudRoot's modal queue. Three exist today —
`LootPicker`, `SpellLootPicker`, `MassActionConfirmPanel` — and #199's
level-up bonus picker is the next one.

## The three pieces

| Piece | Owns |
|---|---|
| `ModalBase` (`ui/modal/modal_base.tscn`) | Dim/Center/Panel chrome, Title/Subtitle/Confirm/Cancel, the input freeze, the confirm gate, the three exits. **Never resolves anything.** |
| `ModalBodyBase` (a body `.tscn` per modal) | The part that actually differs: what's shown, what "valid" means, what the subtitle says, what got picked. |
| `HudRoot` | The queue, and the two side-gates a modal implies (AnnouncementLayer, PauseMenu). |

## Adding a modal — the whole checklist

1. **Body scene.** New `.tscn` whose root is any `Container` (a card row is an
   `HBoxContainer`, a scrolling breakdown a `VBoxContainer`), script `extends
   ModalBodyBase`. Implement `populate` / `is_selection_valid` / `status_text`,
   plus `confirm_text` if the verb depends on the request, plus `resolve` if
   there is something to pick. Emit `selection_changed` whenever an answer may
   have changed — the base *pulls* the rest, it is never pushed.
2. **Modal scene.** New **inherited scene** of `modal_base.tscn` (`Ctrl+Shift+O`
   → pick it → "New Inherited Scene"), script `extends ModalBase`. Restyle the
   `Panel`'s border tint, author `Title`/`ConfirmButton` text, set
   `cancellable` if the answer is refusable. Give it a `present(request)` that
   calls `_present(_BODY_SCENE, title, request)`.
3. **Resolution.** Connect `confirmed` (and `cancelled` if cancellable) in
   `_ready` — after `super()` — and do the request-specific thing there.
4. **Mount + queue.** Instance it in `hud_root.tscn`, add the `@onready`, wire
   `closed → _on_modal_closed` in HudRoot's `_ready`, and raise it with
   `_enqueue_modal(func(): my_modal.present(request))`.

## Why the base never calls `request.resolve()`

It used to, duck-typed on a `Variant`. The two request families genuinely
differ: a `LootPickRequest`/`SpellLootRequest` carries its own resolve callback
(one-shot, fire-and-forget), while a `MassActionRequest` is **live state on
`PlayerInputController`** — confirm and cancel both route back through the
controller, and it can be revoked from outside the modal entirely. Forcing a
shared `resolve()` on the second would mean handing the request an input
controller just to satisfy the base. So the base emits
`confirmed(chosen, request)` / `cancelled(request)` and the concrete modal
decides.

## The three exits

`closed` fires exactly once per `present()`, **after** `confirmed`/`cancelled`,
on all three paths:

- **Confirm** — `_on_confirm`: hide → unfreeze → `confirmed` → `closed`.
  Unfreezing *before* the action runs is what lets a modal raised *by* the
  confirmed action (a loot pick off a confirmed cascade) queue correctly.
- **Cancel** — Cancel button, Esc, or right-click, only when `cancellable`.
- **`dismiss()`** — the decision was revoked from outside (e.g.
  `PlayerInputController.clear_transient_state` on level teardown drops a
  pending `MassActionRequest`). Emits `closed` but neither of the other two.

Miss the third and you get **permanently frozen input**, which is a worse
failure than the missed unpause it replaced. Miss `closed` on any of them and
`_modal_busy` latches true — every later modal is queued forever, silently.

## Never `get_tree().paused`

Pausing the tree stalls confirmed-command RPC dispatch under the LAN sync model
([multiplayer-sync-model.md](multiplayer-sync-model.md)), and a `Tween`-driven
`AnnouncementLayer` band keeps animating through a pause anyway — which is how
a banner used to render on top of a frozen, dimmed modal. Instead:

- `PlayerInputController.set_input_frozen(true)` blocks every player input
  channel (`_unhandled_input`, `_unhandled_key_input`, click routing).
- `AnnouncementLayer.set_modal_open(true)` blocks new dequeues.
- `PauseMenu.set_blocked(true)` keeps Esc from stacking the pause menu on top.

The last two are HudRoot's `_set_modal_busy`, so a modal gets them for free.

## Why the queue is not optional

`set_input_frozen` is a plain bool, not a counter. Two overlapping modals mean
the first to close unfreezes input while the second is still up. HudRoot's
`_pending_modals` / `_modal_busy` is what keeps that bool honest — one modal is
open at a time, ever. It lives in HudRoot, not an autoload: it has exactly one
owner.

A queued `present()` can therefore run some time after it was enqueued, so a
modal whose request has a live lifetime must **guard against a stale request**
(`MassActionConfirmPanel.present` checks it is still the controller's pending
one) and `closed.emit()` straight back out if it has gone.

## Layout gotcha

`%BodySlot` is a `CenterContainer`: it hands its child exactly the child's
combined minimum size and does **not** expand it. A body that needs to scroll
says so with `custom_minimum_size` on its `ScrollContainer`; size flags will
just make it grow instead.
