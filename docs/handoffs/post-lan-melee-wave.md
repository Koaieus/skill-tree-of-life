# Post-LAN melee wave — what remains

Rewritten 2026-09-08 22:45 after #799, #780 and #801 landed; amended 2026-09-09 13:15
after #781 and #803 landed and the release check filed #806. **Spent when #782 and #806
have landed.** Delete it then.

master = `3df07cb`, pushed. Suite there: `0 failing · 3958 passing · 14 pending ·
426 scripts` (212s) — 13 pending are native-parity in a binary-less worktree, 1 is the
#771 pin. In the MAIN checkout a binary exists, so those 13 run and pass.

## Landed tonight

| issue | sha | note |
|---|---|---|
| #799 | `c021be6` | `thinned_nodes` → `popped_nodes`, pops only. Closed. |
| #780 | `d86b967` | Fortification drag on the swing's CLOCK. Closed. |
| #801 | `3df07cb` | Severance is a constraint removal. `BladeFreeFlight` deleted. Closed. |
| #802 | `cfcb039` | Halo perf (not this wave; landed by a parallel session). |
| #803 | `1058c34` | Native continuation — the re-baked tail on the C++ solver. Closed. |
| #781 | `8784a22`+ | Bunker break. Closed. |

## What remains

```
#782 (melee preview, Ready — #781 has landed, so it is unblocked)
#806 (Windows export broken by #798, Ready/P0 — release blocker)
```

**The briefs are posted on the issues themselves**, not here — #782 carries a lead comment
dated 2026-09-08 with the full front-loading. Read that, not this file.

- **#782** — Ready and now unblocked: #781 landed, and it wanted #781 *merged*, not merely
  in flight, because it predicts bunker shatters among other things.
- **#806** — Ready, **P0**. #798's `.gdextension` declares a `windows.release.x86_64`
  library that has never existed, and Godot's exporter hard-fails on a declared-but-missing
  library, so `mise run build` cannot produce a Windows artifact. Found by the 2026-09-09
  release check, one day after #798 landed — no gate covers exporting, so `check`, the
  suite and `mp:e2e` are all green with the Windows export broken. Needs
  `sudo pacman -S mingw-w64-gcc` (not installed) before the `.dll` can be cross-compiled.
  The issue also carries the fix for the missing pre-export guard and the fact that a
  GDExtension `.so` ships *beside* the binary rather than inside the pck.
- **#796** — Ready but **re-scope before pulling**. #797 decomposed its premise: an AI turn
  is ~4979 ms wall but **32.8 ms of compute**, 654 of 707 frames parked on the presentation
  clock. Whether an NPC pays full swing playback is a *pacing* decision, not a perf bug,
  and time-slicing is off the table (the playtest laptop has no idle budget). Read #797's
  comments first.

## The one cross-cutting fact worth carrying

**The swing clock is sim state** — `_f`, banked `drag`, `touched`. Anything that re-runs or
rewinds a span of a swing must carry or rewind the clock with it; a fresh clock mid-swing
silently un-shelters a Fortification wall. `BladeSwingClock.Bank` + `capture`/`restore`
exist for exactly this. Lives in `docs/domain/melee-blade-sim.md` and the class docstring —
deliberately not a rule file.

## Process notes from a four-session evening

- **`git push origin master` publishes everything anyone landed on local master.** It
  happened three times tonight in three directions. Push an explicit sha —
  `git push origin <sha>:master` — which refuses instead of sweeping along whatever landed
  while you were asking for approval.
- **Never cite an `origin/master` you did not fetch for in the same command.** That ref
  moved four times in an hour; a correction I sent was stale within 90 seconds.
- **A new `class_name` makes the main checkout report a wall of failures until
  `mise run refresh`.** #780's `BladeSwingClock` produced `76 failing · 39 scripts ·
  0 pending` — files failing to *load*. The **script count** is the tell, per
  `.claude/rules/testing.md`.
- **A missing `.gd.uid` is NOT why a test file vanishes** — disproven 2026-09-08. The check
  that replaces the theory: GUT's script count must EQUAL
  `git ls-files 'test/unit/**/test_*.gd' 'test/unit/test_*.gd' | sort -u | wc -l`.
