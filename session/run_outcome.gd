class_name RunOutcome
extends Resource

## Emitted once a run ends — what VictorySystem reports and GameSession
## records. Pure data; no logic of its own.

enum LocalResult { WIN, LOSS, DRAW }

@export var winning_camp: Faction = null
@export var local_result: LocalResult = LocalResult.DRAW
@export var turn_count: int = 0
