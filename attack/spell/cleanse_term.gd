@tool
class_name CleanseTerm
extends Resource

## One thing a cleanse does with the stacks it cleared — the SPELL's side of
## a cleanse's price. What a stack is worth is the status's fact
## ([method StatusDef.cleanse_worth]); whether the clears heal, cost the
## target its worth in HP, or nothing at all is a list of these on the
## cleansing effect ([member CureEffect.terms]); an empty list is a free
## cleanse.
##
## A term runs after its effect appended the [CureInstance] (so a hit it
## appends lands after the clears), on the world the walk reads: it reads
## [member CureInstance.defs] / [member CureInstance.cleared] /
## [member CureInstance.on_core], may set fields on that hit, and may append
## hits to `lctx.cast.outcome.hits`. Every cleansing effect runs its list
## through [method settle_all] — one runner, no mirror. Shared by reference
## between casts: stateless.


## Abstract: the base does nothing.
func settle(_hit: CureInstance, _lctx: LandingContext) -> void:
	pass


## The tooltip fragment this term adds ("healing 1 per stack cleared"), or
## "" for none.
func describe() -> String:
	return ""


## Run [param list] in order over [param hit]; null entries are skipped.
static func settle_all(list: Array[CleanseTerm], hit: CureInstance, lctx: LandingContext) -> void:
	for t in list:
		if t != null:
			t.settle(hit, lctx)


## The non-empty fragments of [param list], in order.
static func describe_all(list: Array[CleanseTerm]) -> Array[String]:
	var out: Array[String] = []
	for t in list:
		if t != null:
			var line := t.describe()
			if line != "":
				out.append(line)
	return out


## Σ [member CureInstance.cleared] over [param hit] — core and node parts alike.
static func cleared_total(hit: CureInstance) -> float:
	var total := 0.0
	for c in hit.cleared:
		total += c
	return total
