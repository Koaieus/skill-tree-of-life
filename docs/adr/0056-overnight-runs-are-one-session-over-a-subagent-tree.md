---
id: 0056
title: An overnight run is one session over a subagent tree (swarm-train); the relay of `--bg` sessions with a watchdog (Whip v2) is retired
status: accepted
date: 2026-10-12
deciders: owner
supersedes: []
superseded-by: null
revisit-when: "the harness delivers a background child's completion to its own background parent, or the law-4 drone-to-lead wake fails in a run"
sources:
  - "#1316"
  - "#1313"
  - "#1518"
  - "#1519"
  - "#1578"
  - "docs/charters/swarm-train.md"
  - "docs/handoffs/whip-report-2026-10-02.md"
  - "docs/handoffs/whip-report-2026-10-03.md"
  - "docs/handoffs/whip-report-2026-10-10.md"
  - "docs/handoffs/whip-report-2026-10-11.md"
tags: [meta, orchestration, overnight, swarm]
---

# ADR 0056 — Overnight runs are one session over a subagent tree

## Context

An overnight run lands a queue of Ready issues unattended, inside a runtime cap the owner set on 2026-10-02: *"a cap backstop — say 15 hours max runtime"*. The first transport (Whip) was a relay of real `--bg` sessions — one per swarm lead — kept alive by a watchdog. After its trial nights the owner redirected on 2026-10-09: *"considering switching it to a subagent tree (or a new skill that does that) instead of creating actual sessions and needing a watchdog"*, and chose to try it alongside rather than swap: *"i think a 2nd skill as tryout might be best, can then decide which to keep or both"*. Spike #1518 found the tree viable — nesting holds three deep; a spent window kills in-flight subagents but leaves finished ones intact and resumable; only a final report (under 1 KB) enters the parent; the top sees every descendant and can stop a stalled one — with one shape constraint: a background subagent never receives its own background children's reports.

## Decision drivers

- **Lands without blowing up:** a night ends with the queue landed or returned for design reasons, never wedged on its own machinery.
- **Machinery to own:** every daemon, identity and message path is one more thing that fails overnight.
- **One contract:** the overnight contract (disk ledger, `mise run land` as the gate, relief oriented from disk) has one implementation.
- **Visible from the top:** a stall is detectable and stoppable without a second process.

## Decision

**An overnight run is one session whose train leads are subagents spawning their own drones (swarm-train). The `--bg` relay with a watchdog is retired.** Owner, 2026-10-12: *"tree wins, retire whip."*

## Consequences

- Gone with the relay: the daemon unit, the watchdog process, `--bg` identity and resume-by-flag, cross-session messages. The ledger, the land gate and relief from disk carry over unchanged.
- The top session costs kilobytes per train, and the top's periodic tick is the stall net and the window-reset wake.
- **The known cost is the drone wake.** Owner, 2026-10-12: *"the main critical flaw: backgrounded Drones, when completing, don't automatically wake their lead (`/swarm` supervisor) but instead reach the swarm-train lead (superdupervisor)"*. Mitigation is swarm-train law 4: a drone's final act is `SendMessage` to its lead, which resumed a background lead once (n=1, spike 2026-10-12). The drone's ordinary completion report still lands at the top, so a second wake for a handled unit is a no-op there.
- A spent token window kills every in-flight agent at once; the cap and the drone count per lead are budgeted against it.

## Alternatives considered

### (a) The `--bg` relay with a watchdog (Whip v2)
**Rejected on lands-without-blowing-up and machinery-to-own.** Relay nights 2026-10-02 (landed 7/12) and 2026-10-03 (landed 4/20, 16 dropped) — `docs/handoffs/whip-report-2026-10-0{2,3}.md`; their ledgers carry no `transport` key, and absent means the relay. Their failures (runs #1337, #1363; #1313's 2026-10-09 comment) were the watchdog wedging `{blocked, waiting}` on a cross-session message, `stop` failing, a flagless resume forking a copy, and the `--bg` identity and relief paths — all transport. Tree nights (`"transport": "tree"`): run #1540 landed 11/11 with 0 failures, run #1565 landed 14/16 with 0 failures, its two returns to Needs design (#1393, #1561) design blockers (`whip-report-2026-10-1{0,1}.md`). #1314, the supervised comparison run for the relay, never ran: the call rests on two nights of each transport plus the owner's verdict. *The alternative most likely to be revived* — if the tree hits a harness limit the relay never had; the failures above are the grounds to answer first. Dead ground: "a lead idling on dead drones" and the gh-shim task bomb were never transport — they occur either way.

### (b) Keep both transports
**Rejected on one-contract.** Two implementations of one overnight contract means every ledger, relief and land-gate change is made twice and drifts once; the tryout existed to pick one.
