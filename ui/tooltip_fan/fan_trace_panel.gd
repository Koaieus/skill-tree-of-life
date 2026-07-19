@tool
extends Control
## Sandbox-host panel for the tooltip-fan trace (#233, epic #159).
##
## Frames the FanTrace sandbox in a 2D [SubViewport] with on-screen play
## controls, so the draw-in → extinguish choreography is drivable from the
## unified sandbox host (a LIVE_EDIT tab) without opening the scene. This is the
## seam meant to grow with the other tooltip-fan components (FanUnit) as they
## land — add them to the embedded sandbox and surface their controls here
## beside these buttons. The four corner destinations already use [FanPanel]
## (#223) for skin + glow + reveal.
##
## Satisfies [SandboxLiveTab]'s loader contract with [method noop] — there is no
## inspected resource, same as node_visuals_panel / gimbal_3d_showcase.

@onready var _sandbox: Node = %Sandbox
@onready var _viewport: SubViewport = %World


func _ready() -> void:
	# The sandbox exposes the play controls as public methods; wire the buttons
	# straight to them. (@tool, so this runs inside the host in the editor.)
	%PlayButton.pressed.connect(_sandbox.play_draw_in)
	%EraseButton.pressed.connect(_sandbox.play_erase)
	%ResetButton.pressed.connect(_sandbox.reset_settled)
	%LoopButton.toggled.connect(_sandbox.set_looping)
	%HoverButton.toggled.connect(_sandbox.set_hover_driven)


func _process(_delta: float) -> void:
	# Keep the upward-fanning content framed as the viewport resizes: anchor the
	# sandbox origin near the lower centre so the traces sprout up into view.
	if _sandbox != null and _viewport != null:
		_sandbox.position = Vector2(_viewport.size.x * 0.5, _viewport.size.y * 0.82)


## [SandboxLiveTab] loader contract — this panel takes no inspected resource.
func noop(_obj: Object) -> void:
	pass
