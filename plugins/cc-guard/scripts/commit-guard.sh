#!/usr/bin/env bash
# PreToolUse Bash hook for `git commit`: gitleaks on staged diff + commit message checks.
# Config (git config, repo or includeIf scoped; env wins when set):
#   cc-guard.secrets       bool   default true   run gitleaks
#   cc-guard.commitFormat  bool   default true   enforce subject format + no emoji
#   cc-guard.subjectRegex  str    override subject regex
#   CC_GUARD_SKIP=commit   skip this hook entirely
set -uo pipefail
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
read_input
skipped commit && exit 0
[ "$TOOL_NAME" = "Bash" ] || exit 0
cmd=$(field '.tool_input.command')
case "$cmd" in *"git commit"*|*"git "*" commit"*) ;; *) exit 0 ;; esac
if [ -d "$CWD" ]; then cd "$CWD" || exit 0; fi

cfg() { # cfg <key> <default>
  local v; v=$(git config --get "cc-guard.$1" 2>/dev/null || true); printf '%s' "${v:-$2}"
}
DEFAULT_TYPES="feat|fix|refactor|docs|test|chore|perf|ci|build|style|revert"
subject_re=$(cfg subjectRegex "^(${CC_GUARD_COMMIT_TYPES:-$DEFAULT_TYPES})(\([a-z0-9/._-]+\))?!?: .{1,${CC_GUARD_MAX_SUBJECT:-72}}$")

# --- secrets -----------------------------------------------------------------
if [ "$(cfg secrets true)" != "false" ]; then
  has_cmd gitleaks || { out_deny "cc-guard: gitleaks not installed; secret scan cannot run. brew install gitleaks (or set git config cc-guard.secrets false)"; exit 0; }
  case "$cmd" in
    *" -a "*|*" -a"|*" --all"*|*" -am"*) leaks=$(git diff HEAD | NO_COLOR=1 gitleaks stdin --no-banner --no-color --redact -v 2>&1 | grep -E '^(Finding|Secret|RuleID|File|Line):' | head -10) ;;
    *) leaks=$(NO_COLOR=1 gitleaks git --staged --no-banner --no-color --redact -v 2>&1 | grep -E '^(Finding|Secret|RuleID|File|Line):' | head -10) ;;
  esac
  if [ -n "$leaks" ]; then out_deny "cc-guard: gitleaks found secrets in the commit. Remove them (or add # gitleaks:allow for fixtures):
$leaks"; exit 0; fi
fi

# --- message -----------------------------------------------------------------
[ "$(cfg commitFormat true)" = "false" ] && exit 0
case "$cmd" in *--amend*|*" -C "*|*" -c "*|*--reuse-message*|*--fixup*|*--squash*) exit 0 ;; esac

msg=""
if printf '%s' "$cmd" | grep -q '<<'; then
  # heredoc: body between the line with << and the terminator word
  term=$(printf '%s' "$cmd" | sed -nE "s/.*<<-?[[:space:]]*['\"]?([A-Za-z_]+)['\"]?.*/\1/p" | head -1)
  msg=$(printf '%s\n' "$cmd" | awk -v t="$term" 'f && $0==t {exit} f {print} /<</ {f=1}')
else
  first=$(printf '%s' "$cmd" | sed -n '/git commit/{p;q;}')
  # xargs tokenises shell quotes without executing anything
  while IFS= read -r tok; do
    if [ -n "${want:-}" ]; then
      case "$want" in m) msg="${msg:+$msg

}$tok" ;; F) [ -f "$tok" ] && msg=$(cat "$tok") ;; esac; want=""; continue
    fi
    case "$tok" in
      -m|--message) want=m ;;
      -m?*) msg="${msg:+$msg

}${tok#-m}" ;;
      --message=*) msg="${msg:+$msg

}${tok#--message=}" ;;
      -F|--file) want=F ;;
      --file=*) [ -f "${tok#--file=}" ] && msg=$(cat "${tok#--file=}") ;;
    esac
  done < <(printf '%s' "$first" | xargs -n1 2>/dev/null || true)
fi
[ -z "$msg" ] && exit 0   # editor-driven commit: nothing to check here, git commit-msg hook covers it

subject=$(printf '%s\n' "$msg" | grep -v '^Co-Authored-By:' | grep -m1 -v '^[[:space:]]*$')
case "$subject" in "fixup! "*|"squash! "*|"Merge "*|"Revert \""*) exit 0 ;; esac
if ! printf '%s' "$subject" | grep -Eq "$subject_re"; then
  out_deny "cc-guard: commit subject must match '$subject_re' (got: '$subject'). Use <type>: <description>, max 72 chars."; exit 0
fi
if printf '%s' "$msg" | perl -CSD -ne 'exit 1 if /[\x{1F000}-\x{1FAFF}\x{2600}-\x{27BF}\x{FE0F}]/' ; then :; else
  out_deny "cc-guard: no emoji in commit messages."; exit 0
fi
exit 0
