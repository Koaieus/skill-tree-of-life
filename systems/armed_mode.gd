class_name ArmedMode
extends RefCounted

## One level of PlayerInputController's pop stack (#404's shared arm/pop
## primitive, generalized #406). Priority is array order in
## PlayerInputController._armed_modes — earlier entries pop before later
## ones, which is how nesting is expressed (e.g. a temp-upgrade arm sits on
## top of an attack plan and must pop first). Duck-typed, not a true
## interface — GDScript has none; subclasses override both methods.

func is_armed() -> bool:
	return false


## Pop one level. Returns true if anything changed.
func pop() -> bool:
	return false
