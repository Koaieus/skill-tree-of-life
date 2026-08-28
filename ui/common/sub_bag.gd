class_name SubBag
extends RefCounted

## Scoped signal subscriptions for ephemeral, appear/dismiss UI (#9) — a health
## bar that lives while `damaged`, a tooltip fan that sprouts on hover,
## hot-seat rebind (#459's [method HudRoot.rebind_player]).
##
## `on(sig, fn)` connects. `now(sig, fn)` connects AND invokes [param fn]
## synchronously, once — the load-bearing method. Query-then-subscribe done as
## two separate steps leaves a gap where the signal can fire between them,
## producing a stale first paint; fusing them into one call makes that gap
## unwritable. `now()` always calls [param fn] with **zero** arguments, so
## [param fn] must tolerate that — either take none, or give every parameter a
## default. This is not optional if [param sig] itself emits with arguments:
## Godot requires an exact-or-fewer-via-default arity match, so a bare
## `func(v: float): ...` connected to a 1-arg signal errors ("Method expected
## 0 argument(s), but called with 1") the moment `now()` invokes it with none.
## Read current state inside [param fn] instead of trusting either call's
## argument — it is safe to ignore what a signal emits when the underlying
## value is already readable off the object that owns it.
##
## `clear()` drops every subscription made through this bag. Idempotent, and
## safe even if the emitter or the connected target has since been freed:
## Godot auto-disconnects a freed *target*, and a freed *emitter*'s Signal
## still carries a dangling object pointer that [BindScope] checks before
## touching it. **A pooled or hidden panel must `clear()` on hide — free-time
## auto-disconnect does not fire for hidden-but-alive panels**, which is the
## whole reason this type exists rather than a per-call `is_connected()`
## guard at every call site. See `.claude/rules/ui-subscriptions.md`.
##
## Delegates the actual bookkeeping to [BindScope] rather than re-deriving
## it — same freed-emitter tolerance, same "store the exact Callable, not a
## name" fix for lambdas and `unbind()`ed callables (see its doc). SubBag adds
## the two things a hot-seat-only binder didn't need: a duplicate-connect
## no-op (repeated connect-on-show, no dismiss in between) and `now`.

var _scope := BindScope.new()


## Connect [param fn] to [param sig]. A second `on()` of the same pair —
## double-show without a dismiss in between — is a no-op rather than a
## double connection.
func on(sig: Signal, fn: Callable) -> void:
	if sig.is_connected(fn):
		return
	_scope.link(sig, fn)


## [method on], then call [param fn] immediately with no arguments — the
## synchronous first paint that makes the read/subscribe gap unwritable.
func now(sig: Signal, fn: Callable) -> void:
	on(sig, fn)
	fn.call()


## Drop every subscription made through this bag. Idempotent; safe to call on
## an already-cleared bag, or one whose emitter or target has been freed.
func clear() -> void:
	_scope.release()
