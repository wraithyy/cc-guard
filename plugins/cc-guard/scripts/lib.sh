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
