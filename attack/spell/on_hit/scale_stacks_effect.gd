@tool
class_name ScaleStacksEffect
extends SpellOnHitEffect

## Writes [member LandingContext.stack_scale] at a landing, optionally gated by
## a [LandingCondition]: every [StatusInstance] this landing then mints — an
## authored [ApplyStatusEffect] or an affinity rider — lands its FOLDED stacks
## × that scale ([method StatusInstance.land_on]). Emits nothing itself;
## author it in [member SpellDef.on_hit_effects], which run before the riders.
##
## [b]Unlike [ScaleDamageEffect], it never touches the payload[/b], so nothing
## compounds down the walk: each landing is scaled by its own node alone. A
## scale of 0 lands 0 stacks however much `<family>_stacks_per_hit` is
## invested — that is Defile's blank-node immunity.

## Null means "always" — an unconditional scale.
@export var when: LandingCondition = null
## The scale is this ranker's score of the landed node; null falls back to
## [member factor].
@export var ranker: NodeRanker = null
## Used only when [member ranker] is null.
@export var factor: float = 1.0


func _apply_spell(lctx: LandingContext) -> void:
	if lctx.node == null and lctx.target == null:
		return
	if when != null and not when.evaluate(lctx):
		return
	var node: SkillNode = lctx.target if lctx.target != null else lctx.node
	var scale := ranker.score(node, lctx) if ranker != null else factor
	lctx.stack_scale = maxf(scale, 0.0)


## A multiplier, not an absolute — [param _spell]/[param _board] are unused,
## kept only to match [method OnHitEffect.get_description].
func get_description(_spell: SpellDef = null, _board: StatBoard = null) -> String:
	var what := "Status stacks × %s" % (ranker.get_description() if ranker != null else NumFmt.num(factor))
	if when == null:
		return what + "."
	var gate := when.get_description()
	if gate == "":
		return what + ", conditionally."
	return "%s %s." % [what, gate]
