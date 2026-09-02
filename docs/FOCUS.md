# Focus

**What is next, and what is deliberately not.** One page, on purpose.

**This file carries no per-issue state.** It never says what an issue's status is,
what it depends on, or what shipped — the board answers all three, live:

```
mise gh-project -- roadmap        # open / ready / needs-design per milestone
mise gh-project -- list ready     # what a drone could pull right now
```

> **Rewritten 2026-08-31**, from 353 lines to this. The previous version referenced
> 134 issues; 89 were closed and 81 of those still read as live work — including
> every row in the "what to pull next" table. It was rewritten once before, on
> 2026-08-18, for the same reason, and regrew in twelve days. **The structural
> cause is per-issue prose: it is irresistible to append to and invisible to
> prune.** So the rule is now mechanical rather than aspirational — *a line naming
> one issue may contain its number and nothing else.* If you want to write a
> sentence about an issue, write it **on the issue**.

## North Star

The bar this project is aiming at, so a perf or scope call has something to be
judged against:

1. **A 2000-`SkillNode` map runs smoothly at 144Hz, at 1440p.** The dev sandbox is
   *not* 1440p, so local framerates are optimistic about resolution. This is the
   number that decides whether a rendering or recompute approach is acceptable —
   see `.claude/rules/rendering-performance.md`.
2. **The player can control that**: windowed / fullscreen / borderless, resolution,
   vsync, framerate cap.
3. **LAN-playable**: single-player, seeded runs, and hot-seat coop by
   **2026-09-04**, with versus if it fits. That is milestone `LAN 2026-09-04`.

## The rules

1. **WIP limit: 5 — and it is the weakest rule here.** The real failure mode is
   things *rotting* `In progress`. Judge the column by age, not by count.
2. **Any number of lanes at a time.** Ideally we close lanes out one by one, but
   work closed on any lane is always welcome.
3. **A fork is a filed issue, never an immediate start.** File it, finish the
   current unit, re-read this file. If the fork is needed *for the current unit*,
   do it ASAP — the split exists so an agent can be pointed at a whole issue
   instead of one paragraph of another.
4. **Legibility ships, fidelity defers.**
5. **Crappy-now beats correct-later for anything not on the critical path** —
   except during the LAN window, see below.
6. **`Ready` is a superset, not the queue.** `Ready` means a drone *could* take
   this; being named below means a drone *should*.
7. **There is one queue for design work — #261**, the swarmify pipeline. An issue
   in `Needs design` sits there until a `/swarmify` pass settles its forks.
   **FOCUS does not catalog `Needs design` work.**

## The LAN — milestone `LAN 2026-08-31`, hub #456

> **The LAN is 4-6 September.** Standing instruction for the window, owner call
> 2026-08-29: *"we will take all time we have to land as much as we can, make it
> future proof, but mostly, clean."* The extra week bought **cleanliness, not
> scope** — prefer the correct shape over the crappy-now shortcut rule 5 permits
> elsewhere.

**Membership in the milestone means "this gates the LAN build."** What is left in
it is a board query, not a table here. The lanes, in the order they matter:

1. **Networked lobby** — #712 (children in order: #715, #716)
2. **Spell VFX** — #663, #671, #672
3. **Aura recompute perf** — #657 first; #681
4. **Readouts & UI polish** — #621
5. **AI combat reads** — #537
6. **Owner-run, not drone work** — #665

Board reconciliation lives on #653.
