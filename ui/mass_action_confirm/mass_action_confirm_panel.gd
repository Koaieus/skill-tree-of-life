class_name MassActionConfirmPanel
extends ModalBase

## Modal confirm for a pending [MassActionRequest] (distant-allocate-path or
## would-island-deallocate-cascade). An inherited scene of `modal_base.tscn`
## (#486), same shape as [LootPicker]: [ModalBase] owns the shell, the input
## freeze and the confirm gating; [MassActionConfirmBody] (`%BodySlot`) owns
## the per-node breakdown.
##
## The one [member ModalBase.cancellable] modal — a loot pick must be answered,
## a mass action is a yes/no, so Cancel / Esc / right-click all refuse it.
##
## [b]Three exits, not two.[/b] Confirm and Cancel route back through
## [PlayerInputController]; the request can also be cleared from OUTSIDE (a
## level teardown's `clear_transient_state`), which HudRoot turns into a
## [method ModalBase.dismiss]. All three unfreeze input and emit `closed`.

const _BODY_SCENE := preload("res://ui/mass_action_confirm/mass_action_confirm_body.tscn")

var _allocation_system: AllocationSystem = null


func _ready() -> void:
	super()
	confirmed.connect(_on_confirmed)
	cancelled.connect(_on_cancelled)


## Not an override of [method ModalBase.bind] — GDScript has no overloads, and
## this modal needs the allocation system on top of the input controller.
func bind_systems(input_ctl: PlayerInputController, allocation_system: AllocationSystem) -> void:
	bind(input_ctl)
	_allocation_system = allocation_system


## Show the confirm for a pending request. Called by HudRoot off
## `mass_action_pending_changed`, through the modal queue — so by the time it
## runs the request may already have been cancelled, in which case this closes
## straight back out rather than presenting a dead decision.
func present(request: MassActionRequest) -> void:
	if _input_ctl != null and _input_ctl.pending_mass_action() != request:
		closed.emit()
		return
	var title := "ALLOCATE PATH" if request.verb == MassActionRequest.Verb.ALLOCATE \
			else "DEALLOCATE CASCADE"
	_present(_BODY_SCENE, title, request)


func _configure_body(body_instance: ModalBodyBase) -> void:
	(body_instance as MassActionConfirmBody).bind(_allocation_system)


func _on_confirmed(_chosen: Array, _request: Variant) -> void:
	if _input_ctl != null:
		_input_ctl.confirm_mass_action()


func _on_cancelled(_request: Variant) -> void:
	if _input_ctl != null:
		_input_ctl.cancel_mass_action()
