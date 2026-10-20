@tool
class_name DetonateEffect
extends OnHitEffect

## A hit detonates before its own riders land: its explosive [member load]
## meets the charges present on the target — a spend ([CureInstance],
## [method spend_of]) on the target, then the [ExplosiveSpread] blast centred
## on it at [method power_of], carrying [member riders] with explosive stripped
## (a blast never plants charges) plus [member shrapnel]. Load 0 on a clean
## node is no detonation. Never built by hand: [method arm] owns the arming
## rule and prepends it.
##
## Once per node per scope: [member HitLanding.detonated] is built once per
## arrow and once per spell wave; the blast's inners carry a chained copy
## pinned to the same scope, so a blast landing on another charged node sets
## it off too, and nothing goes off twice.
##
## Charges are read on the resolving world: a spell's cast world, else the
## live board. An arrow's riders are compiled before its volley lands, so on
## the live board every spend is also tallied in a per-compile ledger riding
## [member HitLanding.gather_cache] (key [constant SPENT_KEY]) and subtracted
## from the read: a volley never booms more times than the board has charges.
## A core with no node charges reads — and spends — its owner's entity-hosted
## ones.

## The landing's riders a blast carries — explosive already stripped.
var riders: Array[OnHitEffect] = []
## The blast's own damage: a share of the triggering landing's raw amount.
var shrapnel: PairedDamageEffect = null
## The hit's own explosive load (a spell's [DetonateUse] load); 0 for an arrow, a
## blade and a chained copy — a blast is a zero-load hit on each neighbour.
var load: int = 0
## A chained copy's scope, shared with the landing that set it off; null on
## the top-level effect, which reads [member HitLanding.detonated].
var _scope: Variant = null

const EXPLOSIVE := &"explosive"
## The [member HitLanding.gather_cache] key of the per-compile spend ledger:
## holder ([NodeCombat] or [EntityCombat]) → charges already spent.
const SPENT_KEY := &"detonate_spent"


## The arming rule's one owner: [param effects] with a [DetonateEffect] at
## [param load] prepended — unless any one lands explosive: that is a [PlantUse]
## hit, which never blasts, and they are returned unchanged. A riderless hit
## (empty) still detonates.
static func arm(effects: Array[OnHitEffect], load: int = 0) -> Array[OnHitEffect]:
	if effects.any(_is_explosive):
		return effects
	var det := DetonateEffect.new()
	det.load = maxi(load, 0)
	det.riders = strip(effects)
	det.shrapnel = PairedDamageEffect.new()
	var out: Array[OnHitEffect] = [det]
	out.append_array(effects)
	return out


## [param effects] minus every effect that lands explosive (wrappers too,
## through [method OnHitEffect.status_def]).
static func strip(effects: Array[OnHitEffect]) -> Array[OnHitEffect]:
	var out: Array[OnHitEffect] = []
	for e in effects:
		if not _is_explosive(e):
			out.append(e)
	return out


static func _is_explosive(e: OnHitEffect) -> bool:
	if e == null:
		return false
	var def := e.status_def()
	return def != null and def.id == EXPLOSIVE


## Charges a hit with [param load] spends off [param present]: none on a clean
## node, else `max(1, min(load, present))` — a spark always takes one.
static func spend_of(load: int, present: int) -> int:
	if present <= 0:
		return 0
	return maxi(1, mini(load, present))


## A detonation's power: `load + present + 2·r·min(load, present)`, the
## shared chunk weighted [param resonance] on each side. 0 = no blast.
static func power_of(load: int, present: int, resonance: int) -> int:
	var shared := mini(load, present)
	return maxi(load, 0) + maxi(present, 0) + 2 * resonance * maxi(shared, 0)


func apply(landing: HitLanding) -> void:
	if landing == null or landing.target == null:
		return
	var scope: Dictionary = _scope if _scope != null else landing.detonated
	if scope.has(landing.target):
		return
	var def := _explosive_def()
	var spread := def.spread as ExplosiveSpread if def != null else null
	if spread == null:
		return
	var held := _present(landing)
	var present := maxi(int(held[1]), 0)
	var power := power_of(load, present, spread.resonance)
	if power <= 0:
		return
	scope[landing.target] = true
	var spent := spend_of(load, present)
	if spent > 0:
		if not _resolves_on_cast(landing):
			var ledger := _ledger(landing)
			ledger[held[0]] = ledger.get(held[0], 0.0) + float(spent)
		landing.emit(_spend(landing, def, held[0] is EntityCombat, spent))
	var chained := DetonateEffect.new()
	chained.riders = riders
	chained.shrapnel = shrapnel
	chained._scope = scope
	var inners: Array[OnHitEffect] = [chained]
	if shrapnel != null:
		inners.append(shrapnel)
	inners.append_array(riders)
	spread.blast_for(landing.target, power, inners).apply(landing)


func get_description(_spell: SpellDef = null, _board: StatBoard = null, _read_node: SkillNode = null) -> String:
	return "Sets off the explosive charges on a charged node, blasting this hit's other effects outward."


## `[holder, charges]`: the charges present on the target BEFORE the spend,
## less any this compile already spent — the node's, or, on a core with none
## left, its owner's entity-hosted ones. The holder is what the spend clears.
func _present(landing: HitLanding) -> Array:
	var slice := _world(landing).combat_for(landing.target)
	if slice == null:
		return [null, 0.0]
	var ledger: Dictionary = {} if _resolves_on_cast(landing) else _ledger(landing)
	var power := slice.get_status_power(EXPLOSIVE) - float(ledger.get(slice, 0.0))
	if power <= 0.0 and slice.is_core() and slice.owner() != null:
		var core := slice.owner()
		return [core, core.get_status_power(EXPLOSIVE) - float(ledger.get(core, 0.0))]
	return [slice, power]


## Whether [param landing] reads a spell's cast world, where every spend has
## landed before the next wave reads — no ledger needed there.
static func _resolves_on_cast(landing: HitLanding) -> bool:
	var lctx := landing as LandingContext
	return lctx != null and lctx.cast != null and lctx.cast.world != null


static func _ledger(landing: HitLanding) -> Dictionary:
	if not landing.gather_cache.has(SPENT_KEY):
		landing.gather_cache[SPENT_KEY] = {}
	return landing.gather_cache[SPENT_KEY]


## The world this landing resolves against: a spell's cast world, else live.
static func _world(landing: HitLanding) -> CombatWorld:
	if _resolves_on_cast(landing):
		return (landing as LandingContext).cast.world
	return CombatWorld.live()


## The [param count]-stack spend, through the cleanse path — off the core's entity rows
## when [param on_core]. It carries the landing's pairing, so a dud hit spends
## nothing ([method HitInstance.rider_gated]).
static func _spend(landing: HitLanding, def: StatusDef, on_core: bool, count: int) -> CureInstance:
	var cure := CureInstance.new()
	cure.add(def, float(count), on_core)
	cure.attacker = landing.attacker
	cure.source = landing.source
	cure.origin = landing.origin
	cure.read_node = landing.read_node
	cure.target = landing.target
	cure.structural_key = landing.structural_key
	cure.paired = landing.paired
	cure.hit_key = landing.hit_key
	return cure


static func _explosive_def() -> StatusDef:
	var roster := StatusRoster.shared()
	return roster.by_concept(EXPLOSIVE) if roster != null else null
