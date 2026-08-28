---
description: SubBag — connect-on-show, clear-on-hide for ephemeral UI signal subscriptions
paths:
  - "ui/**"
---

Ephemeral node-local UI — a health bar that lives while `damaged`, a tooltip
fan that sprouts on hover, a hot-seat rebind — connects through `SubBag`
(`ui/common/sub_bag.gd`), never a per-site `is_connected()` guard. On appear:
`subs.now(sig, fn)` — connect **and** synchronously invoke once, so the
first paint reads current state instead of racing the next emit. On dismiss:
`subs.clear()` — idempotent, drops every subscription made through the bag.

```gdscript
var subs := SubBag.new()

func _sprout(node: SkillNode) -> void:
	subs.now(node.damaged_changed, _refresh_hp)
	subs.on(entity.node_health_moved, _refresh_hp)

func _dismiss() -> void:
	subs.clear()
```

**A pooled or hidden panel must `clear()` on hide — never trust teardown.**
Godot only auto-disconnects a *freed* listener; a panel that is hidden but
still alive (pooled, reused, or simply `visible = false`) stays connected and
keeps firing invisibly unless something calls `clear()` for it. Free-time
auto-disconnect is not a substitute for a hide-time `clear()`.

`fn` passed to `now()` must be safe to invoke with **zero** arguments — read
current state itself rather than depend on the signal's emitted value, since
`now()`'s synchronous first call has no emit to source an argument from. If
`sig` itself emits with arguments, give every one of `fn`'s parameters a
default (`func(_v: float = 0.0): ...`) — Godot enforces exact-or-fewer-via-
default arity, so a bare `func(v: float): ...` connected the normal way still
errors the moment `now()` calls it with none ("Method expected 0 argument(s),
but called with 1").

For a binder that only needs "drop this scope's connections on rebind," with
no first-paint fuse, `BindScope` (`ui/bind_scope.gd`) is the older, narrower
primitive most HUD clusters already use — SubBag composes over it rather than
re-deriving the freed-emitter/lambda-identity handling. Reach for `SubBag`
when the call site wants `now()`; reach for `BindScope` directly only inside
an existing binder that already holds one and has no first-paint need.
