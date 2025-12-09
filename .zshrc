export LANG=ja_JP.UTF-8

# === 補完システム ===
autoload -Uz compinit
compinit

# 大文字小文字を区別しない補完
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'

# 補完メニューを選択式に
zstyle ':completion:*' menu select

# === 履歴設定 ===
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt SHARE_HISTORY
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_ALL_DUPS    # 追加する際に過去の重複を消す
setopt HIST_FIND_NO_DUPS       # 検索結果で重複を表示しない
setopt HIST_IGNORE_SPACE

# === fzf - あいまい検索 ===
eval "$(fzf --zsh)"

# fzf 設定
export FZF_DEFAULT_OPTS="--height 40% --layout=reverse --border --inline-info"
export FZF_DEFAULT_COMMAND='rg --files --hidden --follow --glob "!.git/*"'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"

# === zoxide - スマート cd ===
eval "$(zoxide init zsh)"

# Ctrl-Q で zoxide 一覧からディレクトリ移動
fzf-cd-widget() {
  local dir
  dir=$(zoxide query -l |
    fzf --ansi --reverse \
        --preview 'eza -lah --icons --git {} 2>/dev/null || ls -la {}' \
        --preview-window=right:60%) || return
  cd "$dir"
  zle reset-prompt
}
zle -N fzf-cd-widget
bindkey '^Q' fzf-cd-widget

# === eza - モダンな ls ===
alias ls='eza --icons'
alias ll='eza -lh --icons --git'
alias la='eza -lah --icons --git'
alias lt='eza --tree --icons --level=2'
alias llt='eza --tree --icons --level=2 -lh'

# === bat - シンタックスハイライト付き cat ===
export BAT_THEME="Monokai Extended"
alias cat='bat --style=auto'
alias bathelp='bat --plain --language=help'

# bat でヘルプを表示
help() {
    "$@" --help 2>&1 | bat --plain --language=help
}

# === ripgrep - 高速 grep ===
alias rg='rg --smart-case --hidden --glob "!.git/*"'

# === mise - バージョン管理 ===
eval "$(mise activate zsh)"

# === direnv - ディレクトリ別環境変数 ===
eval "$(direnv hook zsh)"

# === ghq - Git リポジトリ管理 ===
# fzf でリポジトリに移動
function ghq-cd() {
  local selected
  local ghq_root
  ghq_root=$(ghq root)
  selected=$(ghq list | fzf --preview "ls -la $ghq_root/{}" --height 50%)
  if [ -n "$selected" ]; then
    cd "$ghq_root/$selected"
  fi
}
alias ghqcd='ghq-cd'

# クローンしてリポジトリに移動
function ghq-get() {
  ghq get "$@" && ghq-cd
}
alias ghqclone='ghq-get'

# === starship - モダンなプロンプト ===
eval "$(starship init zsh)"

# === zsh-syntax-highlighting - シンタックスハイライト ===
source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# === Git ===
# g で git を短縮
alias g='git'

# git の補完を g でも効くようにする
compdef g=git

# === fzf Git ユーティリティ（簡潔版） ===
# 変更ファイルを選んで add
gadd() {
  git status -sb |
  fzf -m --ansi --preview 'echo {} | sed "s/^...//" | xargs git diff --color=always --' --preview-window=down,60% |
  sed 's/^...//' |
  xargs -r git add
}

# スタッシュを選んで pop
gstp() {
  git stash list --color=always |
  fzf --ansi --preview 'cut -d: -f1 <<< "{}" | xargs git stash show -p --color=always' |
  cut -d: -f1 |
  xargs -r git stash pop
}

# === ディレクトリ移動 ===
setopt AUTO_CD          # ディレクトリ名だけで cd
alias ..='cd ..'

# === 設定ファイル編集 ===
alias zshconfig='${EDITOR:-vim} ~/.zshrc'
alias reload='source ~/.zshrc'

# === Docker ===
alias d='docker'
alias dc='docker compose'

# Added by Antigravity
export PATH="/Users/junhat6/.antigravity/antigravity/bin:$PATH"

alias anti='open -a Antigravity'
