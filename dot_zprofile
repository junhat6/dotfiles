#!/bin/zsh
# Login シェルで最初に読み込む環境設定（PATH など）

# Locale
export LANG=ja_JP.UTF-8

# Homebrew
# shellenv で PATH/MANPATH などをまとめて設定
eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || brew shellenv)"

# mise 管理のツールをログインシェルでも優先する（非対話のエージェント実行を含む）
eval "$(mise activate zsh --shims)"

# ユーザーローカル
export PATH="$HOME/.local/bin:$PATH"

# zsh を明示（ログインシェルが変わる環境向け）
if [ -x /bin/zsh ]; then
  export SHELL=/bin/zsh
fi

# android studio 
export ANDROID_HOME=$HOME/Library/Android/sdk
export PATH=$PATH:$ANDROID_HOME/emulator
export PATH=$PATH:$ANDROID_HOME/platform-tools