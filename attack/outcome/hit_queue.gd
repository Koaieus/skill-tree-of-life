class_name HitQueue
extends RefCounted

## The open worklist [method OutcomeApplier.drain] lands from (#1797): the
## unlanded hits of one walk in land order, and a cursor at the next to land.
##
## Land order is `(schedule_index, insertion order)` — the structural key, never
## [member HitInstance.arrival_time] (#543 D2; see
## [method OutcomeApplier.in_arrival_order]). It is also the order the crit
## stream is drawn in ([method CritRoll.decide] runs inside each landing), so
## what this queue yields next is a determinism fact, not a style.
##
## [b]Open[/b]: a landing may [method push] more hits while the queue drains. A
## pushed hit joins the unlanded tail by the same key — after every unlanded
## hit of its own `schedule_index` and before the first of a greater one — and
## never ahead of the cursor: a hit pushed with an index the drain has already
## passed lands next. Nothing pushes today; #1798's gather is the first pusher.

## The record every hit that lands belongs to — the outcome's
## [member AttackOutcome.hits], by reference. [method push] appends here too,
## so the record keeps every hit that landed.
var record: Array[HitInstance] = []
## The hits in land order: [code][0, _cursor)[/code] already handed out,
## [code][_cursor, size)[/code] the unlanded tail, sorted by the land key.
var _order: Array[HitInstance] = []
var _cursor: int = 0


## A queue over [param hits][code][from..][/code], in
## [method OutcomeApplier.in_arrival_order]; [param hits] is the record a
## [method push] appends to. [param from] > 0 is a spell wave: the hits before
## it landed with an earlier wave.
static func over(hits: Array[HitInstance], from: int = 0) -> HitQueue:
	var queue := HitQueue.new()
	queue.record = hits
	queue._order = OutcomeApplier.in_arrival_order(hits.slice(from))
	return queue


func has_next() -> bool:
	return _cursor < _order.size()


## The next hit to land; moves the cursor past it.
func next() -> HitInstance:
	var hit := _order[_cursor]
	_cursor += 1
	return hit


## Append [param hit] to the record and slot it into the unlanded tail by
## `(schedule_index, insertion order)`. A pushed hit is the newest entry, so
## it goes after every unlanded hit with an index no greater than its own.
func push(hit: HitInstance) -> void:
	record.append(hit)
