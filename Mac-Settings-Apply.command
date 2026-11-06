#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
/usr/bin/python3 "$ROOT/.config/dotfiles/scripts/macos-personal.py" apply
