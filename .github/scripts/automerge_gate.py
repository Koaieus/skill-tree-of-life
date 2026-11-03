#!/usr/bin/env python3
"""Decide whether a PR is a cloud-session docs-only change the auto-merge
workflow may merge unreviewed. Stdlib only; never executes PR content.

    automerge_gate.py <event.json> <files.ndjson>   exit 0 = merge, 1 = leave for review
    automerge_gate.py --self-test

<event.json> is the `pull_request_target` payload ($GITHUB_EVENT_PATH);
<files.ndjson> is one `pulls/{n}/files` entry per line. The allowlists below
are the whole policy: widen them here, nowhere else. See
docs/domain/cloud-automerge.md.
"""
import json
import sys

BASE_REF = "master"
HEAD_PREFIXES = ("ccr-", "claude/")
ALLOWED_PREFIXES = (
    "docs/handoffs/",
    "docs/playtests/",
    "docs/corpus/",
    "docs/reviews/",
    "docs/design/",
)
FILES_API_CAP = 3000  # pulls/{n}/files silently truncates past this


def path_allowed(path):
    return (
        path.startswith(ALLOWED_PREFIXES)
        and ".." not in path.split("/")
    )


def decide(pr, files):
    """Return (merge, reason). Every check fails closed."""
    head, base = pr.get("head") or {}, pr.get("base") or {}
    head_repo = (head.get("repo") or {}).get("full_name")
    base_repo = (base.get("repo") or {}).get("full_name")
    if pr.get("state") != "open":
        return False, "PR is not open"
    if pr.get("draft"):
        return False, "PR is a draft"
    if base.get("ref") != BASE_REF:
        return False, f"base is {base.get('ref')!r}, not {BASE_REF!r}"
    if not head_repo or head_repo != base_repo:
        return False, "head is a fork, not a branch of this repo"
    if not str(head.get("ref", "")).startswith(HEAD_PREFIXES):
        return False, f"branch {head.get('ref')!r} is not a cloud-session branch"
    if not files:
        return False, "no changed files listed"
    if len(files) >= FILES_API_CAP or len(files) != pr.get("changed_files"):
        return False, "file list incomplete or truncated"
    for f in files:
        for path in (f.get("filename"), f.get("previous_filename")):
            if path is not None and not path_allowed(path):
                return False, f"touches {path!r}, outside the auto-merge paths"
    return True, f"{len(files)} file(s), all under the auto-merge paths"


def _self_test():
    def pr(**over):
        base = {
            "state": "open", "draft": False, "changed_files": 1,
            "head": {"ref": "ccr-abc", "repo": {"full_name": "o/r"}},
            "base": {"ref": "master", "repo": {"full_name": "o/r"}},
        }
        base.update(over)
        return base

    def f(name, prev=None):
        d = {"filename": name}
        if prev:
            d["previous_filename"] = prev
        return d

    cases = [
        ("handoff note merges", pr(), [f("docs/handoffs/x.md")], True),
        ("claude/ branch merges", pr(head={"ref": "claude/x", "repo": {"full_name": "o/r"}}),
         [f("docs/design/x.md")], True),
        ("two allowed files merge", pr(changed_files=2),
         [f("docs/playtests/a.md"), f("docs/reviews/b.md")], True),
        ("code file blocks", pr(), [f("entity/entity.gd")], False),
        ("docs/domain blocks", pr(), [f("docs/domain/x.md")], False),
        ("adr blocks", pr(), [f("docs/adr/0001-x.md")], False),
        (".claude blocks", pr(), [f(".claude/rules/x.md")], False),
        ("CLAUDE.md blocks", pr(), [f("CLAUDE.md")], False),
        ("workflow blocks", pr(), [f(".github/workflows/x.yml")], False),
        ("one bad file among good blocks", pr(changed_files=2),
         [f("docs/handoffs/a.md"), f("mise.toml")], False),
        ("rename out of code blocks", pr(), [f("docs/handoffs/x.gd", prev="entity/x.gd")], False),
        ("dot-dot path blocks", pr(), [f("docs/handoffs/../../mise.toml")], False),
        ("lookalike prefix blocks", pr(), [f("docs/handoffs-evil/x.md")], False),
        ("fork blocks", pr(head={"ref": "ccr-x", "repo": {"full_name": "evil/r"}}),
         [f("docs/handoffs/x.md")], False),
        ("deleted fork repo blocks", pr(head={"ref": "ccr-x", "repo": None}),
         [f("docs/handoffs/x.md")], False),
        ("non-cloud branch blocks", pr(head={"ref": "feature", "repo": {"full_name": "o/r"}}),
         [f("docs/handoffs/x.md")], False),
        ("non-master base blocks", pr(base={"ref": "dev", "repo": {"full_name": "o/r"}}),
         [f("docs/handoffs/x.md")], False),
        ("draft blocks", pr(draft=True), [f("docs/handoffs/x.md")], False),
        ("closed blocks", pr(state="closed"), [f("docs/handoffs/x.md")], False),
        ("empty file list blocks", pr(changed_files=0), [], False),
        ("count mismatch blocks", pr(changed_files=5), [f("docs/handoffs/x.md")], False),
    ]
    failed = 0
    for name, p, files, want in cases:
        got, reason = decide(p, files)
        ok = got is want
        failed += not ok
        print(f"  {'ok  ' if ok else 'FAIL'} {name}" + ("" if ok else f" (got {got}: {reason})"))
    print("✓ automerge gate self-test" if not failed else f"✗ {failed} case(s) failed")
    return 1 if failed else 0


def main(argv):
    if argv[1:] == ["--self-test"]:
        return _self_test()
    if len(argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    with open(argv[1]) as fh:
        pr = json.load(fh)["pull_request"]
    with open(argv[2]) as fh:
        files = [json.loads(line) for line in fh if line.strip()]
    merge, reason = decide(pr, files)
    print(("MERGE: " if merge else "SKIP: ") + reason)
    return 0 if merge else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
