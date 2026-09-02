# Architecture review brief — window 2026-08-18 .. 2026-09-02

You are one of six READ-ONLY reviewers. Repo: /home/bramh/skill-tree-of-life (Godot 4.7,
GDScript). Read CLAUDE.md first. ~660 commits and ~150 closed issues landed in this window;
you own ONE subsystem (given in your prompt). Your job is to find **architectural drift**,
not line-level nits. Do not edit any file. Do not run `mise run test` (the full suite);
`mise run check` and `test:one` are fine. Never call an `advisor` tool or spawn Opus agents;
use `Explore` agents with `model: "haiku"` for grep-style fan-out if you need it.

## What "drift" means here (rank findings by these)

1. **Parallel mirrors of logic** — two implementations of one contract (a second accessor,
   a second copy of a constant, a hand-rolled version of something a system already owns).
   The house rule is one implementation over swappable state.
2. **Rule/doc violations** — landed code contradicting an `.claude/rules/*.md` or
   `docs/domain/*.md` claim (e.g. node refs in commands, unseeded rolls a peer must reproduce,
   transcendental in gameplay code, `get_tree().paused`, code-composed control trees where a
   `.tscn` is the rule, `get_node` where an `@export` NodePath is the rule, per-node shader
   uniforms, hand-picked HDR floats, `graph.get_neighbours(n).size()` as degree,
   `owned_by == entity` as a relation test).
3. **Stale rules/docs** — a rule or domain doc that now describes something the window
   deleted or renamed (dead paths, dead symbols, superseded decisions still stated as current).
   Check `paths:` globs on scoped rules point at files that still exist.
4. **Issue residue** — for the issues in your list: (a) a follow-up the closing comments
   promised that never got filed or landed; (b) an owner decision in the comments the code
   quietly diverges from; (c) a TODO/FIXME/"temporary" left in code with no issue. Read
   issues with `gh issue view <n>` AND `gh issue view <n> --comments` (a 0-comment issue
   prints nothing — that's normal). Sample the architectural ones first; skip pure-polish ones.
5. **Dead code / leftover seams** — old paths kept alive after a cutover (compat shims,
   `_legacy`, unused signals, exports nothing reads), duplicated test fixtures.
6. **Layering** — UI reaching into systems it should get via `HudRoot.compose`/`bind()`;
   systems reaching into UI; autoload sprawl; a `.tscn` instance below another instance's
   root missing `[editable path=…]`.

## Report format (return this as your final message, ≤1200 words, nothing else)

```
## <subsystem> — verdict: <clean | minor drift | real drift>

### Findings (most severe first)
F1. [<mirror|rule|stale-doc|residue|dead|layering>] <one-line claim>
    where: <path:line>, <path:line>
    evidence: <2-3 lines max>
    fix: <concrete, ≤3 lines; say "delete X", "route Y through Z", "update rule W"; estimate S/M/L>
    confidence: <high|medium|low>
...

### Confirmed clean (one line each, what you checked and found fine)
### Skipped (what you did not get to)
```

Only report what you verified by reading the code. A finding without a path is not a finding.
Prefer 5 solid findings over 20 speculative ones.
