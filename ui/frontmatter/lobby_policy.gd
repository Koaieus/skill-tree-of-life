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

## --- #642 acceptance 5/6: which MODULES this route may override --------------
##
## #642 shipped the merge path ([ScenarioOverride] / [method RunConfig.overrides]
## / [method RunConfig.resolved_preset]) with no lobby-facing half, because
## `ui/frontmatter/**` was fenced out of that unit's scope. This is that half,
## and it lands here rather than in a new registry for #597 D4's reason: this
## resource already answers "what may this lobby's slots choose", already hangs
## on the [MenuGraph.Route] rather than on the non-authoritative
## [enum RunConfig.Mode], and already treats null as today's behaviour. A second
## table keyed on the same value would only give the two something to drift on.

## The run this route generates (#641). Null means the run carries no
## [Scenario], which is master's behaviour for every route today and leaves
## [method RunConfig.resolved_preset] returning null — so the level falls back
## to its own `preset` export exactly as it always has.
##
## [b]This field is the seam a run-section override travels through, and
## nothing else is.[/b] An override rides [member RunConfig.overrides] and is
## merged onto THIS scenario's `preset`; a run with no scenario has no preset to
## merge onto, so the pickers below are inert without it. That is why it is
## authored per-ROUTE and not picked in the lobby — #643 explicitly descopes a
## base-Scenario picker.
@export var scenario: Scenario = null

## The map-size ladder this route offers, or null for "no map-size control".
## Authored under `ui/frontmatter/lobby_options/` — an ordered [LobbyOptionSet],
## never a directory scan (#597 D13; order IS information, and
## `DirAccess.get_files_at` would return `l, m, s, xl, xs, xxl`).
@export var map_size_options: LobbyOptionSet = null

## The blocker-density ladder, or null for "no blocker control". Note the
## ladder descends: [member GraphProcgenBlockers.blocker_per_small] and friends
## are DENOMINATORS (`floor(node_count / blocker_per_<size>)`), so a bigger
## number means FEWER blockers.
@export var blocker_options: LobbyOptionSet = null

## May the host retune [member BudgetPolicy.base_min] / [member BudgetPolicy.base_max]?
## Raw spinners rather than a ladder, and the one control #643 requires to work
## — see [BudgetRangeRow] for the owner's verbatim reason.
@export var budget_overridable: bool = false


## Does this route offer ANY run-level control? The lobby asks exactly this
## before building the run section, so a route that unlocks nothing renders no
## section at all rather than an empty box — and a NULL policy never reaches
## here, which is #643 acceptance 2 (and #615 D2's null-is-today's-behaviour
## rule) holding by construction rather than by a second check.
func offers_run_section() -> bool:
	return (budget_overridable
			or not _ladder(map_size_options).is_empty()
			or not _ladder(blocker_options).is_empty())


## [param set]'s choices, or `[]` when it is null — the "unlocked but unauthored"
## case, which must read as locked rather than as an empty dropdown.
static func _ladder(set: LobbyOptionSet) -> Array[LobbyOption]:
	return [] if set == null else set.choices()


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
