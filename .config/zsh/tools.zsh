# === 表示・閲覧ツール (eza / bat / ripgrep が必要) ===

# eza
alias ls='eza --icons'
alias ll='eza -lh --icons --git'
alias la='eza -lah --icons --git'
alias lt='eza --tree --icons --level=2'
alias llt='eza --tree --icons --level=2 -lh'

export BAT_THEME="Catppuccin Latte"
alias rg='rg --smart-case --hidden --glob "!.git/*"'

# === Go環境変数 ===
export PATH=$PATH:$HOME/go/bin

# === mise - バージョン管理 ===
eval "$(mise activate zsh)"

# === starship - モダンなプロンプト ===
eval "$(starship init zsh)"

# === ショートカット ===
alias zshconfig='nvim ~/.zshrc'
alias reload='source ~/.zshrc'

alias d='docker'
alias dc='docker compose'
alias cc='claude --dangerously-skip-permissions'
alias lg='lazygit'

# === dotfiles (yadm) ===
alias dlg='yadm enter lazygit'

# 共有設定の一覧から選び、ホーム内の実ファイルを開く。
dedit() {
  dotfiles edit "$@"
}

# === エディタ ===
export EDITOR='nvim'
alias v='nvim .'     # カレントディレクトリを開く

# === tmux ===
alias ta='tmux new-session -A -s'

eval "$(atuin init zsh)"

# この端末にだけあるツールは未導入でも起動できる
if command -v devctl >/dev/null 2>&1; then
  eval "$(devctl shell zsh)"
fi
