extends Node

## The live run (#457): what was asked for ([RunConfig]), who is in it
## ([ParticipantRoster]), and how it ended ([RunOutcome]). An autoload, so a
## level can read the run it belongs to across the menu→level scene swap
## without a hand-carried node.
##
## [b]Its one hard job is the determinism contract.[/b] [member RunConfig.seed]
## is resolved EXACTLY ONCE, up front, in [method start] — before any level
## builds. `seed == 0` is the authoring sentinel for "randomise me"; every
## consumer downstream reads the concrete resolved value off
## [code]GameSession.config.seed[/code], so a good run can be replayed by
## typing its seed back into the lobby.
##
## [b]The seed is for procgen. Nothing else.[/b] Owner call, 2026-08-21 (#457),
## verbatim: [i]"we don't care about that seed beyond the procgen using it, for
## now. possibly forever."[/i] Combat reproducibility comes from the per-attack
## [member AttackPlan.resolve_seed] stamped by [BattleSystem] (`8dc6f77`), and
## loot rolls are deliberately host-only per #473 — see
## [code]test/unit/attack/test_attack_determinism.gd[/code], which pins that on
## purpose. So: [b]the same seed reproduces the same MAP, not the same
## FIGHTS.[/b] That is the normal roguelike bargain and an explicit choice.
## Do NOT thread this seed into [BattleSystem], [SpellResolver], [LootSystem]
## or [SkillDustAddon].

## Fired once a run's config is settled and its seed resolved.
signal run_started(config: RunConfig)
## Fired when the run's terminal state has been recorded here.
signal run_recorded(outcome: RunOutcome)

## The run being played. Null between runs. Its `seed` is always concrete
## (non-zero) while a run is live.
var config: RunConfig = null

## Who is in the run — and since #553, the level [b]consumes[/b] this rather
## than handing one back. It is authored before the level loads (by the lobby,
## or by [method apply_received] from the host on a client) and it is what
## decides how many contenders a level spawns and how many starting points
## procgen is asked for. The one level that still writes here is a directly
## launched sandbox with no lobby behind it, seeding its own fallback.
var roster: ParticipantRoster = null

## Which [member Participant.peer_id] in [member roster] is THIS machine (#553).
## The per-machine half of the roster, and the input [method
## SeatPolicy.from_roster] needs to tell "my human" from "the other machine's
## human" — with every participant sharing this value, a seat policy can only
## ever be a couch.
##
## [b]Zero until #554 fills it in[/b], which is deliberate rather than
## unfinished: a real id is assigned by the transport when the link comes up,
## and a level's `_setup_level` runs before [GameRoot] has even adopted its
## network role. So it cannot be read live at level setup — the host stamps the
## joining peer and the client learns its own at handshake, both of which are
## #554's mechanism. Single-player and hot-seat correctly stay at 0 forever.
var local_peer_id: int = 0

## How the run ended, recorded off [signal Events.run_ended]. Null until then.
var outcome: RunOutcome = null

## How THIS MACHINE reaches the other one (#531). Deliberately NOT part of
## [member config]: that crosses the wire by value, and a role is the one thing
## every peer must answer differently — see [NetworkConfig]. Null reads as
## offline. Written by the menu before [method start], read once by
## [GameRoot] at level start, and cleared by [method end] along with the run
## it belonged to. [method start] leaves it alone on purpose: the menu picks a
## role BEFORE it picks a seed, so clearing here would erase the choice that
## routed the player to this lobby in the first place.
var network: NetworkConfig = null


func _ready() -> void:
	Events.run_ended.connect(_on_run_ended)


func is_active() -> bool:
	return config != null


## Begin a run. Resolves the seed sentinel once, here, and nowhere else.
## The lobby's START calls this immediately before routing to the level.
##
## [b]The roster is opened from [member RunConfig.participants] (#554).[/b] It
## used to open EMPTY, which made this the odd one out against
## [method apply_received] directly below — that one sets a real roster, and the
## asymmetry was a bug with a visible symptom: since #553 the level consumes
## [member roster] and treats an empty one as "no lobby ran", so every
## menu-launched run silently fell into `procgen_play_sandbox`'s fallback shape
## (one human, one NPC camp) no matter what the lobby had authored.
##
## A config with no participants still opens an empty roster, and must: that is
## exactly what [method ensure_started] passes, and its emptiness is the signal
## that tells a directly-launched sandbox to invent its own.
##
## Goes through [method ParticipantRoster.add] per participant rather than
## writing the array, so `participant_joined` / `roster_changed` fire for a
## lobby-authored participant exactly as they do for one that arrived over the
## wire.
func start(cfg: RunConfig) -> void:
	assert(cfg != null, "GameSession.start: null RunConfig")
	config = cfg
	config.seed = RunConfig.resolve_seed(config.seed)
	roster = ParticipantRoster.new()
	for participant in config.participants:
		roster.add(participant)
	outcome = null
	run_started.emit(config)


## Accept a run's shape from the HOST — the setup half of #528's join
## handshake, the counterpart to [method start] for a peer instead of the
## machine that decided the run. [b]Does NOT resolve the seed[/b]: unlike
## [method start], [param cfg.seed] already IS the host's resolved value
## ([method RunConfig.to_dict] / [method RunConfig.from_dict] carry it as-is),
## so re-resolving here would hand this peer a different map than everyone
## else's. [param received_roster] is [method ParticipantRoster.from_dict]'s
## result — this method doesn't decode the wire payload itself, so a
## [CommandLink] caller can decode once and reuse the roster for logging
## before handing it here.
func apply_received(cfg: RunConfig, received_roster: ParticipantRoster) -> void:
	assert(cfg != null, "GameSession.apply_received: null RunConfig")
	assert(cfg.seed != 0, "GameSession.apply_received: unresolved seed (0) crossed the wire")
	config = cfg
	roster = received_roster if received_roster != null else ParticipantRoster.new()
	outcome = null
	run_started.emit(config)


## Start a default run if none is live, seeding it from `fallback_seed` (a
## level scene's authored preset seed; 0 means "randomise me" as usual).
##
## This is how a level launched directly — a dev sandbox, a test, `godot
## --path . scenes/procgen_play_sandbox.tscn` — still gets exactly one resolved
## seed without a lobby. A run that IS live is left alone, which is a
## deliberate choice with one visible consequence: the pause menu's restart
## (`reload_current_scene`) replays the SAME map rather than rolling a new one.
## Retry-this-map is the semantic we want there; "give me a different map" is
## menu → new game, which calls [method start] afresh.
func ensure_started(fallback_seed: int = 0) -> void:
	if is_active():
		return
	var cfg := RunConfig.new()
	cfg.seed = fallback_seed
	start(cfg)


## Drop the live run. Called when leaving a finished run for the menu, so the
## next [method ensure_started] resolves a fresh seed instead of inheriting a
## spent one. Tests call it in `before_each` for the same reason: an autoload
## outlives every test in GUT's single process.
##
## [member outcome] deliberately SURVIVES: a run ends and is routed away from
## in the same breath, so clearing it here would delete the terminal state at
## the exact moment a results screen would want to read it. [method start] is
## what clears it, which is the moment a stale outcome could actually mislead.
## [method is_active] keys off [member config], so a surviving outcome never
## makes a dead run look live.
func end() -> void:
	config = null
	roster = null
	# The wire belonged to the run: a player who hosted once and then starts a
	# solo game must not silently open a socket again.
	network = null


func _on_run_ended(run_outcome: RunOutcome) -> void:
	outcome = run_outcome
	run_recorded.emit(run_outcome)
