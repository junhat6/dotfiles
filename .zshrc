export LANG=ja_JP.UTF-8

# === 基本オプション・補完 ===
setopt EXTENDED_GLOB                 # 拡張グロブ（^*.log など）
setopt NO_BEEP                       # ビープ抑止
autoload -Uz compinit
compinit

# 大文字小文字を区別しない補完
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'

# 補完メニューを選択式に
zstyle ':completion:*' menu select

# === 履歴 ===
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt SHARE_HISTORY
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_ALL_DUPS          # 追加時に過去の重複を消す
setopt HIST_FIND_NO_DUPS             # 検索結果で重複を表示しない
setopt HIST_IGNORE_SPACE
setopt HIST_VERIFY                   # 履歴展開を実行前に確認

# === fzf 基本 ===
eval "$(fzf --zsh)"

# fzf 設定
export FZF_DEFAULT_OPTS="--height 40% --layout=reverse --border --inline-info"
export FZF_DEFAULT_COMMAND='rg --files --hidden --follow --glob "!.git/*"'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"

# === ナビゲーション zoxide (brew install zoxide) ===
eval "$(zoxide init zsh)"
setopt AUTO_CD                       # ディレクトリ名だけで cd
setopt AUTO_PUSHD PUSHD_IGNORE_DUPS PUSHD_SILENT PUSHDMINUS  # cd をスタックに積む、重複排除
fzf-cd-widget() {                    # Ctrl-Q で zoxide 一覧から移動
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

# === 表示・閲覧ツール (eza / bat / ripgrep が必要) ===
alias ls='eza --icons'
alias ll='eza -lh --icons --git'
alias la='eza -lah --icons --git'
alias lt='eza --tree --icons --level=2'
alias llt='eza --tree --icons --level=2 -lh'
export BAT_THEME="Monokai Extended"
alias cat='bat --style=auto'
alias bathelp='bat --plain --language=help'
help() { "$@" --help 2>&1 | bat --plain --language=help; }
alias rg='rg --smart-case --hidden --glob "!.git/*"'

# === mise - バージョン管理 ===
eval "$(mise activate zsh)"

# === direnv - ディレクトリ別環境変数 ===
eval "$(direnv hook zsh)"

# === ghq - Git リポジトリ管理 ===
# ghq-cd でリポジトリに移動
function ghq-cd() {
  local selected ghq_root
  ghq_root=$(ghq root)
  selected=$(ghq list | fzf --preview "ls -la $ghq_root/{}" --height 50%)
  [ -n "$selected" ] && cd "$ghq_root/$selected"
}
alias ghqcd='ghq-cd'
# ghq-get でリポジトリをクローンして移動
function ghq-get() { ghq get "$@" && ghq-cd; }
alias ghqclone='ghq-get'

# === starship - モダンなプロンプト ===
eval "$(starship init zsh)"

# === zsh-syntax-highlighting - シンタックスハイライト ===
source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# === Git ===
alias g='git'
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

# === ショートカット ===
alias zshconfig='${EDITOR:-vim} ~/.zshrc'
alias reload='source ~/.zshrc'

alias d='docker'
alias dc='docker compose'

# Added by Antigravity
export PATH="/Users/junhat6/.antigravity/antigravity/bin:$PATH"
alias anti='open -a Antigravity'
