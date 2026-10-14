@tool
class_name DetonateEffect
extends OnHitEffect

## A hit on a charged node sets one explosive charge off before its own riders
## land: a 1-stack spend ([CureInstance]) on the target, then the
## [ExplosiveSpread] blast centred on it, carrying [member riders] with
## explosive stripped (a blast never plants charges) plus [member shrapnel].
## Never built by hand: [method arm] owns the arming rule and prepends it.
##
## Once per node per scope: [member HitLanding.detonated] is built once per
## arrow and once per spell wave; the blast's inners carry a chained copy
## pinned to the same scope, so a blast landing on another charged node sets
## it off too, and nothing goes off twice.
##
## Charges are read on the resolving world: a spell's cast world, else the
## live board (an arrow's riders are compiled before its volley lands). A core
## with no node charges reads its owner's entity-hosted ones.

## The landing's riders a blast carries — explosive already stripped.
var riders: Array[OnHitEffect] = []
## The blast's own damage: a share of the triggering landing's raw amount.
var shrapnel: PairedDamageEffect = null
## A chained copy's scope, shared with the landing that set it off; null on
## the top-level effect, which reads [member HitLanding.detonated].
var _scope: Variant = null

const EXPLOSIVE := &"explosive"


## The arming rule's one owner: [param effects] with a [DetonateEffect]
## prepended — unless they are non-empty and every one lands explosive, in
## which case they only plant and are returned unchanged. A riderless hit
## (empty) still detonates.
static func arm(effects: Array[OnHitEffect]) -> Array[OnHitEffect]:
	if not effects.is_empty() and effects.all(_is_explosive):
		return effects
	var det := DetonateEffect.new()
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
	var present := int(_present(landing))
	if present <= 0:
		return
	scope[landing.target] = true
	landing.hits.append(_spend(landing, def))
	var chained := DetonateEffect.new()
	chained.riders = riders
	chained.shrapnel = shrapnel
	chained._scope = scope
	var inners: Array[OnHitEffect] = [chained]
	if shrapnel != null:
		inners.append(shrapnel)
	inners.append_array(riders)
	spread.blast_for(landing.target, present, inners).apply(landing)


func get_description(_spell: SpellDef = null, _board: StatBoard = null, _read_node: SkillNode = null) -> String:
	return "Sets off one explosive charge on a charged node, blasting this hit's other effects outward."


## The charges present on the target BEFORE the spend: the node's, or, on a
## core holding none, its owner's entity-hosted ones.
func _present(landing: HitLanding) -> float:
	var slice := _world(landing).combat_for(landing.target)
	if slice == null:
		return 0.0
	var power := slice.get_status_power(EXPLOSIVE)
	if power <= 0.0 and slice.is_core() and slice.owner() != null:
		power = slice.owner().get_status_power(EXPLOSIVE)
	return power


## The world this landing resolves against: a spell's cast world, else live.
static func _world(landing: HitLanding) -> CombatWorld:
	var lctx := landing as LandingContext
	if lctx != null and lctx.cast != null and lctx.cast.world != null:
		return lctx.cast.world
	return CombatWorld.live()


## The 1-stack spend, through the cleanse path. It carries the landing's
## pairing, but [method CureInstance.land_on] never checks
## [method HitInstance.rider_gated]: a dud arrow still spends its charge.
static func _spend(landing: HitLanding, def: StatusDef) -> CureInstance:
	var cure := CureInstance.new()
	cure.add(def, 1.0)
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
