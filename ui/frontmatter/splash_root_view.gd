@tool
class_name SplashRootView
extends MenuNodeView

## The root node's view, and the only one in the menu that can charge up (#734).
##
## [b]It exists because the charge is bespoke to one node.[/b] Owner,
## 2026-09-03: [i]"a bespoke effect, not part of the regular skillnodes. just for
## this one."[/i] So rather than teach [MenuNodeView] about a charge every other
## node will never have, `splash_root_view.tscn` INHERITS `menu_node_view.tscn`
## and adds a [ChargeGlow] sibling next to the composite —
## `docs/domain/scene-composition.md`'s option 1, and the only one available:
## an inherited scene may add nodes freely but may NOT re-point the instanced
## `Visuals` child at a derived [PackedScene].
##
## [b]Identity is FORWARDED, not bound.[/b] The glow needs the same colour and
## radius the view draws at, and the tempting move — a `bind()` call from
## [SplashScreen] — lands in the wrong order: [method FrontmatterRoot._build_views]
## calls [method MenuNodeView.bind] and writes [member MenuNodeView.radius]
## before the splash ever sees the view. Overriding the two sync hooks instead
## means the glow tracks whatever the view is currently drawing, from whichever
## write arrives last, and [SplashScreen] only ever has to say
## [method ChargeGlow.set_progress] and [method ChargeGlow.detonate].

@onready var charge: ChargeGlow = %ChargeGlow


## [b]Explicit, and it calls `super()` for a reason that is easy to get wrong.[/b]
## `@onready` assignments are injected at the TOP of the script's own `_ready`,
## so declaring one here is what guarantees [member charge] is resolved BEFORE
## [method MenuNodeView._ready]'s three sync calls run through the overrides
## below. Without it the base's `_ready` fires first, the overrides no-op against
## a null glow, and nothing ever pushes the colour or the radius down again —
## a charge ring drawn at the default radius in the default colour.
func _ready() -> void:
	super()
	_sync_identity()
	_sync_radius()


func _sync_identity() -> void:
	super()
	if charge != null:
		charge.base_color = display_color()


func _sync_radius() -> void:
	super()
	if charge != null:
		charge.node_radius = radius
