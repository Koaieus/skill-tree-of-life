class_name Participant
extends Resource

## One seat in a run — a human at the keyboard, a remote peer, or an AI.
## Plain data; [ParticipantRoster] owns lifecycle, [GameRoot] spawns from it.

enum Kind { LOCAL_HUMAN, REMOTE_HUMAN, AI }

@export var id: int = 0
@export var display_name: String = ""
@export var color: Color = Color.WHITE
@export var camp: Faction = null
@export var kind: Kind = Kind.LOCAL_HUMAN
## 0 = local; the versus hook, unused until a network transport exists.
@export var peer_id: int = 0
