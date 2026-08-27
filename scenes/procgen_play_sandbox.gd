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
##
## [b]This level consumes a run; it never invents one (#584).[/b] Both
## [member GameSession.config] and [member GameSession.roster] must already be
## populated when [method _setup_level] runs, and the level refuses to generate
## rather than inventing a substitute. Two composers fill them, and the level
## cannot tell which: the lobby ([method GameSession.start] from
## `meta_root.gd`), or a [RunBootstrap] child holding an authored `RunConfig`
## `.tres` — which is all `scenes/first_level_sandbox.tscn` adds on top of
## `scenes/level.tscn`. That indifference is the invariant worth keeping: a
## sandbox that parsed its settings differently from a lobby-launched run would
## stop being a rehearsal of the real game.

const _STARTER_GROUP := &"procgen_starter"
const _DEFAULT_CORE_CLASS := preload("res://entity/core/balanced_core.tres")
const _DEFAULT_ENEMY_CORE_CLASS := preload("res://entity/core/basic_enemy_core.tres")
const _DEFAULT_TERRITORY_SEEDER := preload("res://procgen/placement/territory_seeder.tres")

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
@export var viability_radius: float = 400.0

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
	# #463: on a joining CLIENT, everything below reads a run this machine does
	# not own — `cfg.seed` and the roster alike are the host's, and until the
	# host's `run_setup` lands they are still this lobby's wish. Generating
	# first and reconciling after cannot be repaired: `Graph` mints `entity_id`
	# by add-order and a join lobby is offered no AI-count row, so a client that
	# guessed would spawn a different entity SET and slide every id past the
	# first mismatch. See [method GameRoot.await_host_run]. No-op for the host
	# and for every offline launch, which is why this sits ahead of the
	# `is_active` guard rather than inside a network branch of it.
	await await_host_run()
	var cfg: GraphProcgenConfig = preset.duplicate(true)
	# #457: one resolved seed for the whole run. A run started from the lobby
	# already has one; a level launched directly (dev sandbox, headless test)
	# opens a session here seeded from the preset's authored value — so either
	# way `cfg.seed` below is concrete and recorded, never a live sentinel.
	if not GameSession.is_active():
		push_error("%s: no run is open. A level GENERATES a run, it does not "
				% name + "invent one — start the session first, from the lobby "
				+ "or from a RunBootstrap child holding an authored RunConfig.")
		return
	# #457: one resolved seed for the whole run, resolved by `GameSession.start`
	# before anything reached this scene. The preset's authored seed is an
	# authoring default that the run has already superseded.
	cfg.seed = GameSession.config.seed
	if node_count_override > 0:
		# #349 acceptance 4: `topology` is a top-level module `.tres`
		# (ExtResource), so `preset.duplicate(true)` above did NOT deep-copy
		# it — only embedded SubResources cross that boundary. Writing
		# `node_count` straight onto `cfg.topology` would mutate the shared,
		# cached, on-disk Topology module and leak into every subsequent run
		# in this process. Re-duplicate it first so the stamp lands on a
		# private copy, same as `cfg` itself already is.
		cfg.topology = cfg.topology.duplicate(true)
		cfg.topology.node_count = node_count_override
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
	if roster == null or roster.all().is_empty():
		push_error("%s: the run has no participants. " % name
				+ "This level spawns FROM a roster and no longer invents one (#584) — "
				+ "whoever opened the session owes it a populated `participants` list.")
		return
	var grouped_participants := _camp_grouped_participants(roster)
	cfg.camp_sizes = _camp_sizes(roster, grouped_participants)
	# The roster decides how many starting points to produce, on BOTH generation
	# paths (#551 split them in `GraphProcgen.generate`). With a
	# `starter_placement` set, `cfg.camp_sizes` above already does it and
	# `n_random_starters` is bypassed entirely. Without one — `first_level.tres`,
	# which is what the menu actually launches — the starter list is the preset's
	# authored `starting_points` plus this many, so it is this knob that has to
	# stop being a scene @export independent of who is playing.
	if cfg.starting.starter_placement == null:
		# Counted the way `GraphProcgen` counts them: it skips null entries when
		# it seeds the starter list from `starting_points`, so counting the raw
		# array here would over-subtract and silently under-produce starters.
		var authored := 0
		for sp in cfg.starting.starting_points:
			if sp != null:
				authored += 1
		cfg.n_random_starters = maxi(0, grouped_participants.size() - authored)
	# No `else`. On the `starter_placement` path `plan()` replaces the starter
	# list wholesale and `GraphProcgen` never reads `n_random_starters` at all
	# (`graph_procgen.gd` calls `_place_random_starters` only in the other
	# branch), so the write this used to do had no reader. The scene export it
	# copied from is gone with it: after #584 the roster is the only thing that
	# says how many contenders exist, and a second knob that reads like the
	# opponent count is precisely the defect this issue opened on.

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
		spawn_blocker(placement.get("size"), placement.get("node"),
				placement.get("prune_seed", 0), cfg.blockers.blocker_spell_prune_m)

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
		# #563 D1: the ROSTER decides the colour, for every entity alike. The
		# `player_color` / `enemy_colors` exports below are reached only through
		# `resolve_spawn_color`'s fallback arm, and only for a participant that
		# carries no colour at all.
		var color := resolve_spawn_color(
				participant, player_color, enemy_colors, enemies.size())
		# #618 D3: and the roster decides the CLASS the same way. The
		# `core_class` / `enemy_core_class` exports below are the fallback for a
		# participant that carries none, not the answer.
		var core := resolve_spawn_core(participant, core_class, enemy_core_class)
		if participant.kind == Participant.Kind.AI:
			ent = spawn_entity("Enemy_%d" % participant.id, color, starting_nodes[i], core)
			enemies.append(ent)
		elif _is_this_machines(participant):
			ent = spawn_entity("Player", color, starting_nodes[i], core)
			player = ent
		else:
			ent = spawn_entity("Player_%d" % participant.id, color, starting_nodes[i], core)
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


## What colour does this participant's entity render in (#563)?
##
## [b]The roster is authoritative.[/b] Owner call, 2026-08-26, verbatim:
##
## [i]"The roster is authoritative for hero colour. `Participant.color` is real
## run shape, it crosses the wire, and every peer draws every hero in the colour
## its lobby slot chose."[/i]
##
## That REVERSES #563's own opening Note, which called colour a per-machine
## presentation choice belonging to [SeatPolicy]. It does not: it is run shape,
## it replicates, and it is what makes the lobby's per-slot colour picker (#616)
## mean anything. See `docs/domain/seat-policy.md` § "One axis".
##
## Human and AI take the same path — there is no "is this mine" branch here, and
## adding one would be the #563 bug in its original form (two humans both
## drawing in `player_color`, territory indistinguishable).
##
## [param player_fallback] / [param enemy_fallback] are the scene exports, and
## are reached ONLY when the participant carries no colour (#563 D2 — the
## authored-sandbox path, which has no lobby to have picked one). They are not
## dead: a sandbox launched without a roster must still render distinguishable
## heroes. The "no colour" test is [constant Color.WHITE], because that is
## [member Participant.color]'s default and the data model carries no separate
## unset flag; every lobby-built roster already assigns a real colour
## (`ui/frontmatter/panels/lobby_screen.gd`), so the fallback never fires on the
## menu path.
##
## Making distinct slots pick DISTINCT colours is the lobby's job (#616 D4), not
## this function's — here we only honour what we are given.
static func resolve_spawn_color(
		participant: Participant,
		player_fallback: Color,
		enemy_fallback: Array[Color],
		enemy_index: int) -> Color:
	if participant.color != Color.WHITE:
		return participant.color
	if participant.kind == Participant.Kind.AI:
		if enemy_fallback.is_empty():
			return Color.RED
		return enemy_fallback[enemy_index % enemy_fallback.size()]
	return player_fallback


## The core class this participant spawns on (#618 D3). The roster wins; the
## level's two exports are what a participant that carries no class at all —
## a hand-rolled fallback roster, a test fixture — lands on.
##
## Unlike [method resolve_spawn_color] this needs no sentinel: [CoreClass] is a
## reference type, so `null` genuinely means "unset" and there is no legal value
## that has to be reserved to say so.
static func resolve_spawn_core(
		participant: Participant,
		player_fallback: CoreClass,
		enemy_fallback: CoreClass) -> CoreClass:
	if participant.core_class != null:
		return participant.core_class
	return enemy_fallback if participant.kind == Participant.Kind.AI else player_fallback


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
