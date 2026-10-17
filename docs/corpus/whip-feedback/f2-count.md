**Observed (2 of 6 runs).** The morning report's `Landed N/M` header disagrees with the leads' tallies and the top has to reconcile it by hand:
- 2026-10-12 (83eb6242): "It reads 10/12 because it counts rows in the lead's Landed table, and some rows carry two issues." All 12 issues landed.
- 2026-10-17 (eca76d3a): "Landed 29/32 ... That count doesn't match what the leads reported, 22 of 23 for train a plus 9 of 9 for train b, so 31 of 32. I haven't checked which issues the report counts as not landed." The report lists 29 landed + 1 back to Needs design; two issues appear in no section.

**Proposed.** Derive Landed from the board/closed-issue state and the ledger's issue list (every started issue lands in exactly one of Landed / Back to Needs design / Still Ready / Dropped / Orphaned), and have `whip report` print a loud "unaccounted: #…" line when the sections do not sum to M. The skill's final step: the top does not report a count it has not seen sum.
