Launch a long command (the ~215s `mise run test` suite, `refresh`, a bench) ONCE with `run_in_background: true`, then END YOUR TURN — no sleep, no tail follow, no re-reading the output file;
the harness resumes you on exit, so every poll is a full round-trip bought for nothing. See docs/domain/long-running-commands.md
