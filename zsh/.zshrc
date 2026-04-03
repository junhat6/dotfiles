export LANG=ja_JP.UTF-8

# === 基本オプション・補完 ===
setopt EXTENDED_GLOB                 # 拡張グロブ（^*.log など）
setopt NO_BEEP                       # ビープ抑止
fpath=(~/.zsh/completions $fpath)
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
setopt HIST_IGNORE_SPACE
setopt HIST_VERIFY                   # 履歴展開を実行前に確認

# === fzf 基本 ===
eval "$(fzf --zsh)"

# fzf 設定
export FZF_DEFAULT_OPTS="--height 40% --layout=reverse --border --inline-info"
export FZF_DEFAULT_COMMAND='rg --files --hidden --follow --glob "!.git/*"'

# === ナビゲーション zoxide (brew install zoxide) ===
eval "$(zoxide init zsh)"
setopt AUTO_CD                       # ディレクトリ名だけで cd
setopt AUTO_PUSHD PUSHD_IGNORE_DUPS PUSHD_SILENT PUSHDMINUS  # cd をスタックに積む、重複排除
stty -ixon                          # Ctrl-S/Ctrl-Q のフロー制御を無効化（Ctrl-Q をショートカットで使うため）
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

# eza
alias ls='eza --icons'
alias ll='eza -lh --icons --git'
alias la='eza -lah --icons --git'
alias lt='eza --tree --icons --level=2'
alias llt='eza --tree --icons --level=2 -lh'

export BAT_THEME="Monokai Extended"
alias rg='rg --smart-case --hidden --glob "!.git/*"'

# === Go環境変数 ===
export GOPATH=$HOME/go
export GOBIN=$GOPATH/bin
export PATH=$PATH:$GOBIN

# === mise - バージョン管理 ===
eval "$(mise activate zsh)"

# === direnv - ディレクトリ別環境変数 ===
eval "$(direnv hook zsh)"

# === ghq - Git リポジトリ管理 ===
# fzf でリポジトリ選択して移動 (Ctrl-G)
fzf-ghq-widget() {
  local repo
  repo=$(ghq list | fzf \
    --preview 'eza -lah --icons --git "$(ghq root)/{}" 2>/dev/null' \
    --preview-window=right:60%) || return
  cd "$(ghq root)/$repo"
  zle reset-prompt
}
zle -N fzf-ghq-widget
bindkey '^G' fzf-ghq-widget

# === starship - モダンなプロンプト ===
eval "$(starship init zsh)"

# === zsh-syntax-highlighting - シンタックスハイライト ===
source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# === fzf Git ユーティリティ（簡潔版） ===
# ブランチ切り替え
gb() {
  local branches branch
  branches=$(git branch -a) &&
  branch=$(echo "$branches" | fzf +m) &&
  git checkout "$(echo "$branch" | sed "s/.* //" | sed "s#remotes/[^/]*/##")"
}

# === ショートカット ===
alias zshconfig='nvim ~/.zshrc'
alias reload='source ~/.zshrc'

alias d='docker'
alias dc='docker compose'
alias cc='claude --dangerously-skip-permissions'
alias lg='lazygit'

# === エディタ ===
export EDITOR='nvim'
alias v='nvim .'     # カレントディレクトリを開く

# === tmux ===
alias ta='tmux new-session -A -s'

# Added by Antigravity
export PATH="/Users/junhat6/.antigravity/antigravity/bin:$PATH"
alias anti='open -a Antigravity'
