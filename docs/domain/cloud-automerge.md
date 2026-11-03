# Cloud docs auto-merge

A cloud (claude.ai/code) session can push its own branch and open a PR, but
it cannot land on master. For a small set of note-like docs paths it does not
have to: `.github/workflows/cloud-docs-automerge.yml` merges the PR on its
own. Anything else waits for a normal review.

## What merges

A PR is merged (rebase, so master stays linear) iff **all** hold. The policy
is `.github/scripts/automerge_gate.py`; its constants are the only place to
widen or narrow it, and `mise run automerge-gate-selftest` covers them.

- open, not a draft, based on `master`;
- the head is a branch of **this** repo — the repo is public, so a fork PR
  never qualifies;
- the branch starts `ccr-` or `claude/` (cloud PRs are authored as the owner,
  so the author proves nothing; only the owner can push branches here);
- every changed path — and, for a rename, its old path — is under
  `docs/handoffs/`, `docs/playtests/`, `docs/corpus/`, `docs/reviews/` or
  `docs/design/`.

Left out on purpose: `docs/domain/`, `docs/adr/`, `docs/charters/`,
`.claude/`, `CLAUDE.md` — these steer every later agent, so an unreviewed
bad edit spreads; and `.github/`, `.mise/` and all code, which execute.

## Why it is safe

- **`pull_request_target`** runs master's workflow and gate, never the PR's,
  so a PR cannot rewrite the check that judges it. No step checks out or runs
  the PR head — the gate reads only the file *list* from the API. Keep it so:
  a checkout of the head under this trigger hands PR code a write token.
- **The merge is pinned to the judged sha.** A push between the check and the
  merge makes GitHub refuse it, and that push's own run decides afresh.
- **Fails closed**: a truncated or mismatched file list, a deleted fork, or a
  gate whose self-test fails all skip the merge.

The verdict is in the run's job summary. A skipped PR just stays open for
review — nothing is commented.

## Gotchas

- A merge made with the workflow token triggers no further workflows.
- If master ever gets a branch rule requiring reviews, this merge is refused
  until the token is allowed to bypass it.
- The branch is not deleted after merge; a cloud session that keeps working
  restarts it from master.
