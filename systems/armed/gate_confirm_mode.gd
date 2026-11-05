class_name GateConfirmMode
extends ArmedMode

## The one-warning confirm of a stranding gate flip, pushed on whatever is on
## top (an attack plan included). Esc / right-click pop it like any level; the
## identical second request pops it and submits. Clicks fall through, and there
## is no badge or tint: the stranded-node highlight is its presentation.

## The sorted gate keys of the armed request — what "the identical request" means.
var key: Array[Vector2i] = []
## The owned nodes the flip would strand.
var stranded: Array[SkillNode] = []


func _init(p_ctl: PlayerInputController, p_key: Array[Vector2i],
		p_stranded: Array[SkillNode]) -> void:
	ctl = p_ctl
	key = p_key
	stranded = p_stranded


func on_popped() -> void:
	if ctl != null:
		ctl.on_gate_confirm_popped()
