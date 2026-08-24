extends GameRoot

## Procgen sandbox with a live player + AI starters. Inherits the
## [code]game_root.tscn[/code] skeleton; populates entities via
## [method GameRoot._setup_level] so generation runs *after* the systems
## are in the tree but *before* HudRoot composes (it reads player stats).
##
## Enemy territory is grown by [member territory_seeder] (#275, D-19/D-24) —
## a shared, injectable [TerritorySeeder] / [AllocationPolicy] pair, not a
## private random walk. It skips [AllocationSystem.allocate] because that's
## gated on SP/AP -- fine in-game, hostile to one-shot setup -- and uses
## [method AllocationSystem.force_allocate], the same primitive
## [method GameRoot.spawn_entity] composes for the initial core.
##
## The player is seeded with the core node ONLY (D-16's pinned "starting
## nodes: 1") -- it is never handed to [member territory_seeder].

const _STARTER_GROUP := &"procgen_starter"
const _DEFAULT_CORE_CLASS := preload("res://entity/core/balanced_core.tres")
const _DEFAULT_ENEMY_CORE_CLASS := preload("res://entity/core/basic_enemy_core.tres")
const _DEFAULT_TERRITORY_SEEDER := preload("res://procgen/placement/territory_seeder.tres")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _NPC_FACTION := preload("res://entity/factions/npc.tres")

@export var preset: GraphProcgenConfig
@export var player_color: Color = Color(0.4, 0.8, 1.0)
@export var enemy_colors: Array[Color] = [Color(0.95, 0.4, 0.4), Color(1.0, 0.6, 0.2)]
## Class wired onto every spawned entity. The .tres is shared safely — apply()
## duplicates each modifier before installing it on the entity's stat board.
@export var core_class: CoreClass = _DEFAULT_CORE_CLASS
@export var enemy_core_class: CoreClass = _DEFAULT_ENEMY_CORE_CLASS

## Overrides applied to a duplicate of `preset` — leaves the on-disk preset
## untouched so the same resource can serve multiple sandboxes at different
## sizes. 0 = inherit from preset.
@export var node_count_override: int = 50
## Starters to scatter on top of the preset's authored [member
## GraphProcgenConfig.starting_points]. [b]A fallback default[/b] (#553): on the
## legacy generation path the roster decides the count instead, because a run
## needs exactly as many starting points as it has contenders. Still the
## authored value for a preset whose starter count is not roster-driven.
@export var n_random_starters: int = 1
@export var viability_radius: float = 400.0

## Camp shape for the [b]fallback[/b] roster only — the one this level builds
## when it is launched directly (a dev sandbox, a headless test) with no
## [GameSession.roster] to read. Camp 0 is always the local human; every other
## camp is AI on the shared NPC faction — this sandbox owns only two Factions,
## so shapes beyond 2 entries collapse every camp past the first into one NPC
## camp. A run that came from the menu never reads this: the session's roster
## decides the shape, and the roster decides how many camps procgen produces.
@export var camp_sizes: Array[int] = [1, 1]

## Shared allocation-pick strategy (#275, D-24) — greedy BFS ball by default.
## Injectable so a different level scene can swap in another AllocationPolicy
## without touching this script.
@export var territory_seeder: TerritorySeeder = _DEFAULT_TERRITORY_SEEDER

## Target owned-node count for each spawned enemy (core included). D-19:
## enemy level == starting nodes, so this also becomes each enemy's spawn
## level once seeding completes. The player is NEVER expanded — D-16 pins
## player starting nodes at 1 (the core only).
@export var enemy_territory_size: int = 20


func _setup_level() -> void:
	if preset == null:
		push_warning("ProcgenPlaySandbox: assign `preset` in inspector")
		return
	var cfg: GraphProcgenConfig = preset.duplicate(true)
	# #457: one resolved seed for the whole run. A run started from the lobby
	# already has one; a level launched directly (dev sandbox, headless test)
	# opens a session here seeded from the preset's authored value — so either
	# way `cfg.seed` below is concrete and recorded, never a live sentinel.
	GameSession.ensure_started(cfg.seed)
	cfg.seed = GameSession.config.seed
	if node_count_override > 0:
		cfg.node_count = node_count_override
	cfg.viability_radius = viability_radius

	# #553: the roster is decided BEFORE generation and the level only READS it.
	# Two things follow from that order, and both are the point of this unit:
	# the roster tells procgen how many contenders to make room for (rather than
	# procgen deciding how many opponents exist), and #551's `starter_placement`
	# presets can place starters relative to the camp shape.
	#
	# Roster-driven camp + control-kind assignment (#475) — the player and every
	# enemy get their faction from an authored [Participant], not from GameRoot
	# deciding "this entity is named Player".
	var roster: ParticipantRoster = GameSession.roster
	var is_fallback_roster := roster == null or roster.all().is_empty()
	if is_fallback_roster:
		# FALLBACK, not the default path: no lobby ever ran, so there is nothing
		# to consume. A menu-launched run always takes the branch above — and on
		# a client that roster came from the HOST via
		# [method GameSession.apply_received], which is exactly why this level
		# must not write one back over it.
		roster = _fallback_roster()
		GameSession.roster = roster
	var grouped_participants := _camp_grouped_participants(roster)
	cfg.camp_sizes = _camp_sizes(roster, grouped_participants)
	# The roster decides how many starting points to produce, on BOTH generation
	# paths (#551 split them in `GraphProcgen.generate`). With a
	# `starter_placement` set, `cfg.camp_sizes` above already does it and
	# `n_random_starters` is bypassed entirely. Without one — `first_level.tres`,
	# which is what the menu actually launches — the starter list is the preset's
	# authored `starting_points` plus this many, so it is this knob that has to
	# stop being a scene @export independent of who is playing.
	if cfg.starter_placement == null:
		# Counted the way `GraphProcgen` counts them: it skips null entries when
		# it seeds the starter list from `starting_points`, so counting the raw
		# array here would over-subtract and silently under-produce starters.
		var authored := 0
		for sp in cfg.starting_points:
			if sp != null:
				authored += 1
		cfg.n_random_starters = maxi(0, grouped_participants.size() - authored)
	else:
		cfg.n_random_starters = n_random_starters

	# Show the loading bar over a black fade so the procgen wall-clock has a
	# visible heartbeat. SceneTransition is the global fade/progress autoload.
	# `set_faded(true)` snaps to opaque-black (no fade animation needed here —
	# we're populating an empty level, no prior content to fade away from).
	SceneTransition.set_faded(true)
	SceneTransition.progress_bar.show()
	SceneTransition.set_progress(0.0)
	var progress_cb := func(frac: float, _label: String) -> void:
		SceneTransition.set_progress(frac * 100.0)
	var result: Dictionary = await GraphProcgen.generate(cfg, graph, progress_cb)
	var starting_nodes: Array = result.get("starting_nodes", [])
	if starting_nodes.is_empty():
		push_warning("ProcgenPlaySandbox: procgen returned no starting nodes")
		return
	for n in starting_nodes:
		(n as Node).add_to_group(_STARTER_GROUP)

	# Removable blockers (#477): one blocker entity per procgen placement.
	# Spawned before territory seeding so enemy seeding skips already-blocked
	# nodes (AllocationSystem treats them as owned by the blocker entity).
	for placement in result.get("blockers", []):
		spawn_blocker(placement.get("size"), placement.get("node"))

	# Spawn onto the returned nodes in participant order — camp 0 member 0,
	# camp 0 member 1, camp 1 member 0, ... (#551's `starter_placement`
	# contract, held even when no `starter_placement` ran: `cfg.camp_sizes`
	# is inert there). Trim to whichever list came back shorter: the legacy
	# `n_random_starters` path sizes `starting_nodes` off a knob independent
	# of `camp_sizes`, so outside a `starter_placement` preset the two can
	# disagree.
	var spawn_count: int = mini(grouped_participants.size(), starting_nodes.size())
	if spawn_count < grouped_participants.size():
		push_warning("ProcgenPlaySandbox: %d starting nodes for %d camp-planned participants — trimming"
				% [starting_nodes.size(), grouped_participants.size()])

	var entities_by_participant_id: Dictionary = {}
	var enemies: Array[Entity] = []
	# Humans: core only. D-16 pins starting nodes at 1 — no seeding call here.
	#
	# #554: the AI/human split is by KIND, which every peer reads identically off
	# the same roster, and only `player` — the per-machine half — is decided by
	# peer id. Keying the spawn shape off "is this mine" instead would seed each
	# peer's rival with `enemy_territory_size` nodes and its own hero with one,
	# so two peers would build different worlds from the same roster.
	for i in spawn_count:
		var participant: Participant = grouped_participants[i]
		var ent: Entity
		if participant.kind == Participant.Kind.AI:
			var color: Color = enemy_colors[enemies.size() % enemy_colors.size()] if not enemy_colors.is_empty() else Color.RED
			ent = spawn_entity("Enemy_%d" % participant.id, color, starting_nodes[i], enemy_core_class)
			enemies.append(ent)
		elif _is_this_machines(participant):
			ent = spawn_entity("Player", player_color, starting_nodes[i], core_class)
			player = ent
		else:
			ent = spawn_entity("Player_%d" % participant.id, player_color, starting_nodes[i], core_class)
		entities_by_participant_id[participant.id] = ent

	GameRoot.apply_roster(entities_by_participant_id, roster)
	# No `GameSession.roster = roster` here any more (#553). The session owns
	# the live run and therefore owns the roster; a level that wrote its own
	# back would clobber what the lobby agreed — and on a client, what the HOST
	# sent. Only the fallback branch in `_setup_level` seeds one, because there
	# a session genuinely has none.
	#
	# The other half of the same roster: `apply_roster` sets what every machine
	# agrees on (camp, control kind), [SeatPolicy] sets what only this one does
	# (who I play, whose eyes I draw with).
	seat_policy = SeatPolicy.from_roster(
			entities_by_participant_id, roster, GameSession.local_peer_id)

	if player == null:
		push_warning("ProcgenPlaySandbox: no human participant at this peer — nothing bound as player")
		return

	# Wire the player into the interaction layer (input / vision / highlight)
	# now that it exists — edit-time NodePaths can't bind to a node spawned at
	# runtime. `_ready` calls `bind_player` again idempotently; doing it here
	# too sets vision before territory seeding + the fade so the initial fog
	# is correct.
	bind_player(player)

	# Derive seeding RNG from the run's resolved seed so identical seeds produce
	# identical content + enemy territory. Salting with a constant keeps the
	# seeding stream independent of the procgen content stream (so adding or
	# removing modifier rolls upstream doesn't shift seeding). The salt is part
	# of reproducing the MAP, so it stays; what's gone is the second sentinel
	# resolution that used to live on this line (#457).
	var rng := RandomNumberGenerator.new()
	rng.seed = cfg.seed ^ 0x57AB02D
	for e in enemies:
		var achieved := territory_seeder.seed_territory(e, graph, allocation_system, enemy_territory_size, rng)
		# D-19: enemy_level = starting_nodes. Uses the ACTUAL claimed count —
		# a graph that runs dry before `enemy_territory_size` still yields a
		# self-consistent level rather than an inflated one.
		e.level = achieved

	SceneTransition.fade_in()


## Is this participant the human THIS MACHINE plays (#554)?
##
## By [member Participant.peer_id], never by [enum Participant.Kind]: locality
## is a RELATION, not a fact about the participant, and the roster a client
## receives is the HOST's. #562 removed the enum values that let this be asked
## the wrong way at all — the kind now says only HUMAN or AI, and locality
## comes from [method Participant.is_local]. Same shape as
## `.claude/rules/ownership-vocabulary.md`'s rule for `owned_by`: the identity
## question and the "is it mine" question are not the same question.
func _is_this_machines(participant: Participant) -> bool:
	return (participant.kind != Participant.Kind.AI
			and participant.is_local(GameSession.local_peer_id))


## The roster this level invents when there is no session roster to consume —
## a directly-launched sandbox or a headless test, never a menu-launched run.
## Shape comes from [member camp_sizes]: camp 0 is the local human, every other
## camp is AI on the shared NPC faction.
##
## Kept as its own function so the branch that calls it reads as what it is: a
## fallback, not the default path.
func _fallback_roster() -> ParticipantRoster:
	var roster := ParticipantRoster.new()
	var next_id := 0
	for c in camp_sizes.size():
		var camp_faction := _PLAYER_FACTION if c == 0 else _NPC_FACTION
		var kind := Participant.Kind.HUMAN if c == 0 else Participant.Kind.AI
		for _m in maxi(0, camp_sizes[c]):
			var participant := Participant.new()
			participant.id = next_id
			participant.kind = kind
			participant.camp = camp_faction
			roster.add(participant)
			next_id += 1
	return roster


## Groups roster participants by camp, in `roster.camps()` order — the shape
## #551's `starter_placement.plan()` expects and the order its returned
## `StartingPoint`s come back in (camp 0 member 0, camp 0 member 1, camp 1
## member 0, ...).
func _camp_grouped_participants(roster: ParticipantRoster) -> Array[Participant]:
	var camps := roster.camps()
	var buckets: Array[Array] = []
	buckets.resize(camps.size())
	for i in camps.size():
		buckets[i] = []
	for p in roster.all():
		var idx := camps.find(p.camp)
		if idx != -1:
			(buckets[idx] as Array).append(p)
	var flat: Array[Participant] = []
	for b in buckets:
		for p in b:
			flat.append(p)
	return flat


## Camp sizes, in the same `roster.camps()` order [method _camp_grouped_participants]
## flattened — the `Array[int]` shape [StarterPlacement.plan] takes.
func _camp_sizes(roster: ParticipantRoster, grouped: Array[Participant]) -> Array[int]:
	var camps := roster.camps()
	var sizes: Array[int] = []
	sizes.resize(camps.size())
	for i in camps.size():
		sizes[i] = 0
	for p in grouped:
		var idx := camps.find(p.camp)
		if idx != -1:
			sizes[idx] += 1
	return sizes
