# Agent workflow — Pulse iOS

The convention every agent and subagent follows in this repo. The goal: an agent
with zero prior context can pick up any issue and know exactly how to claim it,
work it, verify it, and close it — without asking a human to restate the rules.

**Issues are the only source of scope.** If it is not in the issue body, it is
not in the change. If the issue is wrong or incomplete, comment on it; do not
quietly widen or narrow it.

---

## 1. Orient

Read, in this order, before writing a line of code:

1. `docs/ARCHITECTURE.md` — targets, layers, milestones. Tells you which target
   your change belongs in.
2. `docs/DATA-CONTRACT.md` — item shape, state machine, and the iOS ↔ Mac mirror
   protocol. **Required reading before touching any model.**
3. `README.md` — build commands and the layout.

If you are working inside a bb workspace, run `bb status` first to see the
project, thread and environment you are in, so you do not commit to the wrong
checkout.

```sh
gh issue view <N>          # the full issue: scope, files, acceptance
git log --oneline -10      # what landed recently
git status                 # never start on top of someone's uncommitted work
```

## 2. Claim

Claim the issue *before* starting, so two agents never work the same one:

```sh
gh issue comment <N> --body "/claim"
gh issue edit <N> --add-assignee @me
```

Never start an issue whose `## Depends on` issues are still open. A dependency
that has not landed means the interfaces you are coding against do not exist yet.

## 3. Branch

One branch per issue, off an up-to-date `main`:

```sh
git fetch origin
git switch main && git pull --ff-only
git switch -c issue/<N>-<kebab-slug>     # e.g. issue/12-board-view
```

Never commit directly to `main` unless the issue explicitly says a direct commit
is acceptable. Never force-push, ever — if history needs fixing, add a commit.

## 4. Work

- **Stay inside the issue's `## Files` list.** That list is the blast radius the
  issue author agreed to. Touching a file outside it is how a small fix becomes
  an unreviewable change.
- **`Pulse.xcodeproj` is generated. Never commit it.** It is produced by
  `xcodegen generate` from `project.yml` and is listed in `.gitignore`. If you
  need a new target, file, build setting or Info.plist key, change
  `project.yml`, then regenerate. A hand-edit to the `.xcodeproj` is lost on the
  next generate and will not be reviewed.
- **`PulseCore` stays free of UI and EventKit imports.** No `import SwiftUI`,
  no `import WidgetKit`, no `import EventKit` inside `PulseCore/Sources`. That
  package is the testability boundary: it must build and run its tests with
  plain `swift test` on macOS, no simulator. Platform code lives in
  `Pulse/` (app) and `PulseWidgets/`; adapt EventKit behind the `CaptureSource`
  protocol as described in `docs/ARCHITECTURE.md`.
- **Models and contracts change in `docs/DATA-CONTRACT.md` first**, then in both
  implementations, then bump `schemaVersion`. The Mac plugin mirrors the same
  JSON shape; an unannounced field change breaks it silently.
- If scope genuinely must grow, **stop**. Comment on the issue with what you
  found and why the file list is insufficient. Do not expand scope unilaterally.

## 5. Verify

Run every command in the issue's `## Acceptance` section **verbatim**. Do not
substitute a "similar" command that happens to pass.

The three standard verification commands for this repo:

```sh
# 1. Core domain: fast unit tests, no simulator required
cd PulseCore && swift test

# 2. Generate the Xcode project from project.yml
xcodegen generate

# 3. Full app build against a simulator, no signing
xcodebuild -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /tmp/pulse-build \
  CODE_SIGNING_ALLOWED=NO build
```

Lint (optional locally, non-blocking in CI until the tree is clean):

```sh
bash Scripts/lint.sh          # check
bash Scripts/lint.sh --fix    # auto-format, then check
```

**Definition of done: code + tests + the verification command output pasted into
the closing comment.** "It builds for me" is not done. The pasted output is the
evidence that a reviewer — human or agent — can check without re-running
anything.

Paste real output, not a paraphrase. Include the exit status. If a command is
expected to fail for a known reason, say so explicitly and link the issue.

## 6. Commit

[Conventional Commits](https://www.conventionalcommits.org/), scoped to the part
of the repo you touched:

| Prefix | Use for |
| --- | --- |
| `feat(core):` | `PulseCore` models, store, capture, sync |
| `feat(ui):` | SwiftUI views in `Pulse/` |
| `feat(sync):` | snapshot/command protocol, CloudContainer |
| `fix:` | bug fixes, in any target |
| `chore:` | CI, tooling, docs, project.yml |

Examples:

```
feat(core): add sticky Done/Snooze state machine to ItemStore
feat(ui): render Now/Next/Later/Nice to Know board sections
fix(sync): ack commands before truncating commands.jsonl
chore: add CI, lint config and agent workflow doc
```

Keep commits reviewable: one logical change each. Rebase on `origin/main`
before pushing — `git fetch origin && git rebase origin/main` — and resolve
conflicts in your own favour only for lines you actually changed.

```sh
git fetch origin && git rebase origin/main
git push -u origin HEAD
```

## 7. Deliver

One issue per PR. Title it with the milestone prefix and a short summary:

```
M0.2 — CI builds PulseCore and runs swift test on macOS
```

Body must contain `Closes #<N>` and the acceptance-command output from step 5:

```sh
gh pr create --title "M0.2 — CI builds PulseCore and runs swift test on macOS" \
  --body "Closes #2

## Verification
\`\`\`
$ cd PulseCore && swift test
...
\`\`\`"
```

If the issue explicitly permits a direct commit to `main`, reference the issue
in the commit body instead (`Refs #<N>`), and only after the acceptance commands
pass locally.

## 8. Close

Merge only after CI is green. Both `core` and `app` jobs must pass; `lint` is
non-blocking today and becomes required once the tree is clean (see the comment
in `.github/workflows/ci.yml`). The `Closes #<N>` reference closes the issue on
merge — do not close it by hand before that.

If you merged by direct commit, comment the verification output on the issue and
close it explicitly:

```sh
gh issue close <N> --comment "Done in <sha>.

\`\`\`
$ cd PulseCore && swift test
...
\`\`\`"
```

## 9. When you are blocked

Report the blocker in the issue rather than silently narrowing scope. A half-
implemented feature that "passes" because it skips the hard part is worse than
an open issue with a clear question on it.

Do:

```sh
gh issue comment <N> --body "Blocked on <what>. Tried <approach>, hit <error>.
Need <decision/info>. Leaving the issue open; no code pushed."
```

Do not:

- comment out failing tests to get green CI;
- implement a subset of the acceptance criteria and close the issue;
- change `docs/DATA-CONTRACT.md` unilaterally to make your code compile;
- force-push to "clean up" a branch;
- restart work another agent has claimed.

Leave the issue open. Leave the branch in place if it contains useful
investigation. Say what you tried and what you need.
