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
setopt HIST_IGNORE_SPACE

# === fzf - あいまい検索 ===
eval "$(fzf --zsh)"

# fzf 設定
export FZF_DEFAULT_OPTS="--height 40% --layout=reverse --border --inline-info"
export FZF_DEFAULT_COMMAND='rg --files --hidden --follow --glob "!.git/*"'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"

# === zoxide - スマート cd ===
eval "$(zoxide init zsh)"

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

# === fzf Git 拡張 ===
# fzf を使ったブランチ切り替え
gb() {
  local branches branch
  branches=$(git branch -a) &&
  branch=$(echo "$branches" | fzf +m) &&
  git checkout "$(echo "$branch" | sed "s/.* //" | sed "s#remotes/[^/]*/##")"
}

# fzf を使ったファイル選択して git add
gadd() {
  git status --short |
  fzf -m --ansi --preview 'git diff --color=always {2}' |
  awk '{print $2}' |
  xargs git add
}

# fzf を使ったコミット選択（git show）
gshow() {
  git log --oneline --graph --decorate --all |
  fzf --ansi --no-sort --reverse --tiebreak=index --preview \
    'echo {} | grep -o "[a-f0-9]\{7\}" | head -1 | xargs git show --color=always' |
  grep -o "[a-f0-9]\{7\}" | head -1 | xargs git show
}

# fzf でコミット選択してチェリーピック
gcp() {
  git log --oneline --graph --decorate --all |
  fzf --ansi --no-sort --reverse --preview \
    'echo {} | grep -o "[a-f0-9]\{7\}" | head -1 | xargs git show --color=always' |
  grep -o "[a-f0-9]\{7\}" | head -1 | xargs git cherry-pick
}

# fzf でスタッシュ選択して pop
gstp() {
  git stash list |
  fzf --preview 'echo {} | cut -d: -f1 | xargs git stash show -p --color=always' |
  cut -d: -f1 |
  xargs git stash pop
}

# fzf でリモートブランチも含めて検索
gbr() {
  local branch
  branch=$(git branch -a |
    fzf --preview 'echo {} | sed "s/.* //" | sed "s#remotes/[^/]*/##" | xargs git log --oneline --graph --decorate --color=always' |
    sed "s/.* //" |
    sed "s#remotes/[^/]*/##")
  [ -n "$branch" ] && git checkout "$branch"
}

# === ディレクトリ移動 ===
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# === 設定ファイル編集 ===
alias zshconfig='${EDITOR:-vim} ~/.zshrc'
alias reload='source ~/.zshrc'

# === Docker ===
alias d='docker'
alias dc='docker compose'
