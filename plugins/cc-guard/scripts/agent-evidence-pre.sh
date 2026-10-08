#!/usr/bin/env bash
# PreToolUse Agent: append the canonical VERIFICATION contract to prompts for agents
# that can run commands or edit files. Read-only agents are left untouched.
set -uo pipefail
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
read_input
skipped agent && exit 0
[ "$TOOL_NAME" = "Agent" ] || exit 0
type=$(field '.tool_input.subagent_type')
agent_is_readonly "$type" && exit 0
prompt=$(field '.tool_input.prompt')
printf '%s' "$prompt" | grep -qi 'VERIFICATION' && exit 0
block=$(cat "$(dirname "$0")/evidence-block.txt")
printf '%s' "$HOOK_INPUT" | jq -c --arg b "$block" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",updatedInput:(.tool_input + {prompt:(.tool_input.prompt + $b)})}}'
