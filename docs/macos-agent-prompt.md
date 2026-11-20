# Prompt for the macOS agent

Paste the block below into a Claude Code session on the Mac. The session needs
push access to `rfay/kiri-notes`, and read access to `rfay/kiri` and `rfay/ddev`
(both public).

```text
Evaluate Kiri (https://github.com/libracoder/kiri), a small Docker-API-compatible
container runtime, as a Docker provider for DDEV on this Mac, following the plan in
the rfay/kiri-notes repository.

1. Clone https://github.com/rfay/kiri-notes to ~/kiri-test/kiri-notes and read,
   in this order, before doing anything: docs/lessons-learned.md (what earlier
   testing already found, including how to read each expected failure),
   README.md, docs/kiri-fixes.md and docs/macos-testing-plan.md. Don't
   re-investigate anything lessons-learned.md already explains. If you see one
   of its known failures, record it and move on.
2. Follow docs/macos-testing-plan.md step by step. Its "Ground rules" are binding:
   - don't change the default docker context;
   - don't touch the Mac's existing Docker provider or its DDEV projects;
   - run every Kiri command with DOCKER_CONTEXT and
     DDEV_XDG_CONFIG_HOME=~/kiri-test/ddev-config set;
   - never run `ddev poweroff` or a global prune against the normal provider.
3. Ask me before installing anything not listed in the plan's prerequisites, and
   before anything that needs sudo or an administrator password.
4. Where the plan is wrong for this Mac (a command, a context name, a path),
   adapt it, keep going, and record the change. If you learn something the next
   tester would otherwise have to rediscover, add it to docs/lessons-learned.md.
5. Write the results to results/macos-<YYYYMMDD>-<arch>.md as the plan's
   "What to report" section describes. Include the "For libracoder/kiri#595"
   summary written so it can be pasted as a PR comment. Commit it with a plain
   message and push it to the main branch of rfay/kiri-notes. If plan fixes were
   needed, commit those to docs/macos-testing-plan.md separately.
6. Don't post anything to libracoder/kiri, ddev/ddev or any other upstream
   repository. Don't open issues or PRs. I'll review the results first.
7. At the end, tell me the overall outcome in a few lines:
   - whether released Kiri works with released DDEV;
   - whether it works with the DDEV workaround branch;
   - whether #595 passes on macOS;
   - which macOS-specific checks failed.
   Leave the released Kiri installed and run the plan's cleanup step.
```
