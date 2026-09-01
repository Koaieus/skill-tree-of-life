---
description: The scene-change curtain contract — who raises it, who lowers it, when a scene is presentable
paths:
  - "autoload/scene_director.gd"
  - "autoload/scene_transition.gd"
  - "scenes/game_root.gd"
  - "scenes/procgen_play_sandbox.gd"
---

# The curtain contract (#988ed06 — EXPERIMENTAL, not yet adopted everywhere)

**Experimental.** Only [SceneDirector] and [GameRoot] speak it today; the owner
has yet to adopt it across every scene. Follow it in new code, but do not assume
an arbitrary scene already obeys it.

**The curtain stays up between `fade_out()` and `fade_in()`.** `fade_out` does
not `hide()` itself — whoever raised the curtain owes the lowering. Every
bail-out after a `fade_out` must fade back in or the player is left on black.

**A scene that knows when it is presentable says so with `is_reveal_ready()`,
and lowers its own curtain.** `SceneDirector.goto` probes for that method: if
present it waits (bounded by `REVEAL_TIMEOUT_S`) and reveals nothing itself; if
absent it fades in one frame after the swap. `GameRoot` sets the flag at the
very tail of `_ready` — world generated, HUD composed, camera snapped — because
`_ready` is a coroutine and one frame after `change_scene_to_packed` shows the
HUD over an empty world.

**The progress bar is hidden until something reports progress.** A bar sitting
at 0% through a fade reads as a bug; only a phase whose wall-clock the player
actually waits on (procgen) should show it, in the bar's own 0..100 units.

`SceneTransition.is_curtain_up()` is the guard that keeps a directly-launched
sandbox (nobody faded out) from gaining a black fade nobody asked for.
Pinned by `test/unit/ui/test_scene_reveal.gd`.
