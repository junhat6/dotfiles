#!/bin/bash
set -euo pipefail
ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
for file in "$ROOT/.zshrc" "$ROOT/.zprofile" "$ROOT"/.config/zsh/*.zsh; do zsh -n "$file"; done
for file in "$ROOT/.config/dotfiles/install.sh" "$ROOT"/.config/dotfiles/scripts/*.sh "$ROOT"/.claude/hooks/*.sh "$ROOT/.claude/statusline-command.sh" "$ROOT/.config/yadm/bootstrap" "$ROOT/.local/bin/dotfiles" "$ROOT"/.config/dotfiles/git-hooks/*; do bash -n "$file"; done
git config --file "$ROOT/.gitconfig" --list >/dev/null
if [[ -x /usr/bin/python3 ]]; then PYTHON=/usr/bin/python3; else PYTHON=python3; fi
"$PYTHON" "$ROOT/.config/dotfiles/scripts/dotfiles.py" --root "$ROOT" check --source
"$PYTHON" -m unittest discover -s "$ROOT/.config/dotfiles/tests" -v
