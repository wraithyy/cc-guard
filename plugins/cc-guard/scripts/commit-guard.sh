#!/usr/bin/env bash
# PreToolUse Bash hook for `git commit`: gitleaks on the diff being committed + message checks.
# Config (git config, repo or includeIf scoped; env wins when set):
#   cc-guard.secrets       bool   default true   run gitleaks
#   cc-guard.commitFormat  bool   default true   enforce subject format + no emoji
#   cc-guard.subjectRegex  str    override subject ERE
#   CC_GUARD_SKIP=commit   skip this hook entirely
set -uo pipefail
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
plugin_root=$(cd "$(dirname "$0")/.." && pwd)
read_input
skipped commit && exit 0
[ "$TOOL_NAME" = "Bash" ] || exit 0
cmd=$(field '.tool_input.command')
# `git commit`, `git -c k=v commit`, `git -C dir commit`, tabs, chained after && ; not `gitx commit`
printf '%s' "$cmd" | grep -Eq '(^|[^[:alnum:]_./-])git[[:space:]]+([^[:space:]]+[[:space:]]+){0,6}commit([[:space:]]|$)' || exit 0
if [ -d "$CWD" ]; then cd "$CWD" || exit 0; fi

cfg() { local v; v=$(git config --get "cc-guard.$1" 2>/dev/null || true); printf '%s' "${v:-$2}"; }
DEFAULT_TYPES="feat|fix|refactor|docs|test|chore|perf|ci|build|style|revert"
subject_re=$(cfg subjectRegex "^(${CC_GUARD_COMMIT_TYPES:-$DEFAULT_TYPES})(\([a-z0-9/._-]+\))?!?: .{1,${CC_GUARD_MAX_SUBJECT:-72}}$")

# --- tokenise the `git ... commit ...` part; xargs only echoes, never executes --
# Everything up to a heredoc marker, from the first `git` token. Newlines inside quotes
# become \001 so xargs accepts them. Each `&&`/`;`/`||` segment is parsed separately.
head=$(printf '%s\n' "$cmd" | awk '/<</{print; exit} {print}')
head="git${head#*git}"
all=0; noverify=0; parse_fail=0; msgs=(); ffiles=(); reuses=()
toks=$(printf '%s' "$head" | tr '\n' '\001' | xargs -n1 printf '%s\n' 2>/dev/null) || parse_fail=1
seen_commit=0; want=""; msg=""; reuse=0; ffile=""
flush() { [ $seen_commit -eq 1 ] && { msgs+=("$(printf '%s' "$msg" | tr '\001' '\n')"); ffiles+=("$ffile"); reuses+=("$reuse"); }; seen_commit=0; want=""; msg=""; reuse=0; ffile=""; }
while IFS= read -r tok; do
  case "$tok" in '&&'|';'|'||'|'|') flush; continue ;; esac
  if [ $seen_commit -eq 0 ]; then [ "$tok" = commit ] && seen_commit=1; continue; fi
  if [ -n "$want" ]; then
    case "$want" in m) msg="${msg:+$msg

}$tok" ;; F) ffile="$tok" ;; esac; want=""; continue
  fi
  case "$tok" in
    -m|--message) want=m ;;
    --message=*) msg="${msg:+$msg

}${tok#--message=}" ;;
    -F|--file) want=F ;;
    --file=*) ffile="${tok#--file=}" ;;
    --all) all=1 ;;
    --no-verify) noverify=1 ;;
    --amend|--fixup=*|--squash=*|--reuse-message=*|--reedit-message=*|-C|-c) reuse=1 ;;
    --*) ;;
    -[a-zA-Z]*)
      f="${tok#-}"
      case "$f" in *a*) all=1 ;; esac
      case "$f" in *n*) noverify=1 ;; esac
      case "$f" in *m*) [ "${f##*m}" = "" ] && want=m || msg="${msg:+$msg

}${f#*m}" ;; esac
      case "$f" in *F*) [ "${f##*F}" = "" ] && want=F || ffile="${f#*F}" ;; esac ;;
  esac
done <<< "$toks"
flush
[ ${#msgs[@]} -gt 0 ] || [ $parse_fail -eq 1 ] || exit 0
[ $noverify -eq 1 ] && { out_deny "cc-guard: --no-verify/-n bypasses the git hooks; commit without it."; exit 0; }

# --- secrets -----------------------------------------------------------------
if [ "$(cfg secrets true)" != "false" ]; then
  has_cmd gitleaks || { out_deny "cc-guard: gitleaks not installed; secret scan cannot run. brew install gitleaks (or set git config cc-guard.secrets false)"; exit 0; }
  unset GITLEAKS_CONFIG GITLEAKS_CONFIG_TOML
  gl=(env NO_COLOR=1 gitleaks --no-banner --no-color --redact -v -c "$plugin_root/gitleaks.toml")
  if [ $all -eq 1 ] || printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+add([[:space:]]|$)'; then
    out=$({ git diff HEAD; git ls-files --others --exclude-standard -z | xargs -0 cat 2>/dev/null; } | "${gl[@]}" stdin 2>&1); rc=$?
  else
    out=$("${gl[@]}" git --staged 2>&1); rc=$?
  fi
  case $rc in
    0) ;;
    1) out_deny "cc-guard: gitleaks found secrets in the commit. Remove them (or add # gitleaks:allow for fixtures):
$(printf '%s\n' "$out" | grep -E '^(Finding|RuleID|File|Line):' | head -10)"; exit 0 ;;
    *) out_deny "cc-guard: gitleaks failed (rc=$rc), refusing to commit unscanned:
$(printf '%s\n' "$out" | tail -3)"; exit 0 ;;
  esac
fi

# --- message -----------------------------------------------------------------
[ "$(cfg commitFormat true)" = "false" ] && exit 0
[ $parse_fail -eq 1 ] && { out_warn "cc-guard: could not parse the commit command (unbalanced quotes?); message checks left to the git commit-msg hook" PreToolUse; exit 0; }

check_msg() { # check_msg <msg> <ffile> <reuse>
  local msg=$1 ffile=$2 from_file=0 abs subject hit shown
  [ "$3" = 1 ] && return 0
  if [ -n "$ffile" ] && [ "$ffile" != "-" ]; then
    # only read message files that live inside the repo; never echo their content
    abs=$(cd "$(dirname "$ffile")" 2>/dev/null && pwd -P)/$(basename "$ffile")
    case "$abs" in "$(pwd -P)"/*) [ -f "$abs" ] && { msg=$(cat "$abs"); from_file=1; } ;; esac
  fi
  if [ "$ffile" = "-" ] && printf '%s' "$cmd" | grep -q '<<'; then
    local term; term=$(printf '%s' "$cmd" | sed -nE "s/.*<<-?[[:space:]]*['\"]?([A-Za-z_]+)['\"]?.*/\1/p" | head -1)
    msg=$(printf '%s\n' "$cmd" | awk -v t="$term" 'f && $0==t {exit} f {print} /<</ {f=1}')
  fi
  [ -z "$msg" ] && return 0   # editor-driven commit: the git commit-msg hook covers it
  subject=$(printf '%s\n' "$msg" | grep -iv '^co-authored-by:' | grep -m1 -v '^[[:space:]]*$')
  case "$subject" in "fixup! "*|"squash! "*|"Merge "*|"Revert \""*) return 0 ;; esac
  if ! printf '%s' "$subject" | grep -Eq -e "$subject_re"; then
    shown=$([ "$from_file" = 1 ] && echo "(first line of $ffile)" || printf '%s' "${subject:0:80}")
    out_deny "cc-guard: commit subject must match '$subject_re' (got: '$shown'). Use <type>: <description>, max 72 chars."; return 1
  fi
  hit=$(printf '%s\n' "$msg" | has_emoji)
  [ -n "$hit" ] && { out_deny "cc-guard: no emoji in commit messages (line $hit)"; return 1; }
  return 0
}
for i in "${!msgs[@]}"; do check_msg "${msgs[$i]}" "${ffiles[$i]}" "${reuses[$i]}" || exit 0; done
exit 0
