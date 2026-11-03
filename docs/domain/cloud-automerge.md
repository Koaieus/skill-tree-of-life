# Cloud docs auto-merge

A cloud (claude.ai/code) session can push its own branch and open a PR, but
it cannot land on master. For a small set of note-like docs paths it does not
have to: `.github/workflows/cloud-docs-automerge.yml` merges the PR on its
own. Anything else waits for a normal review.

## What merges

A PR is squash-merged (one linear commit; the branch's intermediate commits,
which the net-diff check never saw, stay off master) iff **all** hold. The policy
is `.github/scripts/automerge_gate.py`; its constants are the only place to
widen or narrow it, and `mise run automerge-gate-selftest` covers them.

- open, not a draft, based on `master`;
- the head is a branch of **this** repo — the repo is public, so a fork PR
  never qualifies;
- the branch starts `ccr-` or `claude/` (cloud PRs are authored as the owner,
  so the author proves nothing; only the owner can push branches here);
- every changed path — and, for a rename, its old path — is under
  `docs/handoffs/`, `docs/playtests/`, `docs/corpus/`, `docs/reviews/` or
  `docs/design/`, **and** is an inert file: extension `.md`, `.txt`,
  `.jsonl`, `.csv` or `.png`; no dot-named file or directory; not named
  `CLAUDE.md` / `CLAUDE.local.md` / `AGENTS.md`; no `swarm-*` / `whip-*` /
  `*.inbox` component.

The directory list alone is not enough. Under `docs/` Godot's editor scan
loads any `.gdextension` it finds (native code on the next `check`), and
Claude Code loads a nested `CLAUDE.md` when an agent works in its directory
(`docs/design/` already has one). The swarm-train relief lead *lands* the
branch a `docs/handoffs/swarm-*.inbox/` report names. Hence the extension,
basename and component checks.

Left out on purpose: `docs/domain/`, `docs/adr/`, `docs/charters/`,
`.claude/`, `CLAUDE.md` — these steer every later agent, so an unreviewed
bad edit spreads; and `.github/`, `.mise/` and all code, which execute.

**Accepted risk:** handoff and design docs are still *read* by later
sessions as briefs (`/handoff` writes the next session's starting point to
`docs/handoffs/`). An unreviewed one can mislead an agent, but only through
the normal channel of an agent reading prose; it cannot run anything.

## Why it is safe

- **`pull_request_target`** runs master's workflow and gate, never the PR's,
  so a PR cannot rewrite the check that judges it. No step checks out or runs
  the PR head — the gate reads only the file *list* from the API. Keep it so:
  a checkout of the head under this trigger hands PR code a write token.
- **The merge is pinned to the judged sha.** A push between the check and the
  merge makes GitHub refuse it, and that push's own run decides afresh.
- **Fails closed**: a truncated or mismatched file list, a malformed file
  entry, a deleted fork, or a gate whose self-test fails all skip the merge.
  A gate *crash* turns the run red rather than reading as a skip.
- **The branch prefix is the trust boundary.** Anything that can push a
  `ccr-*` or `claude/*` branch here can auto-merge docs. Today that is only
  the owner and the owner's cloud sessions; installing the Claude GitHub App's
  issue-comment action (which also pushes `claude/*`) or granting anyone else
  write access widens it.

The verdict is in the run's job summary. A skipped PR just stays open for
review — nothing is commented.

## Gotchas

- A merge made with the workflow token triggers no further workflows.
- If master ever gets a branch rule requiring reviews, this merge is refused
  until the token is allowed to bypass it.
- The branch is not deleted after merge; a cloud session that keeps working
  restarts it from master.
