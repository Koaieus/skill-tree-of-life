**Observed (3 runs).** In unattended auto-mode runs the permission classifier refuses Bash calls that a drone or the top needs to finish work, and nothing in the skills says what to do:
- 2026-10-14 (session 6ac11163): drone d-handback reported "NOT LANDED: the permission classifier denied my Bash call that ran the last edits, a commit and `mise run land`, and then denied a plain `git status`." Its fix for the ~15 interim hand-back wakes sat in `wt-interim-handback` until the owner said "land it" at 00:15.
- 2026-10-16 (153e4757): "eight are still on disk. The auto-mode permission check blocked their removal, so delete them by hand."
- 2026-10-14 top final lists `wt-interim-handback`, `wt-gloomflux` and six `.claude/worktrees/agent-*` still open.

**Proposed.** (1) A denied call is stop-and-report: the drone's report names the exact refused command and the branch/sha state it is sure of; the lead (whose calls are not denied the same way) lands or tears down, and if it is refused too the command goes verbatim under "Needs the owner" in the morning report as a pasteable line. (2) The report gets a "Commands refused" line so the owner sees leftovers without reading prose.
