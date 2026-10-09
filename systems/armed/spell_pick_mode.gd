class_name SpellPickMode
extends ArmedMode

## The spell picker is open: a leaf over [MagicMode] or the [TargetMode] above
## it, opened on demand by [method MagicMode.toggle_picker] or by the first
## magic arm with no sticky spell. It writes nothing to the plan — only
## [method ArmedStack.select_spell] — so it is a plain level, not an
## [AttackStepMode] (whose pop undoes plan writes).
##
## It closes on a [method pick], on any other write of the sticky spell (the
## digit hotkeys), on a graph click (which then falls through to the level
## below: Magic targets, Target retargets), on a pop, and on this player's
## launch. Every close tolerates the picker already being gone: a spell swap
## that drops the target makes [TargetMode] pop itself and this level above it
## before this level's own handler runs.

var magic: MagicMode


func _init(p_magic: MagicMode) -> void:
	magic = p_magic
	ctl = p_magic.ctl


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


## Select [param spell] and close. Picking the already-selected spell still
## closes: [method ArmedStack.select_spell] does not emit on an unchanged value.
func pick(spell: SpellDef) -> void:
	stack.select_spell(ctl.player if ctl != null else null, spell)
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


## The picker has no badge of its own: it shows the magic level's.
func icon() -> Texture2D:
	return magic.icon()


func tint() -> Color:
	return magic.tint()


func icon_tint() -> Color:
	return magic.icon_tint()
