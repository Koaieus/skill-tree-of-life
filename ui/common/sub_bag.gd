class_name SubBag
extends RefCounted

## Scoped signal subscriptions for ephemeral, appear/dismiss UI. `on(sig, fn)`
## connects (duplicate connects are no-ops); `now(sig, fn)` connects AND invokes
## [param fn] once with ZERO arguments, so the first paint never races the next
## emit. `clear()` drops every subscription and is idempotent, even for a freed
## emitter — a hidden-but-alive panel must call it on hide. Bookkeeping is
## [BindScope]'s. See `.claude/rules/ui-subscriptions.md`.

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
