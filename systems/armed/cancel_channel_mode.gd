class_name CancelChannelMode
extends ManageVerbMode


func _init(p_ctl: PlayerInputController) -> void:
	ctl = p_ctl
	verb = PlayerInputController.ManageVerb.CANCEL
