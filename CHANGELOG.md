# Changelog

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
