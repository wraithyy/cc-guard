#!/usr/bin/env bash
# PostToolUse Edit|Write|MultiEdit: format, then block on TS `any` without reason,
# bare @ts-ignore, emoji in code; warn on console.log, TODO/FIXME, eslint-disable
# without reason, Czech text in files, shellcheck findings.
# Env: CC_GUARD_SKIP=edit  CC_GUARD_LANG_WARN=0
# Formatting runs repo-local biome/prettier (code from node_modules), so it is opt-in:
#   git config cc-guard.format true   (globally or per includeIf dir) or CC_GUARD_FORMAT=1
set -uo pipefail
shopt -s extglob
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
read_input
skipped edit && exit 0
file=$(field '.tool_input.file_path')
[ -n "$file" ] && [ -f "$file" ] || exit 0
# only files inside the project; never echo lines from elsewhere (dotfiles, key material)
proj=$(cd "${CLAUDE_PROJECT_DIR:-$CWD}" 2>/dev/null && pwd -P) || exit 0
real=$(cd "$(dirname "$file")" && pwd -P)/$(basename "$file")
case "$real" in "$proj"/*) ;; *) exit 0 ;; esac
case "$real" in *.env|*.env.*|*/.ssh/*|*/.aws/*|*.pem|*.key|*id_rsa*|*id_ed25519*|*.p12|*.pfx) exit 0 ;; esac
ext="${file##*.}"; [ "$ext" = "$file" ] && ext=""
base=$(basename "$file")
case "$ext" in
  ts|tsx|js|jsx|mjs|cjs|vue|svelte|py|go|rs|rb|php|java|kt|swift|c|h|cpp|hpp|cs|css|scss|less|html|yml|yaml|toml|md|mdx|txt) ;;
  sh|bash|zsh) ;;
  *) case "$base" in *.sh|Dockerfile|Makefile) ;; *) exit 0 ;; esac ;;
esac
blocks=(); warns=()
add_block() { blocks+=("$1"); }
add_warn() { warns+=("$1"); }
lines_of() { grep -nE "$1" "$file" | head -"${2:-5}" | cut -c1-140; }

# --- 1. format (same detection as the old fe-post-edit, extended) -------------
format_on=${CC_GUARD_FORMAT:-$(git -C "$proj" config --bool cc-guard.format 2>/dev/null || echo false)}
if [ "$format_on" = true ] || [ "$format_on" = 1 ]; then
  case "$ext" in
    ts|tsx|js|jsx|mjs|cjs|vue|svelte|css|scss|less|html|json|md|mdx|yml|yaml)
      dir=$(dirname "$file"); root=""
      while [ "$dir" != "/" ]; do [ -f "$dir/package.json" ] && { root="$dir"; break; }; dir=$(dirname "$dir"); done
      if [ -n "$root" ]; then
        if [ -f "$root/biome.json" ] || [ -f "$root/biome.jsonc" ]; then
          (cd "$root" && npx --no-install biome check --write -- "$file" >/dev/null 2>&1) || true
        elif ls "$root"/.prettierrc "$root"/.prettierrc.* "$root"/prettier.config.* >/dev/null 2>&1 || grep -q '"prettier"' "$root/package.json" 2>/dev/null; then
          (cd "$root" && npx --no-install prettier --write -- "$file" >/dev/null 2>&1) || true
        fi
      fi ;;
  esac
fi

# --- 2. ast-grep: any without reason, bare ts-ignore (block) -----------------
case "$ext" in ts|tsx)
  if has_cmd ast-grep; then
    rules="$(dirname "$0")/../rules/sgconfig.yml"
    while IFS=$'\t' read -r rule line col; do
      [ -z "$rule" ] && continue
      n=$((line + 1))
      if [ "$rule" = no-explicit-any ]; then
        # justified by a comment after the `any` on the same line, or a comment line above
        prev=$([ "$n" -gt 1 ] && sed -n "$((n-1))p" "$file" || true)
        rest=$(sed -n "${n}p" "$file" | cut -c"$((col + 1))-")
        # a comment starts after whitespace; `https://` inside a string does not count
        case "$rest" in *[[:space:]]//*|*[[:space:]]/\**) continue ;; esac
        case "$prev" in *([[:space:]])//*|*([[:space:]])/\**|*([[:space:]])\**) continue ;; esac
        add_block "$file:$n: explicit \`any\` without a justifying comment (same or previous line)"
      else
        add_block "$file:$n: @ts-ignore/@ts-expect-error without a reason"
      fi
    done < <(ast-grep scan -c "$rules" --json "$file" 2>/dev/null | jq -r '.[] | [.ruleId, .range.start.line, .range.start.column] | @tsv')
  fi ;;
esac

# --- 3. emoji in code (block); md/txt exempt ---------------------------------
case "$ext" in md|mdx|txt) ;; *)
  hit=$(has_emoji "$file")
  [ -n "$hit" ] && add_block "$file:$hit  <- emoji in code/comments is not allowed" ;;
esac

# --- 4. warnings ---------------------------------------------------------------
case "$ext" in ts|tsx|js|jsx|mjs|cjs|vue|svelte)
  case "$base" in *.test.*|*.spec.*|*.stories.*) ;; *)
    h=$(lines_of 'console\.(log|debug)\(' 3); [ -n "$h" ] && add_warn "console.log left in $file:
$h" ;;
  esac
  h=$(lines_of 'eslint-disable(-next-line|-line)?([[:space:]]+[a-z@/,-]+)?[[:space:]]*$' 3); [ -n "$h" ] && add_warn "eslint-disable without a reason (add -- why) in $file:
$h" ;;
esac
h=$(lines_of '\b(TODO|FIXME|XXX)\b' 3); [ -n "$h" ] && add_warn "TODO/FIXME in $file:
$h"
if [ "${CC_GUARD_LANG_WARN:-1}" != 0 ]; then
  case "$file" in */skills/*|*/notes/*|*/Notes/*|*/memory/*) ;; *)
    if ! head -5 "$file" | grep -q '^lang: cs'; then
      c=$(grep -c '[ěščřžýáíéúůďťňĚŠČŘŽÝÁÍÉÚŮĎŤŇ]' "$file" || true)
      [ "$c" -ge 3 ] && add_warn "$file has $c lines with Czech diacritics; files are English-only (set CC_GUARD_LANG_WARN=0 or 'lang: cs' front matter to silence)"
    fi ;;
  esac
fi
case "$ext:$base" in sh:*|bash:*|zsh:*|*:*.sh)
  if has_cmd shellcheck; then
    h=$(shellcheck -f gcc -S warning "$file" 2>/dev/null | head -5 | cut -c1-140)
    [ -n "$h" ] && add_warn "shellcheck:
$h"
  fi ;;
esac

# --- 5. emit -------------------------------------------------------------------
join() { local IFS=$'\n'; printf '%s' "$*"; }
if [ ${#blocks[@]} -gt 0 ]; then
  msg="cc-guard blocked the edit result; fix before continuing:
$(join "${blocks[@]}")"
  [ ${#warns[@]} -gt 0 ] && msg="$msg

also:
$(join "${warns[@]}")"
  out_block "$msg"
elif [ ${#warns[@]} -gt 0 ]; then
  out_warn "cc-guard:
$(join "${warns[@]}")" PostToolUse
fi
exit 0
