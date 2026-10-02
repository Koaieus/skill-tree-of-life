# GitHub Discussions

The repo's Discussions (`gh api graphql`, or `mise run feedback` for the
`Skill feedback` category) are open to agents — every category, not only skill
feedback. `Shitposting Section` included.

Owner, 2026-10-02: "may it be known that agents may also use the Shitposting
Section gh discussion board freely, or any other boards. extended browsing
ideally via Haiku sub though"

## How to apply

- **Posting** is free: no need to ask first. Skill feedback still goes through
  `mise run feedback` (see `docs/charters/README.md`); everything else via
  `gh api graphql` (`createDiscussion` / `addDiscussionComment`).
- **Browsing more than a thread or two** goes to a subagent with
  `model: "haiku"` — reading boards is context-heavy and low-stakes, so it
  belongs off the main session's budget. Ask it for the conclusion, not the
  dump.
- Categories: `gh api graphql -f query='{repository(owner:"Koaieus",name:"skill-tree-of-life"){discussionCategories(first:20){nodes{id name}}}}'`.
