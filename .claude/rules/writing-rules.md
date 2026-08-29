---
description: Writing a rule, doc, or CLAUDE.md entry — keep the always-on tier tiny; scope with paths:, leave a Breadcrule, and cite a reproduced incident for any diagnostic claim
paths:
  - ".claude/rules/*.md"
  - "CLAUDE.md"
  - "docs/domain/*.md"
---

# Writing a rule

You're reading or editing a rule / `CLAUDE.md`. Before you add a page:

- **A rule with no `paths:` is always-on** — injected into *every* turn of *every*
  session. Length there is a tax on every future agent. Add a `paths:` glob so it
  loads only when the files it guards are read. Full length is fine once scoped.
- **If it belongs in the always-on tier anyway** (every agent should know it
  exists, or it's not a tidy set of file paths), write a **Breadcrule**: one line
  that states the claim *and* points to a doc — `Breadcrule: <claim>. See
  docs/domain/<topic>.md` — and put the body in the doc.
- **Extension globs work** — `paths: ["**/*.tscn"]` matches, verified by probe
  (2026-08-03). Directory prefixes (`graph/**`) are convention, not a constraint,
  so a gotcha tied to a *file format* should be scoped to that format rather than
  to a list of directories that happens to contain it.
- **A gotcha you got bitten by that was already in the doc is a CRUMB bug, not a
  doc bug.** You didn't open the doc because the crumb didn't tell you to. Fix the
  crumb's trigger wording — name the failure mode, not the topic — and don't add a
  paragraph to the doc that nobody was going to reach either.
- Run **`mise run rules-hygiene`** whenever you touch this tier. It reports
  over-budget always-on rules, docs-wearing-a-rule's-hat, dead crumbs, stale
  references, and **dead globs** — a `paths:` matching zero files makes a rule that
  silently never loads, which nothing else can catch. It also counts the
  **`~/.claude` user tier** (the auto-memory index + any unscoped global rule),
  which is always-on and lives outside the repo — so a claim duplicated between a
  memory and a rule is paid twice, every turn.
- Lead with the rule, then **Why:** / **How to apply:**. Small-rule discipline is
  in `CLAUDE.md` → *Knowledge accumulation*.

## You are carrying this payload, so you may cut it

A rule is not a diary. Every line you add is loaded into future agents who are
working on something else, and the agent writing a rule is the one worst placed
to judge it: fresh from hours on one problem, maximum recency bias, and it never
pays the cost — every *later* session does. So the incentive is broken by
construction, and the correction has to be a habit, not good intentions.

**When you open a rule to add to it, you have also opened it to cut.** You have
the source in one hand and the rule in the other; you are, right now, the best-
qualified reader that file will get. Use it:

- **Delete what's stale or wrong.** A rule describing code that moved is worse
  than no rule — it actively misleads.
- **Delete what's now obvious**, enforced by a test, or apparent from the code.
- **Cut the narrative.** War stories, "we tried X then Y", and debugging
  chronology are the doc's job. The rule keeps the claim and the fix.
- **Compress.** A paragraph that survives as one sentence should be one sentence.
- **Demote by size.** A rule past ~150 lines has stopped being a rule and become
  a doc wearing a rule's hat. Move the body to `docs/domain/<topic>.md`, leave the
  gotchas. If it's *also* always-on, leave a breadcrule.

**Adding "just one paragraph" is the failure mode**, because it's true every
time and it compounds. Treat a rule like a fixed budget: if your paragraph earns
its place, something else can lose its place. Land net-neutral or smaller unless
the addition genuinely outweighs what's there.

## Calibrate the alarm to the actual blast radius

A rule can be net-negative through **tone**, not just length. An overstated
warning makes agents second-guess themselves, stall, invent workarounds, ask for
permission they don't need, or burn turns investigating — attention taken
straight from the implementation they were hired to do. That cost is invisible in
the rule's byte count and it recurs on every session.

So state the *expected* outcome before the worst case, and say what the response
actually is. If the blast radius is small, say so plainly:

- **Is it recoverable?** If it's in git, say that — "you can see it and revert
  it" converts dread into a glance.
- **What's the realistic case, not the scary one?** Lead with "usually nothing
  or cosmetic noise", then the rare bad case.
- **What is the whole response?** If it's one `git diff`, say *one `git diff`*
  and say the ceremony is not needed — otherwise agents invent their own.
- **Say what NOT to do.** "Don't stall, don't work around it, don't ask" is
  often the highest-value line in the rule, because the default failure is
  over-caution, not under-caution.

Words like *silently*, *castrates*, *mandatory*, *always*, *never* are load
bearing — spend them on things that genuinely warrant them, or they stop meaning
anything on the ones that do.

Ask the deciding question honestly: *will an agent who is not me, working on
something else, be better off carrying this?* Rules exist for the 99% who never
hit your bug — not for the one who just did.

## Cite the incident, or don't add the claim

A **diagnostic** claim — one that tells a future agent *what a symptom means* —
compounds differently from one about tone or length. A wrong entry doesn't just
cost bytes, it **primes a wrong diagnosis**: the next agent spends turns chasing
your cause, and the usual repair is *another* paragraph correcting the first. The
doc ends up arguing with itself and everyone carries both sides.

That loop is attested here, not hypothetical. `docs/domain/godot-workflow.md`'s
class-cache section regrew 91% by bytes in the month *after* it was deliberately
cut back, entirely through additions whose commit messages cite no observed
instance (audited 2026-08-29).

So: **an addition asserting "symptom X means cause Y" must name the instance that
showed it** — the error string, the test count, a sha, an issue — in the commit
body, not just the diff.

- **No incident, no entry.** *"It is the cache, every time"* with an empty commit
  body is a guess wearing a rule's confidence. Write what you saw, or write
  nothing.
- **Rule out the benign explanation first, in writing.** Most "the tool silently
  corrupted my file" claims are normal serialization or stale committed state.
  Godot omits any property equal to its script's *current* default, so shifting a
  default makes a `.tres` line appear or vanish with the effective value
  unchanged — indistinguishable in a diff from the editor eating a field. Same
  family as the `.import`-churn misread.
- **Ruling a cause OUT beats adding another warning.** If the doc's own framing
  sent you down the wrong path, cut or narrow the section that misled you. A
  "this look-alike is NOT that" paragraph leaves the misleading claim standing
  and doubles what every future agent carries.

Full tiering (inline gotcha → scoped rule → breadcrule+doc → doc), the `paths:`
mechanism, and how to write the crumb: **`docs/domain/breadcrules.md`**.
