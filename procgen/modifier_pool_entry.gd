@tool
class_name ModifierPoolEntry
extends Resource

## One pick option in a [ModifierPool]. `cost` is spent from a node's roll
## budget; `weight` biases the weighted pick *among entries still affordable*.

@export var modifier: StatModifierDef
@export var cost: int = 1
@export var weight: float = 1.0
