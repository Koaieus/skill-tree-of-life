class_name ArmedMode
extends RefCounted

## One level of PlayerInputController's pop stack (#404's shared arm/pop
## primitive, generalized #406). Priority is array order in
## PlayerInputController._armed_modes — earlier entries pop before later
## ones, which is how nesting is expressed (e.g. a temp-upgrade arm sits on
## top of an attack plan and must pop first). Duck-typed, not a true
## interface — GDScript has none; subclasses override the methods they need.

func is_armed() -> bool:
	return false


## Pop one level. Returns true if anything changed.
func pop() -> bool:
	return false


## The identity colour this level lends to the viewport armed-mode glow
## (#412), or a transparent colour for "this level shows no glow".
##
## Only [AttackPlanArmedMode] overrides this today — **owner call 2026-08-21:**
## "in Manage mode: no outline". Every other level (Manage verbs, core-move,
## temp-upgrade, mass-action) deliberately contributes nothing, so the
## highlight-ring language doesn't gain colours ahead of the design pass
## `docs/FOCUS.md` already reserves for it.
##
## Read by [method PlayerInputController.get_armed_tint], which walks the stack
## **base-first** — see its docstring for why that isn't the pop order.
func tint() -> Color:
	return Color.TRANSPARENT
