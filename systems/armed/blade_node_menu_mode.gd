class_name BladeNodeMenuMode
extends ArmedMode

## A picked node's management menu is open: a leaf over [BladeMode], pushed by
## a left-click on the pivot or a member. Seat-local, never on the wire. It
## undoes nothing on pop — popping the blade pops it too, and every close but
## [method pick] and [method unpick] leaves the plan as it was. The HUD's
## [BladeNodeMenu] shows it; this level owns what the menu's buttons do.
## An armed [TempUpgradeMode] sits above the blade instead and wins the click,
## so no menu opens while a card is armed. See docs/domain/click-grammar.md.

var blade: BladeMode
## The picked node the menu manages — the pivot or a member.
var node: SkillNode


func _init(p_blade: BladeMode, p_node: SkillNode) -> void:
	blade = p_blade
	ctl = p_blade.ctl
	node = p_node


func plan() -> MeleeAttackPlan:
	return blade.parent.plan() as MeleeAttackPlan if blade != null else null


## The hub's un-pick — the click [BladeMode] used to take directly: on the
## pivot it pops the blade (clearing the pivot, and this menu with it); on a
## member it drops the member and closes the menu.
func unpick() -> void:
	var p := plan()
	if p == null:
		pop_self()
	elif node == p.source:
		blade.pop_self()
	else:
		p.toggle_member(node)
		pop_self()


## A fan pick: toggle [param scene] on this node through the seat's one door
## ([method PlayerInputController.request_temp_upgrade_at]), then close — the
## pick arms nothing.
func pick(scene: PackedScene) -> void:
	if ctl != null:
		ctl.request_temp_upgrade_at(node, scene)
	pop_self()


## The [param offered] kinds a pick here would change, in their order
## ([method MeleeAttackPlan.placeable_temp_kinds]).
func placeable(offered: Array[PackedScene]) -> Array[PackedScene]:
	var p := plan()
	if p == null:
		var none: Array[PackedScene] = []
		return none
	return p.placeable_temp_kinds(node, offered)


## The kinds among [param kinds] this node already carries as a temp addon —
## the cards that draw lit, whose pick refunds.
func carried(kinds: Array[PackedScene]) -> Array[PackedScene]:
	var out: Array[PackedScene] = []
	if node == null:
		return out
	for scene in kinds:
		for a in node.get_addons():
			if a.is_temporary and a.get_kind() == scene.resource_path:
				out.append(scene)
				break
	return out


## Close, and let the click through to the blade below: a click on another
## node picks, un-picks or opens that node's menu as if this one were shut.
func handle_left_click(_node: SkillNode) -> bool:
	pop_self()
	return false


## The menu has no badge of its own: it shows the blade's.
func icon() -> Texture2D:
	return blade.icon()


func tint() -> Color:
	return blade.tint()


func icon_tint() -> Color:
	return blade.icon_tint()
