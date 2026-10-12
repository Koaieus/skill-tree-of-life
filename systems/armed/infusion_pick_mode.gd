class_name InfusionPickMode
extends ArmedMode

## One infusion socket's aspect chooser is open: a leaf over [MagicMode] (or
## the [TargetMode] above it), opened by [method MagicMode.toggle_socket]. It
## mirrors [SpellPickMode] — seat-local, never on the wire, never seen by the
## AI. Its one plan write is [method pick]'s [method MagicAttackPlan.set_socket];
## every other close (a pop on Esc or right-click, a graph click, a spell swap,
## this player's launch) leaves the plan as it was. Every close tolerates the
## chooser already being gone.

var magic: MagicMode
## The socket index the chooser fills.
var socket: int = 0


func _init(p_magic: MagicMode, p_socket: int) -> void:
	magic = p_magic
	ctl = p_magic.ctl
	socket = p_socket


func on_pushed() -> bool:
	stack.selected_spell_changed.connect(_on_spell_changed)
	var bs := ctl.battle_system if ctl != null else null
	if bs != null:
		bs.attack_launched.connect(_on_attack_launched)
	return true


func on_popped() -> void:
	if stack != null and stack.selected_spell_changed.is_connected(_on_spell_changed):
		stack.selected_spell_changed.disconnect(_on_spell_changed)
	var bs := ctl.battle_system if ctl != null else null
	if bs != null and bs.attack_launched.is_connected(_on_attack_launched):
		bs.attack_launched.disconnect(_on_attack_launched)


## Socket [param id] here ([method MagicAttackPlan.set_socket]) and close.
func pick(id: StringName) -> void:
	var plan := magic.plan() as MagicAttackPlan
	if plan != null:
		plan.set_socket(socket, id)
	pop_self()


## Close, and let the click through to the level below.
func handle_left_click(_node: SkillNode) -> bool:
	pop_self()
	return false


func _on_spell_changed(_spell: SpellDef) -> void:
	pop_self()


func _on_attack_launched(_mode: BattleSystem.AttackMode, _spell: SpellDef) -> void:
	var flying := ctl.battle_system.in_flight_plan
	if flying != null and flying.attacker == ctl.player:
		pop_self()


## The chooser has no badge of its own: it shows the magic level's.
func icon() -> Texture2D:
	return magic.icon()


func tint() -> Color:
	return magic.tint()


func icon_tint() -> Color:
	return magic.icon_tint()
