# cc-guard

Deterministic guard hooks for Claude Code. Prose rules in CLAUDE.md are advisory;
these hooks make the ones that matter fail for real.

## Hooks

| Event | Script | Does |
|---|---|---|
| PreToolUse Bash (`git commit`) | `scripts/commit-guard.sh` | gitleaks on the staged diff (or `git diff HEAD` with `-a`), conventional subject `type(scope): desc` max 72 chars, no emoji. Denies the call with the reason. |

## Git hooks (outside Claude)

`git-hooks/pre-commit` (gitleaks) and `git-hooks/commit-msg` (format, emoji, strips
`Co-Authored-By: Claude*` trailers). Both chain to the repo's own `.git/hooks/<name>`.

```sh
scripts/install-git-hooks.sh --global   # ~/.config/git/hooks + core.hooksPath
scripts/install-git-hooks.sh --repo     # into .git/hooks, or prints husky/lefthook snippet
```

## Config

Per repo or per directory via git config (`includeIf` friendly). Env `CC_GUARD_*` overrides.

| Key | Default | Effect |
|---|---|---|
| `cc-guard.secrets` | `true` | run gitleaks; missing binary is a hard deny |
| `cc-guard.commitFormat` | `true` | enforce subject format and no emoji |
| `cc-guard.subjectRegex` | conventional | ERE for the subject line, e.g. `^[A-Z]+-[0-9]+ ` for Jira keys |
| `CC_GUARD_SKIP` | | comma list: `commit` disables the Claude-side hook |
| `CC_GUARD_COMMIT_TYPES` | `feat\|fix\|...` | allowed types in the default regex |
| `CC_GUARD_MAX_SUBJECT` | `72` | subject length limit |

## Add to a project

1. `.claude/settings.json`:
   ```json
   {
     "extraKnownMarketplaces": { "cc-guard": { "source": { "source": "github", "repo": "wraithyy/cc-guard" } } },
     "enabledPlugins": { "cc-guard@cc-guard": true }
   }
   ```
   Teammates get prompted to install the plugin when they open the repo.
2. Binaries: `brew install gitleaks` (macOS) or `apt install gitleaks` / release binary.
3. Git-level hooks (optional, catches commits made outside Claude): `scripts/install-git-hooks.sh --repo`.

Requires `jq` and `perl` (both present on macOS and most Linux images).
