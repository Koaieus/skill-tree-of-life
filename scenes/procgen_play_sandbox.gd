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

## The FALLBACK preset (#641 D6). A run carrying a [Scenario]
## ([member GameSession.config].scenario) wins — this export is what a run
## opened with none lands on. Precedent already shipped in this same file:
## [method resolve_spawn_color] (#563 D1) and [method resolve_spawn_core]
## (#618 D3) both read "the run wins; the scene export is what a run carrying
## none lands on". The arm stays live rather than dead code because a sandbox
## launched without a lobby (`RunBootstrap` holding an authored `RunConfig`
## with no `scenario`) must still generate a map.
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

## Shared allocation-pick strategy (#275, D-24) — greedy BFS ball by default.
## Injectable so a different level scene can swap in another AllocationPolicy
## without touching this script.
@export var territory_seeder: TerritorySeeder = _DEFAULT_TERRITORY_SEEDER

## Target owned-node count for each spawned enemy (core included). D-19:
## enemy level == starting nodes, so this also becomes each enemy's spawn
## level once seeding completes. The player is NEVER expanded — D-16 pins
## player starting nodes at 1 (the core only).
@export var enemy_territory_size: int = 20


## Two shapes, and only one of them generates (#715).
##
## [b]A joining CLIENT runs no procgen at all.[/b] It used to generate from the
## host's seed and then pull the authority's world on top, which cost it 5-10
## seconds to build a map it was about to throw away and left a window where the
## link was up and a WRONG world was present. It now builds an empty graph,
## spawns the roster's entities as placeholders so `entity_id` minting lands on
## the host's numbers, and lets [method GameRoot.pull_host_world] fill in the
## world. Everything the host derives from the seed — nodes, edges, archetypes,
## keystones — arrives serialized instead of being re-derived, so no
## transcendental in the seeded draw (#547, #689, #706) can desync anything.
##
## The `is_active` / roster guards below are shared, and deliberately: a client
## with no run open is exactly as broken as a host with none.
func _setup_level() -> void:
	# #457: one resolved seed for the whole run. A run started from the lobby
	# already has one; a level launched directly (dev sandbox, headless test)
	# opens a session here seeded from the preset's authored value — so either
	# way `cfg.seed` below is concrete and recorded, never a live sentinel.
	if not GameSession.is_active():
		push_error("%s: no run is open. A level GENERATES a run, it does not "
				% name + "invent one — start the session first, from the lobby "
				+ "or from a RunBootstrap child holding an authored RunConfig.")
		return
	# #715: and here the two shapes part company. Above this line everything is
	# shared; below it is generation, which a joining client does not do.
	if _is_network_client():
		await _setup_level_as_client()
		return
	# #641 D6: the run's Scenario names the preset; `preset` (the scene export
	# above) is the fallback for a run that opened with none.
	#
	# #643: through `resolved_preset()` rather than `scenario.preset` directly,
	# which is what makes #642's whole merge path reachable — before this, that
	# path had ZERO production callers and every lobby override was silently
	# dropped. This is a STRICT SUPERSET of the previous behaviour, not a
	# behaviour change: `resolved_preset()` returns `scenario.preset` merged onto
	# a duplicate, and merging an EMPTY override list is a plain duplicate. A run
	# carrying no overrides therefore generates exactly the map it always did.
	var source_preset: GraphProcgenConfig = GameSession.config.resolved_preset()
	if source_preset == null:
		source_preset = preset
	if source_preset == null:
		push_warning("%s: no preset available — the run's Scenario carries none "
				% name + "and `preset` is unassigned in the inspector")
		return
	var cfg: GraphProcgenConfig = source_preset.duplicate(true)
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
	# The roster decides how many starting points to produce (#551, #742) —
	# `cfg.camp_sizes` above is the ONLY input either generation path reads for
	# that count. With a `starter_placement` set (every shipped preset, since
	# #742 lifted `first_level.tres`'s legacy manual-anchor-plus-random-fill
	# path into a real [CenterCoreStarters]), `plan()` derives the headcount
	# from `camp_sizes` directly. Without one, the starter list is exactly the
	# preset's authored `starting_points` — no random fill, no second knob
	# reading like an opponent count independent of who is playing (#584).

	# Show the loading bar over a black fade so the procgen wall-clock has a
	# visible heartbeat. SceneTransition is the global fade/progress autoload.
	# `set_faded(true)` snaps to opaque-black; on the lobby path the curtain is
	# ALREADY up (SceneDirector faded out before the load and holds it) and this
	# is a no-op, and on a direct `godot --path . scenes/first_level_sandbox.tscn`
	# launch it is what raises it — no fade animation either way, there is no
	# prior content to fade away from.
	#
	# It is not lowered here: [method GameRoot._ready] fades in at its very end,
	# once the HUD is composed and the camera is on the player, which is the
	# same moment on both paths.
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

	# Spawn onto the returned nodes in participant order — camp 0 member 0,
	# camp 0 member 1, camp 1 member 0, ... (#551's `starter_placement`
	# contract, held even when no `starter_placement` ran: `cfg.camp_sizes`
	# is inert there). Trim to whichever list came back shorter: a preset with
	# no `starter_placement` sizes `starting_nodes` off its own authored
	# `starting_points` list, independent of `camp_sizes`, so the two can
	# disagree outside a `starter_placement` preset.
	var spawn_count: int = mini(grouped_participants.size(), starting_nodes.size())
	if spawn_count < grouped_participants.size():
		push_warning("ProcgenPlaySandbox: %d starting nodes for %d camp-planned participants — trimming"
				% [starting_nodes.size(), grouped_participants.size()])

	var enemies: Array[Entity] = []
	var seated := _seat_the_roster(
			roster, grouped_participants, starting_nodes, spawn_count, enemies)

	# Removable blockers (#477): one blocker entity per procgen placement. Still
	# before territory seeding, so enemy seeding skips already-blocked nodes
	# (AllocationSystem treats them as owned by the blocker entity).
	#
	# [b]AFTER the roster's spawns, not before (#715).[/b] [Graph] mints
	# `entity_id` by add-order, and a joining client seats the roster and spawns
	# no blockers at all — so with blockers first, every participant's id on the
	# host sat above ~120 ids the client does not have, and [EntitySnapshot]
	# (which decorates by `entity_id`) would decorate the wrong entities.
	# Participants first makes their ids `1..N` on every peer by construction.
	# Nothing else about this loop cares where it sits: blocker placement excludes
	# every starter core, so it cannot collide with a core just force-allocated.
	for placement in result.get("blockers", []):
		spawn_blocker(placement.get("size"), placement.get("node"),
				placement.get("prune_seed", 0), cfg.blockers.blocker_spell_prune_m)

	if not seated:
		return

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


## The joining CLIENT's whole `_setup_level` (#715): no preset, no
## [GraphProcgen], no territory seeding — an empty graph and the roster's
## entities, standing by for [method GameRoot.pull_host_world] to fill the world
## in around them.
##
## [b]It still SPAWNS, and that is the one thing it may not skip.[/b]
## [EntitySnapshot] decorates by `entity_id` and never spawns (#560 D7), so the
## entities have to be here before the host's state arrives or every row is
## skipped with a warning. They are spawned in [method _camp_grouped_participants]
## order — the identical order the generating branch uses — because [Graph] mints
## `entity_id` by add-order (`graph/graph.gd::_mint_entity_id`), and one
## mis-ordered spawn slides every id past it. `core_location` is null: there are
## no nodes yet to allocate onto, and the snapshot's pass 2 resolves it.
##
## [b]The loading bar covers the HOST's generate + ship, not this machine's
## procgen.[/b] Same curtain, same progress widget, different wall-clock being
## explained — this peer is waiting on somebody else's 5-10 seconds now. It is
## indeterminate on purpose: the host reports no progress, and inventing a fake
## ramp would be worse than a bar that simply says "working".
func _setup_level_as_client() -> void:
	if false: await get_tree().process_frame # keep this a coroutine, as the caller awaits it
	var roster: ParticipantRoster = GameSession.roster
	if roster == null or roster.all().is_empty():
		push_error("%s: the host's run carries no participants — nothing to seat." % name)
		return
	SceneTransition.set_faded(true)
	SceneTransition.progress_bar.show()
	SceneTransition.set_progress(0.0)
	var grouped := _camp_grouped_participants(roster)
	var enemies: Array[Entity] = []
	_seat_the_roster(roster, grouped, [], grouped.size(), enemies)


## Spawn one [Entity] per camp-grouped participant, apply the roster to them and
## derive this machine's [SeatPolicy]. Shared by both branches of
## [method _setup_level] (#715) precisely because it must not drift: the ORDER
## and the COUNT of these spawns are what make `entity_id` mean the same thing on
## every peer, and two copies of this loop would be two chances to disagree.
##
## [param starting_nodes] is empty on the client, which is what makes every core
## `null` there. [param enemies] is filled in for the caller — only the
## generating branch seeds territory, so only it uses them. Returns false when
## this machine seated nobody, which is the caller's cue to stop.
##
## Humans: core only. D-16 pins starting nodes at 1 — no seeding call here.
##
## #554: the AI/human split is by KIND, which every peer reads identically off
## the same roster, and only `player` — the per-machine half — is decided by
## peer id. Keying the spawn shape off "is this mine" instead would seed each
## peer's rival with `enemy_territory_size` nodes and its own hero with one,
## so two peers would build different worlds from the same roster.
func _seat_the_roster(
	roster: ParticipantRoster,
	grouped_participants: Array[Participant],
	starting_nodes: Array,
	spawn_count: int,
	enemies: Array[Entity],
) -> bool:
	var entities_by_participant_id: Dictionary = {}
	for i in spawn_count:
		var participant: Participant = grouped_participants[i]
		var ent: Entity
		var where: SkillNode = starting_nodes[i] if i < starting_nodes.size() else null
		# #563 D1: the ROSTER decides the colour, for every entity alike. The
		# `player_color` / `enemy_colors` exports are reached only through
		# `resolve_spawn_color`'s fallback arm, and only for a participant that
		# carries no colour at all.
		var color := resolve_spawn_color(
				participant, player_color, enemy_colors, enemies.size())
		# #618 D3: and the roster decides the CLASS the same way. The
		# `core_class` / `enemy_core_class` exports are the fallback for a
		# participant that carries none, not the answer.
		var core := resolve_spawn_core(participant, core_class, enemy_core_class)
		if participant.kind == Participant.Kind.AI:
			ent = spawn_entity("Enemy_%d" % participant.id, color, where, core)
			enemies.append(ent)
		elif _is_this_machines(participant):
			ent = spawn_entity("Player", color, where, core)
			player = ent
		else:
			ent = spawn_entity("Player_%d" % participant.id, color, where, core)
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
		return false

	# Wire the player into the interaction layer (input / vision / highlight)
	# now that it exists — edit-time NodePaths can't bind to a node spawned at
	# runtime. `_ready` calls `bind_player` again idempotently; doing it here
	# too sets vision before territory seeding + the fade so the initial fog
	# is correct.
	bind_player(player)
	return true


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
