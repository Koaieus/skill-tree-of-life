---
id: 0071
title: The default drone is an OpenCode DeepSeek-flash drone, reviewed Claude-side (Opus, Fable for the hardest); the Claude drone is the fallback and the Opus tier for tough units
status: accepted
date: 2026-10-23
deciders: owner
supersedes: []
superseded-by: null
revisit-when: "OpenCode drones underperform on Godot units (scenes, GUT, editor churn) — then the Claude drone is the default again and OpenCode takes mechanical units only; or the OpenCode window, not the Claude one, becomes what caps a night. The per-unit Opus reviewer over a persistent Fable Sage is a tentative pick (owner: either is fine)."
sources:
  - "docs/charters/drone.md"
  - "docs/charters/swarm.md"
  - "docs/charters/sage.md"
  - "a sibling repo's opencode-drone charter and docs/domain/opencode-cli.md (owner's upload, 2026-10-23)"
  - "~/.config/opencode/agents/drone.md (opencode-go/deepseek-v4-flash, reasoningEffort max)"
tags: [meta, orchestration, swarm, drone, cost]
---

# ADR 0071 — The default drone is an OpenCode flash drone, reviewed Claude-side

## Context

Drones are the implementation workers of swarm, swarm-train, relay and warp: one fenced unit each, in a worktree, today a Claude Code `drone` agent on Sonnet (Opus for a hard unit), reviewed by a persistent Fable Sage. The drone and swarm charters said the repo had no OpenCode config and dropped the OpenCode column on purpose. A sibling repo then ran a Claude lead over `opencode run` drones on DeepSeek v4.1 flash: implementation cost cents per unit, the scarce budget is OpenCode's rolling 5-hour window rather than dollars, an in-OpenCode `v4-pro` review cost ~80% of a unit while a Claude-side review costs Claude tokens the lead already budgets, and flash "has lapses in judgment at times, or gets loopy". An OpenCode drone is a CLI process, not an `Agent` call: no `SendMessage`, no `advisor`, no context hook, and `--agent` ignores the agent's model pin.

## Decision drivers

- **Cost per landed unit**, across both budgets (Claude window, OpenCode window).
- **Judgement where it pays:** a unit's quality is set by its spec and its review, not by the typist.
- **Context is free on the drone side:** big mechanical sweeps fit a flash drone's window at no Claude cost.
- **Godot fitness:** scenes, `.tscn`/`.uid` churn and GUT are unproven on OpenCode.
- **One contract:** both drone harnesses obey one drone charter.

## Decision

**OpenCode flash drones are the default implementer; review stays on the Claude harness.** Owner, 2026-10-23: *"these drones implemented stuff at like 5~10 issues per 1% of opencodes rolling window. they're extremely cheap and we offset that with smart model reviewing using claude harness, Opus or sometimes Fable"*; *"i think opencode drones should become our go-to for drones"*.

**The Claude drone stays: as the fallback, and on Opus for the hardest units.** Owner, 2026-10-23: *"keep option to launch Opus drone for real tough cookies. they're still well performing"*; *"BIG mechanical stuff they can do, their ctx is basically free. just really clever solutions are best specced up front"*.

## Consequences

- Implementation leaves the Claude window almost entirely; a night's ceiling becomes review plus orchestration.
- The spec carries the cleverness: a unit that needs a clever solution has it decided before dispatch, or goes to an Opus Claude drone.
- Two projections of one drone contract, one per harness, must be derived together from the drone charter.
- The lead drives a CLI: worktree made up front, brief and spec copied into it, model passed explicitly on every run, cost read from the session export, the stream read by digest, never whole.
- A HELP from an OpenCode drone is answered by continuing its session, not by `SendMessage`; a Sage cannot sit inside the drone's loop.

## Alternatives considered

### Claude Sonnet drone as default (status quo) — **most likely revived**
Lost on cost per landed unit: implementation was the Claude window's largest line. Revives by the Godot clause of `revisit-when`, with OpenCode kept for mechanical units.

### OpenCode for mechanical units only
Lost on cost: it moves only the sweeps, and the owner's figures put ordinary units in reach. It is the named fallback, not dead.

### OpenCode only, the Claude drone retired
Lost on resilience: a spent OpenCode window or an outage stops all building, and the hardest units lose their Opus tier.

### Review inside OpenCode (`v4-pro`)
Lost on the OpenCode window: one review cost about four times the drone. Dead while the window is the scarce budget.
