**Incident, 2026-11-19/20 (cloud session, `/swarmify docs/handoffs/owner-forks-2026-11-18.md — run the ADR gate on the 2026-11-19 Catalyst calls, then take group 2`).** The pass reached ~200k context before the owner's first question. Where it went, all in the main thread: reading eight open issue bodies in full via REST, the ADR skill and `docs/domain/adr.md`, two full ADRs (0094, 0095), drafting and committing ADR 0096 by hand, and the gate comments. Only the ADR-librarian check and one Haiku Explore were delegated, and the main thread waited on them instead of asking.

Owner, 2026-11-20, verbatim: *"the ADR stuff consumed like 150k tokens without us getting into anything useful yet (i mean you did ask the questions but thats at 217k ctx; some very suboptimal decisions were made this session of not offloading research or mechanical work (=writing ADRs) to subagents even before i got my first response in"*

What the charter should say:
- A pass's FIRST turn fans out in parallel: the Explore for code facts; one subagent for any ADR gate *and* ADR drafting (the `adr` skill's "write it yourself, you sat with the owner" law should yield to a subagent briefed with the owner's verbatim quotes, the session reviewing the draft); one subagent for issue/comment reads returning owner sentences verbatim.
- A handoff/working file named in the prompt is the only document the main thread reads in full.
- A context target for the first owner question (~80k), not only the 200k ceiling in step 0.
- The 7b close's step (c) "invoke `adr`" for a multi-call gate is mechanical work: delegate it.
