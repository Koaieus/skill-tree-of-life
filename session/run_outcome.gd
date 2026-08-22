class_name RunOutcome
extends Resource

## Emitted once a run ends — what VictorySystem reports and GameSession
## records. Pure data; no logic of its own.
##
## **Point-of-view-free** (#517): a run has one winner and as many points of
## view as there are machines watching it, so "did *I* lose" is not a fact about
## the run. [HudRoot] answers that at display time from the local [SeatPolicy].
## [member winning_camp] null is a DRAW.

@export var winning_camp: Faction = null
@export var turn_count: int = 0
