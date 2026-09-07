---
id: 0003
title: The entry point is a config setting, not an autoload redirect
status: accepted
date: 2026-09-01
deciders: owner+agent
supersedes: []
superseded-by: null
sources:
  - "43b0e53"
  - "#577"
  - "CLAUDE.md"
tags: [boot, scenes, exporting]
---

# ADR 0003 — The entry point is a config setting, not an autoload redirect

> **Backfilled 2026-09-07** from commit `43b0e53` and the note it left in
> `CLAUDE.md`. The decision date is the date of the commit. Small, but a textbook
> case for the tier: the setting looks arbitrary, is trivially "improved" back to
> the broken shape, and the reason is invisible from the code.

## Context

The project needed two different starting points: an **exported build** must open
the frontmatter menu (`scenes/meta/meta_root.tscn`), while day-to-day development
wants to land straight in a sandbox level.

The arrangement that grew to serve both was: point `run/main_scene` at
`scenes/dev_sandbox.tscn` for developer convenience, and add a `Boot` autoload
that redirects to `meta_root` from `_ready` so that shipped builds still opened
the menu.

It did not work, and the failure was structural rather than a bug:

- **No autoload can win that race.** The engine instantiates the main scene
  *before* any autoload can intervene. The redirect therefore always ran second,
  and `SceneDirector.goto` then spent a fade plus a threaded load on top of it.
  An exported build visibly flashed `dev_sandbox` and cut away a moment later.
- **The waste was worse than the flash.** `dev_sandbox` extends `game_root`, so
  every single export built an entire level — graph, entities, HUD compose —
  purely to throw it away.

## Decision

**`run/main_scene` is `scenes/meta/meta_root.tscn`, and the `Boot` autoload is
deleted.**

The entry point is a property of the build, so it belongs in the build's
configuration. Nothing redirects at startup, because there is nothing to redirect
away from.

Sandboxes are launched **by path** instead:

```
godot --path . scenes/dev_sandbox.tscn
godot --path . scenes/first_level_sandbox.tscn
godot --path . scenes/procgen_play_sandbox.tscn
```

The consequence for developers is explicit and accepted: **editor F5 opens the
menu**, not a sandbox.

## Consequences

- An exported build starts in the menu, with no flash, no wasted level build, and
  no fade-plus-threaded-load on the critical boot path.
- **Launching a sandbox costs a longer command line.** This is the whole price,
  it is paid by developers only, and the three commands are documented in
  `CLAUDE.md` under *Running the Game*.
- `#577`'s acceptance re-points onto the setting rather than onto the autoload;
  the two structural *"there is a menu to boot into"* tests survived unchanged,
  and `test/unit/ui/test_entry_point.gd` replaced `test_boot_routing.gd`.
- **`run/main_scene` now looks like it could be changed freely, and cannot.**
  Pointing it back at a sandbox reintroduces the exact defect. That trap is why
  `CLAUDE.md` says *"It is a config setting on purpose"* — and why this record
  exists.

## Alternatives considered

### Keep the `Boot` autoload redirect, and make it faster

Skip the fade, load synchronously, redirect earlier.

**Why it lost:** there is no "earlier" available. The engine builds the main scene
before autoloads run, so the sandbox is *already constructed* by the time any
redirect could fire — including its graph, its entities and its HUD compose. The
cost being removed is the construction, and no amount of optimisation inside the
redirect touches it. The race is not tight; it is unwinnable.

### A lightweight `boot.tscn` as the main scene, which then routes

Make the main scene an empty scene whose only job is to decide where to go.

**Why it lost:** it is the autoload redirect with extra steps — one more scene to
maintain, one more hop before the menu, and still a redirect where a setting
would do. It also keeps the "where does this build actually start" answer in code
rather than in the config, which is the thing that made the original arrangement
hard to reason about.

### Different `run/main_scene` per export preset, or a debug-build conditional

Ship the menu, develop into a sandbox, branch on `OS.has_feature("editor")`.

**Why it lost:** it makes the editor and the shipped build take structurally
different boot paths, so the path that ships is the one least exercised — the
same argument that puts single-player and hot-seat on the networked code path in
[ADR 0002](0002-host-authoritative-sync-not-lockstep.md). Typing a scene path is a
smaller cost than a boot sequence that only runs for players.
