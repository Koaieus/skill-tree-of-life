class_name LobbyRoster
extends RefCounted

## STUB — signatures only, so the moved test parses and fails on its own asserts.

signal changed

const PENDING_PEER_ID := -1
const HOST_PEER_ID := NetworkTransport.HOST_PEER_ID
const MAX_NAME_LENGTH := 24
const DEFAULT_AI_OPPONENTS := 5
const MAX_AI_OPPONENTS := 12
const PICK_ID := "id"
const PICK_PEER := "peer_id"

var mode: RunConfig.Mode = RunConfig.Mode.SINGLE
var network: NetworkConfig = null
var policy: LobbyPolicy = null
var participants: Array[Participant] = []
var core_preset: CoreClass = null


func _init(mode_in: RunConfig.Mode = RunConfig.Mode.SINGLE, network_in: NetworkConfig = null, policy_in: LobbyPolicy = null) -> void:
	mode = mode_in
	network = network_in
	policy = policy_in


func set_ai_opponents(_count: int) -> void: pass
func ai_opponent_count() -> int: return 0
func set_core_preset(_core: CoreClass) -> void: pass
func pick_color(_p: Participant, _color: Color) -> bool: return false
func pick_core(_p: Participant, _core: CoreClass) -> bool: return false
func reset_core(_p: Participant) -> bool: return false
func pick_camp(_p: Participant, _camp: Faction) -> bool: return false
func pick_name(_p: Participant, _name: String) -> bool: return false
func is_core_overridden(_p: Participant) -> bool: return false
func by_id(_id: int) -> Participant: return null
func can_start() -> bool: return false
func start_blocked_reason() -> String: return ""
func to_run_config(_seed: int = 0, _scenario: Scenario = null, _overrides: Array[ScenarioOverride] = []) -> RunConfig: return null
func to_participant_roster() -> ParticipantRoster: return null
static func build_participants(_mode: RunConfig.Mode, _network: NetworkConfig, _ai_opponents: int) -> Array[Participant]: return []
static func slot_bit_for(_kind: Participant.Kind) -> int: return 0
static func assign_default_cores(_participants_in: Array[Participant]) -> void: pass
static func apply_core_preset(_participants_in: Array[Participant], _picked_cores: Dictionary, _preset: CoreClass) -> void: pass
static func assign_default_colors(_participants_in: Array[Participant], _palette: PlayerPalette) -> void: pass
static func taken_colors(_participants_in: Array[Participant], _except_id: int) -> Array[Color]: return []
static func resolve_mode(_participants_in: Array[Participant]) -> RunConfig.Mode: return RunConfig.Mode.SINGLE
static func is_pending_remote(_p: Participant) -> bool: return false
static func stamp_pending_remote(_roster: ParticipantRoster, _peer_id: int) -> bool: return false
static func may_edit(_p: Participant, _local_peer_id: int, _authors_ai: bool) -> bool: return false
static func may_edit_remotely(_p: Participant, _from_peer: int) -> bool: return false
static func normalize_name(text: String) -> String: return text
static func encode_pick(_participant: Participant, _from_peer: int, _changes: Dictionary) -> Dictionary: return {}
static func parse_seed(_text: String) -> int: return -1
func add_remote(_peer_id: int) -> void: pass
func clear_remote(_peer_id: int, _join_prefs: Dictionary = {}) -> bool: return false
func remove_remote(_peer_id: int) -> bool: return false
func adopt(_roster: ParticipantRoster) -> void: pass
func apply_remote_pick(_pick: Dictionary) -> bool: return false
func has_pending_remote() -> bool: return false
