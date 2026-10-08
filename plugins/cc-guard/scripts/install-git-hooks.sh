#!/bin/sh
# Install cc-guard git hooks.
#   --global  copy to ~/.config/git/hooks and set core.hooksPath (chains to repo hooks)
#   --repo    copy into the current repo's .git/hooks; with husky/lefthook present, print the snippet instead
set -eu
src=$(cd "$(dirname "$0")/../git-hooks" && pwd)
case "${1:-}" in
  --global)
    dst="${XDG_CONFIG_HOME:-$HOME/.config}/git/hooks"
    mkdir -p "$dst"
    cp "$src/pre-commit" "$src/commit-msg" "$dst/"
    chmod +x "$dst/pre-commit" "$dst/commit-msg"
    git config --global core.hooksPath "$dst"
    echo "cc-guard: installed to $dst, core.hooksPath set" ;;
  --repo)
    root=$(git rev-parse --show-toplevel)
    if [ -d "$root/.husky" ] || [ -f "$root/lefthook.yml" ] || [ -f "$root/.lefthook.yml" ]; then
      cat <<SNIP
cc-guard: this repo manages hooks itself. Add these lines:

  .husky/pre-commit:   $src/pre-commit "\$@"
  .husky/commit-msg:   $src/commit-msg "\$@"

  lefthook.yml:
    pre-commit: { commands: { cc-guard: { run: $src/pre-commit } } }
    commit-msg: { commands: { cc-guard: { run: $src/commit-msg {1} } } }
SNIP
      exit 0
    fi
    hooks=$(git rev-parse --git-path hooks)
    mkdir -p "$hooks"
    cp "$src/pre-commit" "$src/commit-msg" "$hooks/"
    chmod +x "$hooks/pre-commit" "$hooks/commit-msg"
    echo "cc-guard: installed to $hooks" ;;
  *) echo "usage: install-git-hooks.sh --global | --repo" >&2; exit 2 ;;
esac
