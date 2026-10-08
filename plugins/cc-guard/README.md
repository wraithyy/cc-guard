# cc-guard

Deterministic guard hooks for Claude Code. Prose rules in CLAUDE.md are advisory;
these hooks make the ones that matter fail for real.

## Hooks

| Event | Script | Does |
|---|---|---|
| PreToolUse Bash (`git commit`) | `scripts/commit-guard.sh` | gitleaks on the staged diff (working tree + untracked with `-a` or a preceding `git add`), pinned default rules (a repo `.gitleaks.toml` is ignored), conventional subject `type(scope): desc` max 72 chars, no emoji, `--no-verify` refused. Denies the call with the reason. Unparseable commands (unbalanced quotes) fall through to the git `commit-msg` hook. |
| PostToolUse Edit/Write/MultiEdit | `scripts/post-edit.sh` | formats with biome/prettier when the project has them, then **blocks** on TS `any` without a comment on the same or previous line, bare `@ts-ignore`/`@ts-expect-error`, emoji in code; **warns** on `console.log`, `TODO`/`FIXME`, `eslint-disable` without a reason, Czech text in files, shellcheck findings in `.sh`. |

ast-grep rules live in `rules/` (`ast-grep test -c rules/sgconfig.yml`). Emoji means pictographic
blocks only; check marks, arrows, (TM) and box drawing are allowed.

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
| `CC_GUARD_SKIP` | | comma list of hooks to disable: `commit`, `edit`, `agent` |
| `CC_GUARD_LANG_WARN` | `1` | `0` silences the Czech-text warning; or put `lang: cs` in the file's front matter |
| `CC_GUARD_NO_FORMAT` | `0` | `1` skips biome/prettier |
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
2. Binaries: `brew install gitleaks ast-grep shellcheck` (macOS) or the Linux equivalents. gitleaks missing = commits denied; ast-grep/shellcheck missing = those checks silently skipped.
3. Git-level hooks (optional, catches commits made outside Claude): `scripts/install-git-hooks.sh --repo`.

Requires `jq`, `perl` and bash 3.2+ (both present on macOS and most Linux images).
