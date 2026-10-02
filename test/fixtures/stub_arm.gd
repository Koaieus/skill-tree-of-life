extends AttackArmMode

## A test-only attack level holding an authored plan — a stub plan subclass, or
## one minted with [method BattleSystem.new_plan] — with no controller and no
## slot. [method stack_holding] stands it on a bare [ArmedStack], so a reader
## wired to that stack sees exactly [param plan] as the armed plan.

const _SELF := preload("res://test/fixtures/stub_arm.gd")

var _held: AttackPlan


func _init(p: AttackPlan) -> void:
	super(null, p.mode if p != null else BattleSystem.AttackMode.NONE)
	_held = p


func on_pushed() -> bool:
	_set_plan(_held)
	return true


func on_popped() -> void:
	_set_plan(null)


## A bare stack (caller frees it) whose attack level holds [param plan].
static func stack_holding(plan: AttackPlan) -> ArmedStack:
	var stack := ArmedStack.new()
	stack.set_root(ArmedMode.new())
	stack.push(_SELF.new(plan))
	return stack
