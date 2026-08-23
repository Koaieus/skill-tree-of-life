class_name LaunchAttackCommand
extends Command

## "Commit this attack plan." The one command in the vocabulary that is
## ASYMMETRIC between the authority and a peer (#511) — and that asymmetry is
## the whole design, so it is stated here rather than discovered later.
##
## [b]Two states, one type.[/b]
##   * [member record] EMPTY — an INITIATE. Nobody has computed this attack yet.
##     [method BattleSystem.prepare_launch_command] stamps the seed, resolves on
##     a shadow, checks affordability, and stamps the record it produced into
##     this same object — all of it BEFORE the command confirms (#545), so
##     [CommandLink] broadcasts a complete record and the authority mutates
##     nothing until every peer has been told.
##   * [member record] POPULATED — the attack is decided and what remains is a
##     REPLAY: rebuild the recorded effects and land them. Since #545 that is
##     the state the authority is in too by the time it applies, which is why
##     "who computed it" is [member computed_here] and not
##     `record.is_empty()`.
##
## Why not two command types: a peer that received an initiate would have to
## know it is not the authority to refuse it, which is a role split #511
## explicitly does not build. One type whose payload says which half of the
## work has already been done needs no role at all — and when #463 adds the
## intent channel upward, a client's intent IS this command with an empty
## record.
##
## [member plan] rides along in BOTH states. It is not redundant on the replay
## path: melee reforms its blade from the plan to DRAW the swing
## (deterministic, mutates nothing — see `docs/domain/multiplayer-sync-model.md`
## on why re-simulating to draw is not re-simulating to derive), and magic
## needs the spell to find its VFX coordinator scene.

const TAG: StringName = &"launch_attack"

## The plan's wire form — [method AttackPlan.to_dict], rebuilt with
## [method AttackPlanCodec.from_dict].
var plan: Dictionary = {}

## The resolved record — [method AttackRecord.capture], replayed with
## [method AttackRecord.rebuild]. Empty means "nobody has computed this attack
## yet"; see the class note.
var record: Dictionary = {}

## [b]Did THIS machine compute [member record][/b] — set by
## [method BattleSystem.prepare_launch_command] when it resolves, read by
## [method BattleSystem.apply_launch_command] to decide whether the live
## [member BattleSystem.attack_plan] is this command's plan or whether the plan
## has to be rebuilt from [member plan].
##
## [b]Transient applier state — deliberately absent from [method to_dict] and
## [method from_dict][/b], exactly like [member Command.pre_fingerprint] and for
## the same two reasons: a received command is by definition one this machine did
## not compute (so false is the only correct value off the wire), and
## `test/fixtures/outcome/*.tres` IS a serialized dictionary of this type (#539),
## so a new wire field invalidates every committed fixture.
##
## It replaced `record.is_empty()` when the compute moved ahead of the confirm
## (#545): the authority now reaches [method BattleSystem.apply_launch_command]
## with a POPULATED record, so emptiness no longer distinguishes the halves.
var computed_here: bool = false

## The seed the authority stamped for this attack, carried separately from
## [member record] because it is an INPUT to resolution, not a result of it.
## Handed (plan + seed), the authority can re-resolve and compare — the
## "verify by re-resolving" half of the sync model. That is a host-side
## verification hook; a peer reconstructs from [member record] instead.
var resolve_seed: int = 0


func _init(entity_id_: int = 0, plan_: Dictionary = {}, resolve_seed_: int = 0) -> void:
	super(entity_id_)
	plan = plan_
	resolve_seed = resolve_seed_


func type_tag() -> StringName:
	return TAG


func to_dict() -> Dictionary:
	var d := super()
	d["plan"] = plan
	d["record"] = record
	d["seed"] = resolve_seed
	return d


static func from_dict(d: Dictionary) -> LaunchAttackCommand:
	var command := LaunchAttackCommand.new(
		int(d.get("entity_id", 0)),
		d.get("plan", {}),
		int(d.get("seed", 0)),
	)
	command.record = d.get("record", {})
	return command
