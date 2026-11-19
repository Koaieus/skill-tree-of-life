class_name InfusionChoices
extends RefCounted

## The wedges an infusion socket's [AspectWheel] offers — pure statics over a
## [MagicAttackPlan]; the plan owns what a pick would do
## ([method MagicAttackPlan.socket_order_with] / [method MagicAttackPlan.socket_points]).

## The shape socket's index: not one of the aspect sockets.
const SHAPE_SOCKET := -1
## The ride socket's index: not one of the aspect sockets.
const RIDE_SOCKET := -2



## Pick element [param id] in element socket [param field] ([constant SHAPE_SOCKET]
## or [constant RIDE_SOCKET]): a fresh element forges one point, a re-pick of
## the one already there one more, never past its offer ([method field_entries]'
## `value`). A greyed entry is a no-op. True iff the pick was taken.
static func pick_element(plan: MagicAttackPlan, field: int, id: StringName) -> bool:
	if plan == null or plan.spell == null:
		return false
	var entry: AspectWheelEntry = null
	for e in field_entries(plan, field):
		if e.id == id:
			entry = e
	if entry == null or not entry.is_pickable():
		return false
	var current := _forged(plan.infusion, field)
	var pts := mini(current[1] + 1 if current[0] == id else 1, entry.value)
	if field == SHAPE_SOCKET:
		plan.set_shape(id, pts)
	else:
		plan.set_ride(id, pts)
	return true


## The element [param field] forges on [param infusion] and its points, as
## `[id, points]`; `[&"", 0]` when none.
static func _forged(infusion: Infusion, field: int) -> Array:
	if field == SHAPE_SOCKET:
		return [infusion.shape_element, infusion.shape_points] if infusion.shape_points > 0 else [&"", 0]
	return [infusion.ride_element, infusion.ride_points] if infusion.ride_points > 0 else [&"", 0]


## [param spell]'s authored default for element socket [param field] — what an
## unforged infusion answers ([method Infusion.shape_of] / [method Infusion.ride_of]).
static func default_of(spell: SpellDef, field: int) -> StringName:
	var bare := Infusion.innate(spell)
	return bare.shape_of(spell) if field == SHAPE_SOCKET else bare.ride_of(spell)


## The wedges element socket [param field] offers: every [ElementRoster]
## element, in roster order. `value` = the element's count less what the OTHER
## socket spends on it ([method Infusion.spent_on] less this socket's own),
## `checked` = forged here, `mark` = adds / replaces against [method default_of]
## (none against an empty default), `disabled_reason` = the ride refused by the
## spell (rate 0; the ride socket only), else nothing left of the count.
static func field_entries(plan: MagicAttackPlan, field: int) -> Array[AspectWheelEntry]:
	var out: Array[AspectWheelEntry] = []
	if plan == null or plan.spell == null:
		return out
	var spell := plan.spell
	var forged := _forged(plan.infusion, field)
	var default_id := default_of(spell, field)
	var default_element := ElementRoster.shared().by_id(default_id)
	for element in ElementRoster.shared().elements:
		if element == null or element.stat == null:
			continue
		var id := element.id()
		var own: int = forged[1] if forged[0] == id else 0
		var held := AspectCurrency.cap_of(plan.attacker, element.stat.id)
		var entry := AspectWheelEntry.new(id, element.identity,
				maxi(0, held - (plan.infusion.spent_on(id) - own)))
		entry.checked = own > 0
		var mark_text := ""
		if default_element != null:
			var adds := id == default_id
			entry.mark = AspectWheelEntry.MARK_ADDS if adds else AspectWheelEntry.MARK_REPLACES
			mark_text = " · %s %s" % ["adds to" if adds else "replaces",
					default_element.identity.noun]
		entry.hub_text = "%s: %d%s" % [element.identity.noun, entry.value, mark_text]
		if field == RIDE_SOCKET and Infusion.rate_of(spell, id) <= 0.0:
			entry.disabled_reason = "refused by %s" % spell.name
		elif entry.value <= 0:
			entry.disabled_reason = "no %s left" % element.identity.noun
		out.append(entry)
	return out


## Every aspect [param plan]'s caster holds above zero, in [AspectRoster] order,
## as offered to socket [param socket]: `value` = held, `checked` = sits in
## another socket, `disabled_reason` = refused by the spell or no capacity left,
## `hub_text` = the [InfusionExchange] line were it socketed here. A negative
## [param socket] is an element socket: [method field_entries].
static func entries(plan: MagicAttackPlan, socket: int) -> Array[AspectWheelEntry]:
	if socket < 0:
		return field_entries(plan, socket)
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
	out.append_array(_element_entries(plan))
	return out


## Every [ElementRoster] count the caster holds (a default entity reads its `default_value`, even 0), after the aspects, in
## roster order: `identity` tints and badges the wedge, `hub_text` reads
## "Fire attunement: N". An element count is no infusion currency, so the wedge
## is shown but never pickable.
static func _element_entries(plan: MagicAttackPlan) -> Array[AspectWheelEntry]:
	var out: Array[AspectWheelEntry] = []
	for element in ElementRoster.shared().elements:
		if element == null or element.stat == null:
			continue
		var held := AspectCurrency.cap_of(plan.attacker, element.stat.id)
		var entry := AspectWheelEntry.new(element.id(), element.identity, held)
		entry.hub_text = "%s: %d" % [element.stat.display_name, held]
		entry.disabled_reason = "%s is not infusable" % element.stat.display_name
		out.append(entry)
	return out
