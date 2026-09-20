# ADR — charter

The design behind `.claude/skills/adr/SKILL.md`. The skill is derived from
this; change the wish here, then re-derive the file. See [README](README.md)
for the protocol. The *format* itself is owned by
[docs/domain/adr.md](../domain/adr.md); this charter only says why a skill
exists on top of it and what the skill must make an author do.

## Why a skill, when the format doc and a librarian already exist

The format was set by an Opus session on its own (owner, 2026-09-21: *"which
I didn't have a say in, I let Opus just do whatever"*), and it has held across
26 records because the writer each time was a large model with the convention
doc in context. Two things are not covered by that:

1. **Authorship is the deciding agent's, never the librarian's.** The
   `adr-librarian` agent is Sonnet, read-only, and drafts on request; the
   convention doc forbids it writing a record because a librarian writing up
   an owner call is the laundering `issue-workflow.md` bans. So the writer is
   always the session that sat with the owner — and that session needs the
   procedure, not just the template. Owner, 2026-09-21: *"Opus/Fable writes
   more accurately."*
2. **The failure mode is a good-looking record that is wrong in one of five
   mechanical ways** — a decision that has no rejected alternative (not an
   ADR), an owner call paraphrased instead of quoted, a `date:` that is the
   file date not the decision date, a domain doc left half-migrated, or an
   accepted record edited instead of superseded. Each of these the convention
   doc explains; none of them a template enforces. `adr-hygiene` catches the
   structural ones after the fact; the skill is the checklist before.

## Laws

1. **Gate first.** Before writing: is there a rejected alternative, is it
   engineering not game design, and is it settled (owner has spoken) rather
   than still forking? Any no → not an ADR; say which home it goes to instead.
2. **Check it is not already decided.** Grep `docs/adr/index.md` and ask the
   librarian if the topic smells settled. A hit means *supersede*, not a new
   sibling.
3. **Quote the owner, verbatim, dated.** Every decision line traces to a
   quote in the transcript or issue; the skill makes the author collect the
   quotes before drafting. A paraphrase re-enters the record as the agent's
   own conclusion, at the bottom of the authority ladder.
4. **`date:` is the decision date.** Not the file date. A record drafted a day
   later still carries the day the owner spoke.
5. **Title is the decision, not the topic.** Actionable without opening the
   file.
6. **Alternatives are the section that earns the format.** One subsection per
   rejected option, why it lost, and — for a tentative decision — the named
   trigger under which the most-likely-revived alternative comes back.
7. **Tentative is fine; unrecorded is not.** A decision the owner calls
   tentative is still `accepted`; tentativeness is expressed as the supersede
   trigger in *Consequences*, never as `proposed` (that status is for framing
   a fork, and the repo's design gate is `/swarmify`, not ADR review).
8. **Migrate the domain doc in the same commit.** If a `docs/domain/` page
   carries the decision prose, move the dated verdict and its rejected options
   out together and leave a link; `adr-hygiene`'s decision-prose counter must
   not rise.
9. **Index row, hygiene, commit, link back.** Add the row, run
   `mise run adr-hygiene`, commit the record and index (explicit paths — the
   checkout is shared), then comment the ADR path and sha on the source issue.
10. **Supersede, never edit.** The only edit an accepted record ever receives
    is `status: superseded` + `superseded-by:`. The skill carries the
    supersede path as a first-class branch, not a footnote.

## What the skill must not contain

The template, the frontmatter field list, or the boundary table — those live
in `docs/domain/adr.md` and are linked, not copied (a copy is a parallel
mirror that rots). Issue numbers, incidents, this charter's reasoning.
