class_name LaunchAttackCommand
extends Command

## "Commit this attack plan." The one command in the vocabulary that is
## ASYMMETRIC between the authority and a peer (#511) — and that asymmetry is
## the whole design, so it is stated here rather than discovered later.
##
## [b]Two states, one type.[/b]
##   * [member record] EMPTY — an INITIATE. The authority stamps the seed,
##     resolves, checks affordability, and applies its own outcome with every
##     mode's land-time gate live against the real world. Natural logic, not a
##     precomputed script. It then stamps the record it just produced into
##     this same object, which is what [CommandLink] broadcasts (it encodes on
##     [signal CommandApplier.command_confirmed], which [BattleSystem] raises
##     the instant the record is stamped — so the stamp rides out for free, and
##     without waiting out the host's animation tail).
##   * [member record] POPULATED — a REPLAY. A peer reconstructs the recorded
##     effects; it does not re-resolve, does not re-run a gate, and never
##     computes a combat number.
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

## The post-apply record — [method AttackRecord.capture], replayed with
## [method AttackRecord.rebuild]. Empty means "not applied yet"; see the class
## note.
var record: Dictionary = {}

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


## [b]The one verb that still confirms AFTER it applies (#540 decision 3).[/b]
##
## Not a peer-role exception — a PAYLOAD one. [member record] is stamped by
## [method BattleSystem._compute_record], which runs inside the apply. Confirming
## first would broadcast this command with an EMPTY record, and a peer that
## receives an empty record reads it as an INITIATE (see the class note), takes
## the compute branch it cannot run — it holds no live plan — and refuses the
## attack outright. Every attack would stop crossing.
##
## [b]Deleting this override is a one-line change; #534 is where it happens.[/b]
## What it waits on is the compute half moving out of the apply and into
## [method CommandApplier._validate], so the record is final before the confirm.
## #536 already made that legal — the compute resolves against a
## [method CombatWorld.shadow] and mutates nothing real — it just did not move
## it, because until #540 landed decision 4 the confirm was also where
## [CommandLink] sampled its POST-mutation fingerprint.
func confirms_before_apply() -> bool:
	return false


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
