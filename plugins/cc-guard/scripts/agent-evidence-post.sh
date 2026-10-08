#!/usr/bin/env bash
# PostToolUse Agent: warn when a report from a command-capable agent has no VERIFICATION
# block, or claims success with red-flag phrases and no exit code nearby.
set -uo pipefail
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
read_input
skipped agent && exit 0
[ "$TOOL_NAME" = "Agent" ] || exit 0
type=$(field '.tool_input.subagent_type')
agent_is_readonly "$type" && exit 0
# tool_response may be a string, an array of content blocks, or an object: take all strings
text=$(printf '%s' "$HOOK_INPUT" | jq -r '.tool_response | if type=="string" then . else [.. | strings] | join("\n") end')
[ -z "$text" ] && exit 0
warn=""
if ! printf '%s' "$text" | grep -qi 'VERIFICATION'; then
  warn="report from $type has no VERIFICATION block: treat its claims as UNVERIFIED and re-run the critical check in the main session."
fi
flags=$(printf '%s\n' "$text" | grep -niE 'should (now )?(work|pass)|vše ověřeno|all tests pass(ed)?|tests? (are )?(now )?green' | head -3 | cut -c1-100)
if [ -n "$flags" ]; then
  # a red flag is fine when an exit code is quoted within 5 lines of it
  while IFS= read -r line; do
    n=${line%%:*}; lo=$((n>5?n-5:1)); hi=$((n+5))
    printf '%s\n' "$text" | sed -n "${lo},${hi}p" | grep -Eqi 'exit( code)?[ =:]+[0-9]+|rc=[0-9]+' || warn="${warn:+$warn
}red-flag phrase without an exit code nearby: \"${line#*:}\""
  done <<< "$flags"
fi
[ -n "$warn" ] && out_warn "cc-guard evidence check ($type):
$warn" PostToolUse
exit 0
