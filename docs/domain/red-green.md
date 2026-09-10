# Red-green

**When a change is testable, the test goes first — and you watch it fail for the
right reason before you write a line of the fix.** Not every issue earns a test;
the ones that do are strictly better served by red→green than by writing the
test afterwards.

Two claims, in order of how often they bite: *which* changes earn a test, and
*how to get a genuinely red test in this repo* — because in Godot + GUT, "red"
is not the default failure mode. A broken test file reports **green**.

## 1. Does this change earn a test?

The house vocabulary is swarmify's: done is **"a failing test to make green, or
an exact behavioural spec."** The second half is not a consolation prize — it is
the correct answer for a real share of the work.

Three worked examples, from drones in the corpus, cheapest first:

| Drone run | Shape | Verification |
|---|---|---|
| `6743ce24` | visual / shader fix, no runtime-testable behaviour | `mise run check` only — **no test, correctly** |
| `e96e4971` | behaviour change under existing coverage | `check` → `test:dir` on the touched dir |
| `c0f9d75f` | new behaviour | new test, red first → green → suite once |

Earns a test-first cycle:

- **New behaviour with an observable seam** — a function's return, a signal
  emitted, a stat resolving to a number, a command applied.
- **A bug fix.** The reproduction *is* the test, and writing it first is the
  only way to know the fix fixed anything. Never fix first and add the test
  after: a test written against working code proves nothing about the bug.
- **A contract you're about to depend on** — a new `class_name`'s public
  surface, a resolver's ordering guarantee.

Does **not**:

- **Visual acceptance.** "Does it look right" gets no test harness. Shaders,
  layouts, tuning of a `.tres` — `check` (plus `check-shaders`) is the gate.
  A test must never pin an authored `.tres` value either — the owner tunes
  those, and a golden that goes red on every tuning pass is noise.
- **A pure refactor with the tests already green.** The existing suite *is* the
  red-green loop; you're keeping it green, not turning it green.
- **A one-line rename, a doc, a comment.**

If the issue went through `swarmify`, its `## Acceptance spec` already names the
test — use it verbatim rather than inventing a second one. If it didn't, naming
the test is step one of implementing, and it belongs in the plan you present.

## 2. Getting a genuinely RED test here

The project-specific trap, and the reason naive TDD fails in this repo: **a test
file with a parse error is silently skipped and the suite still reports
passing.** GUT logs `Ignoring script … because it does not extend GutTest` and
moves on; the totals just don't include your file. So "I wrote a test and the
suite isn't green" is *not* what you observed — you have to check what you
actually observed.

And a brand-new test is the single most likely file in the repo to parse-error,
because TDD writes it against code that **does not exist yet**. A reference to a
`class_name` or method you haven't written is a **parse error, not a red test**.

So the red step has a shape:

1. **Stub the surface first.** Empty class, method returning a default, signal
   declared. Just enough that the test file *parses*. This is not cheating —
   it is the design step TDD is actually for: you are deciding the seam.
2. **New or renamed `class_name`? `mise run refresh`.** A fresh worktree has no
   class cache, and a new type is invisible to the parser until it does — the
   same failure wearing a different hat.
3. **Run `mise run test:one -- res://test/unit/test_<yours>.gd` and read the
   verdict, not the exit code.** Two things must be true:
   - **Your test ran.** The script count is non-zero and no `Ignoring script`
     line appears under `run health:`.
   - **It failed on your assert line**, with the value you expected to be wrong
     — not on a load error, a missing autoload, or a null.
4. *Then* implement, and re-run the same `test:one` for green.

A red you didn't read is worth nothing. The whole value of the red step is the
information that the test can distinguish broken from fixed; a file that never
ran carries none of it.

Full trap list — the `:=`-on-`autofree()` inference error, `Array[StringName]`
being `.tres` syntax and not GDScript, `free()` vs `queue_free()` on a
level-sized instance, the `class_name`-less visual leaves that need a
`preload` — lives in `.claude/rules/testing.md`. Read it before writing a new
test file, not after it mysteriously "passes".

## 3. Then the ladder

Red→green is about *order*, not about how much you run. Cost discipline is
unchanged and orthogonal:

```
mise run check                                       # ~20s — after every script edit
mise run test:one -- res://test/unit/test_<yours>.gd # your red-green loop
mise run test:dir -- res://test/unit/<subsystem>/    # once you believe you're green
mise run test                                        # full suite — ONCE, at final green
```

The full suite (~215s) is a gate, not a feedback loop. TDD does not buy you more
full runs — it buys you a `test:one` that means something.

## Where this is enforced

- `warp` — step 3a, before implementing.
- `drone` — the `## Red-green` section; the orchestrator's brief names the test.
- `swarmify` — writes the acceptance test into the issue in the first place.
- `swarm` — Gate #3: a unit isn't dispatchable without a failing test or an
  exact spec.

## See also

- `.claude/rules/testing.md` — GUT mechanics and the full gotcha list.
- `docs/domain/godot-workflow.md` — when `mise run refresh` is the answer.
- `.claude/rules/long-running-commands.md` — background the suite, end your turn.
