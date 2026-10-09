# cc-guard

**Deterministic guard rails for Claude Code.**

Rules written as prose in `CLAUDE.md` are advice. The model follows them most of
the time, and "most of the time" is exactly when a secret lands in a commit, an
`any` slips into a strict codebase, or a subagent reports "all tests pass" without
ever running them. cc-guard turns the rules that actually matter into hooks that
run on every relevant action, cannot be skipped by a tired model, and give Claude
a precise reason to fix the problem.

It is a plain [Claude Code plugin](https://code.claude.com/docs/en/plugins): a
handful of bash scripts, no daemon, no network, no LLM calls. Each check costs a
few milliseconds.

## What it guards

| When | Check | Result |
|---|---|---|
| Claude runs `git commit` | **Secrets.** gitleaks scans the staged diff (working tree and untracked files too with `-a` or a preceding `git add`), using pinned default rules so a repo cannot switch detection off. | commit **denied** with rule id, file and line; secret values are redacted |
| | **Commit subject.** `type(scope): description`, max 72 chars, types `feat fix refactor docs test chore perf ci build style revert`. `fixup!`, `squash!`, merge and revert commits are exempt. | **denied** with the regex and what was sent |
| | **No emoji** anywhere in the message. Check marks, arrows, (TM) and keyboard glyphs are fine. | **denied** |
| | `--no-verify` / `-n` would skip the git hooks below. | **denied** |
| Claude edits or writes a file | **TypeScript `any`** without a justification comment after it on the same line or on the line above. | edit result **blocked** until fixed |
| | **`@ts-ignore` / `@ts-expect-error`** without a reason text. | **blocked** |
| | **Emoji** in code or comments (`.md` and `.txt` are exempt). | **blocked** |
| | `console.log` outside test files, `TODO`/`FIXME`, `eslint-disable` without `-- reason`, Czech text in files, shellcheck findings in shell scripts. | **warning** injected into Claude's context, work continues |
| | Optional: run the project's own biome or prettier on the edited file. | formatted in place (opt-in, see below) |
| Claude delegates to a subagent | **Evidence contract.** Any subagent that can run commands or edit files gets a fixed `VERIFICATION` block appended to its prompt: list the exact commands, exit codes and raw output, label everything else `UNVERIFIED`. Read-only agents (Explore, Plan, agents without Bash/Edit/Write) are untouched. | prompt rewritten transparently |
| A subagent reports back | Report has no `VERIFICATION` section, or says "should work" / "all tests pass" with no exit code within five lines. | **warning** next to the report: treat as unverified, re-run the check yourself |
| Anyone commits from a shell (optional git hooks) | Same secret scan and commit message rules as above, plus `Co-Authored-By: Claude*` trailers are stripped from the message. The hooks chain to the repo's own `.git/hooks`, so husky and friends keep working. | commit **rejected** by git |

"Blocked" means the hook returns a structured reason and Claude has to fix the
file or the command before it can move on. "Warning" means Claude sees a note
but is not stopped.

## Install

### For yourself (every project)

```sh
claude plugin marketplace add wraithyy/cc-guard
claude plugin install cc-guard@cc-guard
brew install gitleaks ast-grep shellcheck     # Linux: distro packages or release binaries
```

gitleaks is required: without it every commit is denied rather than silently
unscanned. ast-grep and shellcheck are optional; their checks are skipped when
missing.

Optional git-level hooks, so commits made outside Claude get the same treatment:

```sh
git clone https://github.com/wraithyy/cc-guard ~/cc-guard
~/cc-guard/plugins/cc-guard/scripts/install-git-hooks.sh --global
```

This copies `pre-commit` and `commit-msg` into `~/.config/git/hooks` and sets
`core.hooksPath`. The installed plugin lives under
`~/.claude/plugins/cache/cc-guard/cc-guard/<version>/` if you prefer to run the
installer from there.

### For a project (teammates get it automatically)

Add to the repo's `.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "cc-guard": { "source": { "source": "github", "repo": "wraithyy/cc-guard" } }
  },
  "enabledPlugins": { "cc-guard@cc-guard": true }
}
```

Claude Code prompts each teammate to install the plugin when they open the repo.
Add `brew install gitleaks ast-grep shellcheck` to the project's setup docs, and
optionally `scripts/install-git-hooks.sh --repo` for the git-level hooks (it prints
a husky/lefthook snippet instead when the repo already manages hooks).

## Configure

Everything is git config, so it scopes per repo or per directory with `includeIf`.
Environment variables override git config.

| Setting | Default | Meaning |
|---|---|---|
| `cc-guard.secrets` | `true` | run the gitleaks scan |
| `cc-guard.commitFormat` | `true` | enforce subject format and no-emoji. Set `false` in work repos with their own convention, or override the pattern instead |
| `cc-guard.subjectRegex` | conventional commits | ERE for the first line, e.g. `^[A-Z]+-[0-9]+ ` for Jira keys |
| `cc-guard.format` | `false` | run the project's biome/prettier after each edit. Off by default because it executes code from the repo's `node_modules`; turn it on for directories you trust |
| `CC_GUARD_SKIP` | | comma list of hooks to disable for a session: `commit`, `edit`, `agent` |
| `CC_GUARD_LANG_WARN` | `1` | `0` silences the Czech-text warning; a file can also opt out with `lang: cs` in its front matter |
| `CC_GUARD_COMMIT_TYPES` | see above | allowed commit types in the default regex |
| `CC_GUARD_MAX_SUBJECT` | `72` | subject length limit |

Example: enforce the conventional format everywhere except work repos.

```ini
# ~/.gitconfig
[cc-guard]
    format = true
[includeIf "gitdir/i:~/Development/work/"]
    path = ~/.gitconfig-work

# ~/.gitconfig-work
[cc-guard]
    commitFormat = false
```

## What it does not do

- It does not read or send anything anywhere. No network, no telemetry, no model calls.
- It does not scan your whole history; run `gitleaks git` yourself for that.
- It does not replace a linter or a test suite. The `any`, emoji and TODO checks are
  narrow on purpose, and anything a project's eslint/biome config already enforces
  belongs there.
- It cannot stop a repo that overrides `core.hooksPath` (husky, lefthook) from
  skipping the git-level hooks. The Claude-side hooks still run.

## How it is built

```
plugins/cc-guard/
  hooks/hooks.json          registers the four hooks
  scripts/commit-guard.sh   PreToolUse Bash
  scripts/post-edit.sh      PostToolUse Edit|Write|MultiEdit
  scripts/agent-evidence-pre.sh / -post.sh   PreToolUse / PostToolUse Agent
  scripts/lib.sh            stdin parsing, output helpers, agent capability lookup
  rules/                    ast-grep rules with test fixtures (ast-grep test -c rules/sgconfig.yml)
  git-hooks/                pre-commit, commit-msg (POSIX sh, self-contained)
  gitleaks.toml             pinned rule set
```

Every script reads the hook JSON from stdin, decides, and prints at most one JSON
document. Nothing is `eval`ed; commit commands are tokenised with `xargs`, which
echoes and never executes. Fixtures for every rule are documented in
[`plugins/cc-guard/README.md`](plugins/cc-guard/README.md).

## License

MIT
