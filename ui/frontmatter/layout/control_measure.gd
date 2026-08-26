class_name ControlMeasure
extends RefCounted

## Static "instance it, sort it by hand, measure it, free it" machinery (#589
## D3), shared by every screen-space geometry that is authored as a scene but
## answered as a pure function: [MenuFanHarness] (one menu's fan) and
## [FrontmatterLayout]'s reader of `frontmatter_columns.tscn` (#603 C2).
##
## [b]Promoted, not duplicated.[/b] `hero_slot()` needed the exact same
## "instance / sort / measure / free" dance [MenuFanHarness.measure] already
## does, and a second hand-rolled copy would be two implementations of one
## contract — the thing `.claude/rules/` calls out by name. So the three
## pieces of that dance that do not need a [MenuFanHarness]'s own state move
## here, and [method MenuFanHarness.measure] calls them too.
##
## [b][method parent_for_measuring] is not boilerplate.[/b] Its docstring
## records a real crash: [method Node.add_child] fails — printing its own
## error rather than raising — on a `root` that is busy adding a scene that
## was run DIRECTLY (F6 in the editor, or `run/main_scene`), which was hit on
## every direct run of `meta_root.tscn`. Reading this cold and re-deriving the
## workaround from scratch is how that crash comes back.


## Drives one full container sort, top-down, inside a single call.
##
## [b]Why by hand.[/b] [method Container.queue_sort] defers through the
## message queue and only flushes inside a frame, so the obvious version would
## force every caller into an `await` — including the unit tests, which exist
## precisely because a [Transform2D] is assertable and a tween's third frame is
## not. `NOTIFICATION_SORT_CHILDREN` is the same code path the queue would
## eventually run; sending it in parent-before-child order gives the identical
## result synchronously, because each container needs only its own size
## (already set by its parent's sort) to place its children.
static func sort(control: Control) -> void:
	if control is Container:
		control.notification(Container.NOTIFICATION_SORT_CHILDREN)
	for child in control.get_children():
		if child is Control:
			sort(child as Control)


## Parents [param control] somewhere it can actually be measured, for the
## length of one synchronous call.
##
## [b]Not `root`, on purpose.[/b] [method Node.add_child] FAILS — printing its
## own error rather than raising — on a parent that is busy setting up
## children, and `root` is exactly that while the [SceneTree] is adding a
## scene that was run DIRECTLY (F6 in the editor, or `run/main_scene`). The
## measured control then never parents, [method sort] measures every rect as
## `0x0`, and the first thing anyone sees is a null `get_parent()` two calls
## away. That was a real crash on every direct run of `meta_root.tscn`.
##
## Every autoload is a fully-ready child of `root` before any scene is added,
## so none of them is ever mid-add — which makes one of them a host that works
## in both cases, and avoids the failed-`add_child` error that probing `root`
## first would print every time. Being a [Control] under a plain [Node] does
## not affect `is_visible_in_tree()`, which is the only thing the sort needs.
static func parent_for_measuring(control: Control, host: SceneTree) -> void:
	for candidate in host.root.get_children():
		if candidate == host.current_scene:
			continue
		candidate.add_child(control)
		if control.is_visible_in_tree():
			return
		# Parented, but under something hidden (the fade overlay is an
		# autoload and rests invisible). `fit_child_in_rect` early-returns on
		# anything not `is_visible_in_tree()`, so this host is no better than
		# none.
		candidate.remove_child(control)
	host.root.add_child(control)


## [param control]'s centre in [param stop]-local pixels. Walked by hand
## rather than via [method Control.get_global_rect]: the control is parented
## to the tree ROOT for the duration of a measurement, so a global rect would
## be offset by wherever root put it. Local accumulation up to [param stop] —
## the measured subtree's own top — is what makes the result independent of
## that.
static func centre_of(control: Control, stop: Control) -> Vector2:
	var at := control.size * 0.5
	var node: Node = control
	while node != null and node != stop:
		at += (node as Control).position
		node = node.get_parent()
	return at
