## CurlOperator: Cyclone as a linear operator (`tools/curl_spectrum/curl_operator.gd`)

Cyclone's propagation as a **linear operator on directed edges** (#705).

Keep the walk's state on the edge it arrived along rather than on the node it
stands at, and `CycloneSpread` becomes a fixed non-negative matrix: a front in
state `(u → v)` mints one child per turn-rank `r`, in state `(v → w_r)`,
carrying `rank_coefficients[r]` of its damage. Damage is conserved-then-
scaled and `CycloneReducer` SUMS on convergence, so total damage per wave is
exactly `‖M^k x‖₁` — and growth per wave is `M`'s spectral radius, by power
iteration, with no cast and no world.

**What the linear model leaves out, and which way it errs.** Three of the
shipped spell's rules are history-dependent and so cannot be a matrix entry:
```
closing_gain      — needs the front's trail to know a hop closes a ring
momentum merge    — the merged heading re-aims the NEXT ranking
the merge itself  — N incidents become ONE front, which then fans ONCE
```
The third is the one that bites, and it is not a rounding error: where the
operator keeps two converging fronts as two directed-edge states that each
fan in full, the resolver collapses them into a single payload that fans
once, so convergence *loses* arms even while it sums damage.

So ρ is **not** a bound in either direction, and #705 measured which way
it misses rather than assuming: against real `SpellResolver` casts on the
same terrain, the walk tracks the operator exactly for two waves, then runs
BELOW it on sparse ground (merge-collapse dominates) and ABOVE it on dense
ground once `closing_gain` starts firing — roughly ±30% by wave 8 at the
shipped 0.25 connectivity. Table E of `snapshot.md` is that comparison, and
it is why the sweep ships a cast probe instead of a footnote.

What ρ *is* exact for is the question the floor rests on: a tree, where
nothing ever closes and nothing ever merges, reads 0.000 and the two models
agree term by term.

The ranking itself is NOT re-derived here: `Curl.rank_indices` is the
same call the shipped step makes.
