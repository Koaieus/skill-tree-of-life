@tool
class_name LobbyPolicy
extends Resource

## What one lobby SHAPE allows its slots to choose (#615).
##
## [b]It hangs on a [MenuGraph.Route], not on a [enum RunConfig.Mode][/b] (#615
## D2). The obvious shape — a `Mode -> LobbyPolicy` table — is keyed on a value
## that is explicitly not authoritative: [method LobbyScreen.configure]'s own
## docstring says the mode passed in is "the shape the menu route ASKED for, not
## the mode the run ends up with", and the real mode does not exist until START
## derives it from the roster (#554 D3). The policy is needed at lobby-OPEN. The
## route is the one thing that exists then and already knows which run it opens,
## so it carries this and there is no second registry to drift.
##
## [b]A null policy is legal and means "today's behaviour".[/b] Every consumer
## treats absence as "no camp control at all, nothing blocks START" — which is
## exactly what the lobby did before this resource existed, and is pinned as a
## characterization test in `test_lobby_roster.gd`. That is what lets a route be
## authored without one.
##
## [b]It does not decide the mode and must not be read as doing so[/b] (#615 D6).
## [method LobbyScreen.resolve_mode] stays the sole mode authority and counts
## HUMAN camps only, so AI camp freedom cannot move the derived mode, and a
## hot-seat policy that locks both humans to `camp_1` keeps resolving
## COOP_HOTSEAT by construction rather than by a check.

## The hard ceiling on distinct camps in one run (#615 D5), and it has zero
## headroom: [code]LobbyScreen._MAX_AI_OPPONENTS[/code] is 4, plus 2 humans is 6
## participants; `entity/factions/` holds exactly `camp_1..camp_6`; and
## `first_level.tres` asks procgen for `n_random_starters = 6`. Those three
## numbers agree today and a free per-slot camp picker fits them precisely —
## raising any one of them is a change to all three.
const MAX_CAMPS := 6

## The camp pool a picker may offer, in dropdown order. Empty means this lobby
## shows no camp control at all — which is the single-player shape, where the
## human is on `player.tres` and every AI shares `npc.tres`.
@export var camps: Array[Faction] = []

## May a HUMAN slot change its camp? False on the hot-seat shape: both humans
## share `camp_1` and the lobby is coop by construction (D6). The control is
## still SHOWN when [member camps] is non-empty — shown and disabled, so a
## player can see the rule rather than wonder where the dropdown went.
@export var human_camps_pickable: bool = false

## May an AI slot change its camp? Independent of the human answer: a hot-seat
## coop lobby locks its two players together and still wants to be able to split
## its opponents into rival camps.
@export var ai_camps_pickable: bool = false

## Ceiling on how many distinct camps this lobby offers, clamped to
## [constant MAX_CAMPS]. Authored per shape so a lobby can be narrower than the
## engine bound without editing [member camps].
@export var max_distinct_camps: int = MAX_CAMPS

## Does START require the humans to span more than one camp? True on the versus
## shape, where a run with every human in one camp has no opposing side and
## [method LobbyScreen.resolve_mode] would quietly hand back COOP_HOTSEAT.
@export var require_distinct_human_camps: bool = false


## May a slot of [param kind] change its camp? Both the human and the AI answer
## are gated on there being a pool to choose from — a policy that permits a pick
## and offers no camps permits nothing.
func may_pick_camp(kind: Participant.Kind) -> bool:
	if camp_choices().is_empty():
		return false
	return ai_camps_pickable if kind == Participant.Kind.AI else human_camps_pickable


## The camps a row's dropdown lists: [member camps] truncated to
## [member max_distinct_camps], itself clamped to [constant MAX_CAMPS]. Never
## longer than the `camp_*.tres` that exist, which is #615 acceptance 4.
func camp_choices() -> Array[Faction]:
	var limit := clampi(max_distinct_camps, 0, MAX_CAMPS)
	var out: Array[Faction] = []
	for camp in camps:
		if camp == null or out.has(camp):
			continue
		if out.size() >= limit:
			break
		out.append(camp)
	return out


## Why START is refused for [param participants], or `""` when it is allowed.
## A string rather than a bool so the reason can reach a player later without
## re-deriving it; today the lobby only asks whether it is empty.
func start_blocked_reason(participants: Array[Participant]) -> String:
	if require_distinct_human_camps and _distinct_human_camps(participants) < 2:
		return "Versus needs the players in different camps."
	return ""


## Distinct camps across the non-AI slots — the same population
## [method LobbyScreen.resolve_mode] counts, deliberately, so this check and the
## derived mode can never disagree about who is a side.
static func _distinct_human_camps(participants: Array[Participant]) -> int:
	var seen: Array[Faction] = []
	for p in participants:
		if p == null or p.kind == Participant.Kind.AI or p.camp == null:
			continue
		if not seen.has(p.camp):
			seen.append(p.camp)
	return seen.size()
