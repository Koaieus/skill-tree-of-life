# Lobby, roster and run bootstrap

The pre-run session surface: palette, roster, policy, bootstrap.

## Player palette (`session/player_palette.gd`)

The colours a lobby slot may pick a hero from (#616). Authored once as
`session/player_palette.tres`; the lobby assigns defaults round-robin and
the per-slot picker overrides.

**Distinct from the stat palette.** `.claude/rules/ui-palette.md` makes
`StatDef.tint_color` the source of truth for attribute/vital colours
and forbids a second resource restating them — this is not that. A hero's
identity colour answers "whose is this", not "which stat is this", so it is
its own axis and its own resource. Nothing here is read back into a stat
colour, and nothing reads values out of `ui/theme/editor_swatches.tres`.

**Two colours are deliberately absent, and both absences are load-bearing:**

**1. Gold.** Reserved for pure positives (same rule file) — reward, never
identity. The generator below therefore skips the hue band `[62, 112)`
outright rather than trusting an author to eyeball it.

**2. Pure white.** `Participant.color` defaults to
`Color.WHITE` and there is no separate "unset" flag, so
`ProcgenPlaySandbox.resolve_spawn_color` reads pure white as the
sentinel for "this participant carries no colour" and falls through to the
level's `player_color` / `enemy_colors` exports. A slot that could
pick pure white would therefore silently spawn in the level default instead
of what the player chose. `test_lobby_roster.gd` pins the absence.

**Owner call, 2026-09-02, superseding #639's stride:** sixteen colours in
two authored tiers — eight canonical brights (index 0-7: Red, Blue, and six
more spread around the non-gold hue arc), then eight muted "second choice"
colours (index 8-15) sitting in the hue gaps between the brights, for a
roster that somehow outgrows tier one. `default_for` just walks the
array (`colors[index % size]`) — the ordering itself is arranged so that
consecutive slots land on well-separated hues; #639's runtime
`index * stride` trick is retired rather than reapplied to a hand-curated
list. `test_lobby_roster.gd` still pins pairwise OKLab separation (dE ≥
0.14, same bar #639 used) for a 3- and a 6-slot roster.

Values were derived OKLCH → sRGB with the house conversion (Björn Ottosson's
OKLab formulas, same script as the stat palette table), gamut-checked per
hue rather than clamped, with lightness cycled across three values (0.62 /
0.74 / 0.86) so hue alone never has to carry the whole separation. Don't
eyeball a new one — re-derive it.


Names, index-for-index with the shipped array (not a second data source —
just what to call an index when talking about one):
```
0 Red         4 Orange       8 Rust       12 Cobalt
1 Blue        5 Chartreuse   9 Moss       13 Lavender
2 Violet      6 Olive       10 Teal       14 Plum
3 Magenta     7 Cyan        11 Steel      15 Rose
```

## LobbyRoster (`session/lobby_roster.gd`)

The lobby's DOMAIN half (#1002): who is in the run, what each seat picked,
and whether START is allowed. `LobbyScreen` holds one, renders rows from it,
forwards every edit here and calls `to_run_config` at START — the
screen is a view, this is the run's shape before it becomes a `RunConfig`.

**Three shapes, decided by the `NetworkConfig` rather than by a mode the
player picked** (#554):

```
  offline, SINGLE      1 human at peer 0 on `player.tres`    -> SINGLE
  offline, hot-seat    2 humans at peer 0 sharing `camp_1`    -> COOP_HOTSEAT
  host / join          1 human on camp_1 at THIS peer +
                       1 human on camp_2 at the other one     -> VERSUS
```

**Which of those humans is "me" is never written down (#562)** — the two
seats differ only by `Participant.peer_id`, and each machine derives
its own answer with `Participant.is_local`.

**Why the remote seat is declared before anybody joins.** The mode is
derived at START from the roster and procgen reads the camp shape at level
setup — both before a peer's socket is anywhere near this machine. So a
networked roster seats the second human immediately, at
`PENDING_PEER_ID`, and the join stamps that placeholder with the
real id (`clear_remote`). "The roster grows on join" is true of the
peer id, not of the seat.

**Pick memory.** Changing the AI count rebuilds the participant list from
scratch (`build_participants` is pure), so what a player explicitly
chose lives beside the list as one `LobbyRoster.Pick` per seat id and is
re-applied after every rebuild — a slot's colour must not silently revert to
its palette default because a DIFFERENT slot was added. A field's zero value
is "still on the default": white for colour (the palette never offers it),
null for core, camp and tier, "" for the name.

**Colour is run shape, for every slot (#616).** It crosses the wire in
`Participant.to_dict`, so the AI slots are this roster's problem
too: defaults come round-robin off the palette across the WHOLE roster.

**The run section is NOT here.** Map size, blockers, arrangement, victory
and budget are ladders the route's `LobbyPolicy` unlocks and the screen
composes into [ScenarioOverride]s — `to_run_config` takes the settled
scenario + overrides as arguments rather than owning the ladders, so this
file never has to know what an `OptionChoiceRow` is.

Emits `changed` after every mutation that altered a seat or the
START gate; the screen's one handler repaints from it.

## RunBootstrap (`session/run_bootstrap.gd`)

Starts a run from an authored `RunConfig` when no composer did — the
editor-launch half of #584.

**This is a child node, deliberately, and it is the whole mechanism.** A
level scene that can be launched directly needs a run to consume, and there
are three ways to give it one: a fallback branch inside the level (what this
replaces), a virtual hook the sandbox subclass overrides (what `9b0e185`
did), or a sibling that fills `GameSession` in before the level looks. Only
the third leaves the level with **one** way to learn what run it is
generating, and that property is the point:

```
lobby  → GameSession.start(composed RunConfig)  ┐
                                                ├→ level reads GameSession
RunBootstrap → GameSession.start(authored .tres)┘
```

A sandbox that parsed its settings differently from a lobby-launched run
would stop being a rehearsal of the real game — the owner's call, 2026-08-26:
*"if our first level sandbox deviates from the 'lobby launched level' in a
meaningful way (or in how it parses its settings) it becomes less of a real
representative of the real game"*. Here the two paths differ only in
**who authored the RunConfig**, never in what the level does with it.

The level never references this class. That is what makes it a rehearsal
rather than an accommodation: `scenes/level.tscn` has no idea a bootstrap
exists, so there is no sandbox-shaped seam in the shipped code for the two
paths to drift apart along.

**Ordering.** A child's `_ready` runs before its parent's, and
`GameRoot._ready` is where the level reaches `_setup_level` — the only
thing in a level's bring-up that reads `GameSession.roster`. So the
bootstrap wins that race wherever it sits, with no explicit call from
`GameRoot` to keep in sync.

It is nonetheless authored as the **first** child (`index="0"`). Godot
readies depth-first in tree order, so last-child would leave the guarantee
resting on an audit — "nothing under `Graph` or `HudRoot` reads
`GameSession.config` in its own `_ready`" — that is true today and
that a future sibling could quietly break, with the symptom being a null
config rather than an error. First-child makes it true by layout instead:
nothing in the level can observe a session this node has not opened yet.

## ScenarioOverride (`session/scenario_override.gd`)

A leaf-addressed, by-value patch onto a duplicated `Scenario` (#642 D14 —
"Decision — the override encoder", rooted one level up onto `Scenario`
itself by #742). Not a module resource and not a stringly-typed
`Dictionary`: a typed, inspector-authorable Resource carrying exactly one
(path, value) pair.

**Rooted at `Scenario`, not at `Scenario.preset`** (#742). A
`Scenario` is itself just another Resource with ExtResource-typed fields —
`preset` is one of them, `victory_condition` another — so there is no need
for a second override list to reach the latter: a preset-targeting override
just gains a `preset:` prefix (`"content:budget_policy:base_min"` ->
`"preset:content:budget_policy:base_min"`), while `"victory_condition"`
needs none. Same walk, same `_resolve_leaf_type` -> class-check ->
`set_indexed` machinery, no routing branch to distrust.

`target` is a property path into the DUPLICATED `Scenario`, in
Godot's subname form: `"preset:content:budget_policy:base_min"`. Colons,
not slashes. `value` is a primitive/scalar for a scalar leaf, or a
resource PATH (a String) for a Resource-typed leaf (#742 — see
`_coerce_resource`) — never an embedded object, which is what makes
an in-memory "Custom" override survive `RunConfig.to_dict` with no
`resource_path` involved anywhere (#642 acceptance 3, #597 D4's named
failure mode made unreachable by construction).

**D15 hardening** (comment "Hardening D14", 2026-08-27): `set_indexed`
fails SILENTLY three ways — a typed-array target with an untyped payload,
a wrong-type scalar, and a lossy float-into-int truncation. `merge_onto`
closes all three by construction: a `target` must resolve to a
SCALAR leaf (int/float/bool/String/StringName) or a Resource-typed leaf
(arrays and dictionaries are still rejected outright), and the incoming
`value` is type-checked against that leaf's OWN declared type (read
via `get_property_list()`, never assumed) before anything is written. A
rejection always `push_warning`s naming the target and leaves the scenario
byte-for-byte unchanged — never a silent no-op.
