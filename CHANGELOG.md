# Changelog

## 0.3.1 - 2026-10-08
- post-edit: formatting is opt-in (`git config cc-guard.format true` / `CC_GUARD_FORMAT=1`) because it runs repo-local biome/prettier; only files inside the project are inspected, key-like paths skipped; `any` justification counts only comments after the match or a comment line above
- agent_is_readonly: user agent file wins over a repo-supplied one, YAML-list `tools:` parsed, CRLF tolerated
- hooks read stdin via a temp file (multi-MB tool responses no longer hit ARG_MAX)
- emoji set narrowed further (keyboard glyphs, most arrows allowed; stars/hourglass still blocked)

## 0.3.0 - 2026-10-08
- agent-evidence-pre: append VERIFICATION contract to command-capable subagent prompts (PreToolUse Agent, updatedInput)
- agent-evidence-post: warn on reports without VERIFICATION or with unbacked success phrases (PostToolUse Agent)

## 0.2.0 - 2026-10-08
- post-edit: format, block TS `any` w/o reason, bare ts-ignore, emoji; warn console.log, TODO, eslint-disable, Czech text, shellcheck (PostToolUse Edit|Write|MultiEdit)
- ast-grep rules with test fixtures (rules/)
- commit-guard: pinned gitleaks config, fail closed on gitleaks error, scan untracked with -a / git add, parse chained and multi-line commands, refuse --no-verify, -F only inside repo
- git hooks: mktemp, worktree-safe chaining (git-common-dir), case-insensitive trailer strip
- narrowed emoji range (check marks, arrows, TM allowed)

## 0.1.0 - 2026-10-08
- commit-guard: gitleaks on staged diff, conventional subject, no emoji (PreToolUse Bash)
- git hooks: pre-commit (gitleaks), commit-msg (format, emoji, strip Claude trailer), chaining
- install-git-hooks.sh --global / --repo
