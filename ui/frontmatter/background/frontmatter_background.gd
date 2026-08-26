@tool
class_name FrontmatterBackground
extends CanvasLayer

## A real background for the frontmatter menu (#602) instead of the engine's
## default gray: one opaque base layer of domain-warped, palette-mapped noise
## ("colour waves") plus two additive line-streak layers, each hosted in its
## own [Parallax2D] so they scroll at different rates as the frontmatter's
## [Camera2D] travels between menu nodes — the same multi-depth-parallax shape
## as [code]ui/space_background/space_background.gd[/code], reused because it
## already solves "several full-screen shader layers behind everything else".
##
## [b]Self-contained on purpose.[/b] This scene is not mounted into
## [code]ui/frontmatter/frontmatter_root.tscn[/code] yet — a sibling unit owns
## that file. It works standalone (this script needs nothing injected;
## [Parallax2D] reads the viewport's active [Camera2D] itself) so it can be
## instantiated directly in a test or a sandbox tab. Intended mount point: a
## direct child of [code]FrontmatterRoot[/code], parented BEFORE
## [code]%GraphLayer[/code] in sibling order and/or on a negative
## [member CanvasLayer.layer] (this scene uses [code]-100[/code], matching
## [code]SpaceBackground[/code]) so it draws behind the graph and the
## [code]PanelLayer[/code] [CanvasLayer] without depending on node order.
##
## [b]Animation clock.[/b] The shaders read a plain [code]shader_time[/code]
## uniform this script drives in [method _process], never the builtin
## [code]TIME[/code] — that is what lets [member reduce_motion] freeze the
## colour/line animation while leaving the [Parallax2D] layers' positional
## scroll alone, since that scroll already only moves when the camera does
## (driven by [code]FrontmatterRoot[/code]'s own navigation travel, which
## independently collapses under reduce motion) rather than needing a clock of
## its own.

## Master toggle so a showcase / embed can drop the background without
## deleting it. Mirrors [code]SpaceBackground.enabled[/code].
@export var enabled: bool = true:
	set(value):
		enabled = value
		visible = value

## Freezes the shader-driven colour/line animation. [method _ready] overwrites
## this from [member GameSettings.reduce_motion] (see [method _resolve_reduce_motion]),
## so what is authored here on the node is only the default a run without the
## autoload gets — the editor, and any live sandbox tab. Follows
## [code]FrontmatterRoot.reduce_motion[/code]'s exact contract (#602 brief).
@export var reduce_motion: bool = false

@onready var _base_sprite: Sprite2D = %BaseLayer
@onready var _mid_sprite: Sprite2D = %MidLayer
@onready var _near_sprite: Sprite2D = %NearLayer

var _elapsed: float = 0.0


func _ready() -> void:
	reduce_motion = _resolve_reduce_motion()
	visible = enabled
	_push_time(0.0)


func _process(delta: float) -> void:
	if not reduce_motion:
		_elapsed += delta
	_push_time(_elapsed)


func _push_time(t: float) -> void:
	(_base_sprite.material as ShaderMaterial).set_shader_parameter("shader_time", t)
	(_mid_sprite.material as ShaderMaterial).set_shader_parameter("shader_time", t)
	(_near_sprite.material as ShaderMaterial).set_shader_parameter("shader_time", t)


## Same contract as [code]FrontmatterRoot._resolve_reduce_motion()[/code]:
## reads [member GameSettings.reduce_motion] off the [code]Settings[/code]
## autoload EXCEPT in the editor, where that autoload is not in the tree (this
## script is [code]@tool[/code] so an editor preview or a live sandbox tab can
## mount it) — there, the authored [member reduce_motion] export is the value.
func _resolve_reduce_motion() -> bool:
	if Engine.is_editor_hint():
		return reduce_motion
	return Settings.current.reduce_motion
