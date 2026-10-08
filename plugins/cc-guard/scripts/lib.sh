#!/usr/bin/env bash
# Shared helpers for cc-guard hook scripts. Source, do not execute.
# Every hook: read_input; decide; emit one JSON document or nothing; exit 0.
# Exit 2 is reserved for "stderr is the message" blocking (PostToolUse).

read_input() {
  HOOK_INPUT=$(cat)
  TOOL_NAME=$(field '.tool_name')
  CWD=$(field '.cwd')
  SESSION_ID=$(field '.session_id')
  export HOOK_INPUT TOOL_NAME CWD SESSION_ID
}

# field '.tool_input.command' -> raw string, empty when null
field() {
  printf '%s' "$HOOK_INPUT" | jq -r "$1 // empty"
}

has_cmd() { command -v "$1" >/dev/null 2>&1; }

# skipped commit|edit|agent -> true when listed in CC_GUARD_SKIP (comma list)
skipped() {
  case ",${CC_GUARD_SKIP:-}," in *",$1,"*) return 0 ;; esac
  return 1
}

# Pictographic emoji. Deliberately excludes text symbols such as check marks (U+2713),
# arrows (U+2190-21FF), (TM)/(C), box drawing. Keep in sync with git-hooks/commit-msg.
EMOJI_RE='[\x{1F000}-\x{1FAFF}\x{2B00}-\x{2BFF}\x{2300}-\x{23FF}\x{2600}-\x{2604}\x{260E}\x{2614}\x{2615}\x{2648}-\x{2653}\x{2660}-\x{2667}\x{267B}\x{26A0}-\x{26FF}\x{2700}-\x{2705}\x{2708}-\x{270D}\x{2728}\x{2733}\x{2734}\x{2744}\x{2747}\x{274C}\x{274E}\x{2753}-\x{2757}\x{2763}\x{2764}\x{2795}-\x{2797}\x{27A1}\x{27B0}\x{27BF}\x{FE0F}]'
# has_emoji <file-or-stdin>: prints "line: text" of the first hit, empty when clean
has_emoji() { perl -CSD -ne 'print "$.: $_" and exit if /'"$EMOJI_RE"'/' "$@" | cut -c1-120; }

json_str() { jq -Rn --arg s "$1" '$s'; }

# PreToolUse: refuse the call, reason shown to Claude.
out_deny() {
  jq -cn --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
}

# PreToolUse: replace tool input (whole object) without touching permission flow.
out_updated_input() {
  jq -cn --argjson i "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",updatedInput:$i}}'
}

# PostToolUse: tool already ran; reason goes back to Claude as a blocking error.
out_block() {
  jq -cn --arg r "$1" '{decision:"block",reason:$r}'
}

# Any event: non-blocking note injected next to the tool result.
out_warn() {
  jq -cn --arg e "$2" --arg c "$1" '{hookSpecificOutput:{hookEventName:$e,additionalContext:$c}}'
}

# agent_is_readonly <subagent_type>: 0 when the agent cannot run Bash or edit files.
# Looks up the agent file (project, then user); frontmatter `tools:` without any of
# Bash/Edit/Write/MultiEdit/NotebookEdit = read-only. Missing `tools:` = full access.
# Built-ins: Explore and Plan are read-only; general-purpose and unknown are not.
agent_is_readonly() {
  local t=$1 f fm
  case "$t" in Explore|Plan|explorer) return 0 ;; general-purpose|"") return 1 ;; esac
  t=${t##*:}   # plugin-scoped name
  for f in "${CLAUDE_PROJECT_DIR:-$PWD}/.claude/agents/$t.md" "$HOME/.claude/agents/$t.md"; do
    [ -f "$f" ] || continue
    fm=$(awk 'NR==1 && $0!="---" {exit} NR>1 && $0=="---" {exit} NR>1 {print}' "$f")
    printf '%s\n' "$fm" | grep -q '^tools:' || return 1
    printf '%s\n' "$fm" | grep -E '^tools:' | grep -Eq '\b(Bash|Edit|Write|MultiEdit|NotebookEdit)\b' && return 1
    return 0
  done
  return 1
}
