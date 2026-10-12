class_name InfusionChoices
extends RefCounted

## The wedges an infusion socket's [AspectWheel] offers — pure statics over a
## [MagicAttackPlan]; the plan owns what a pick would do
## ([method MagicAttackPlan.socket_order_with] / [method MagicAttackPlan.socket_points]).


## Every aspect [param plan]'s caster holds above zero, in [AspectRoster] order,
## as offered to socket [param socket]: `value` = held, `checked` = sits in
## another socket, `disabled_reason` = refused by the spell or no capacity left,
## `hub_text` = the [InfusionExchange] line were it socketed here.
static func entries(plan: MagicAttackPlan, socket: int) -> Array[AspectWheelEntry]:
	var out: Array[AspectWheelEntry] = []
	if plan == null or plan.spell == null:
		return out
	var spell := plan.spell
	var order := plan.infusion.points.keys()
	for aspect in AspectRoster.shared().aspects:
		if aspect == null or aspect.stat == null:
			continue
		var held := AspectCurrency.cap_of(plan.attacker, aspect.stat.id)
		if held <= 0:
			continue
		var id := aspect.id()
		var entry := AspectWheelEntry.new(id, aspect.identity, held)
		var at := order.find(id)
		entry.checked = at >= 0 and at != socket
		var pts: int = plan.socket_points(plan.socket_order_with(socket, id)).get(id, 0)
		entry.hub_text = InfusionExchange.line(spell, id, pts)
		if Infusion.rate_of(spell, id) <= 0.0:
			entry.disabled_reason = "refused by %s" % spell.name
		elif pts <= 0:
			entry.disabled_reason = "At %s's infusion capacity (%d points)" \
					% [spell.name, maxi(0, floori(spell.infusion_capacity))]
		out.append(entry)
	return out
