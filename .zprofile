#!/bin/zsh
# Login シェルで最初に読み込む環境設定（PATH など）

# Locale
export LANG=ja_JP.UTF-8

# Homebrew
# shellenv で PATH/MANPATH などをまとめて設定
eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || brew shellenv)"

# ユーザーローカル
export PATH="$HOME/.local/bin:$PATH"

# zsh を明示（ログインシェルが変わる環境向け）
if [ -x /bin/zsh ]; then
  export SHELL=/bin/zsh
fi

