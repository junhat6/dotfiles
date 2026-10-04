fpath=(~/.zsh/completions $fpath)
autoload -Uz compinit
compinit

# 大文字小文字を区別しない補完
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'

# fzf-tab に候補選択を任せる
zstyle ':completion:*' menu no

# === fzf 基本 ===
eval "$(fzf --zsh)"

# fzf 設定
export FZF_DEFAULT_OPTS="--height 40% --layout=reverse --border --inline-info"
export FZF_DEFAULT_COMMAND='rg --files --hidden --follow --glob "!.git/*"'

# Ctrl-T: ファイルのみをファジーファインダーし、選択パスをコマンドラインに挿入（fzf 標準ウィジェット）
export FZF_CTRL_T_COMMAND='fd --type f --hidden --follow --exclude .git'
export FZF_CTRL_T_OPTS="--preview 'bat --color=always --style=numbers --line-range=:200 {} 2>/dev/null'"

# Ctrl-F: ディレクトリのみをファジーファインダーし、選択後 cd（fzf 標準ウィジェットを Ctrl-F に割り当て）
export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
export FZF_ALT_C_OPTS="--preview 'eza -lah --icons --git {} 2>/dev/null'"
bindkey '^F' fzf-cd-widget
bindkey -r '\ec'                     # Alt-C は Hammerspoon のアプリ切り替えと衝突するため無効化

# compinit・fzf の後、ウィジェットを包むプラグインより前に読み込む
if [[ -r "$_dotfiles_brew_prefix/opt/fzf-tab/share/fzf-tab/fzf-tab.zsh" ]]; then
  source "$_dotfiles_brew_prefix/opt/fzf-tab/share/fzf-tab/fzf-tab.zsh"
  zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 --color=always -- "$realpath"'
  zstyle ':fzf-tab:*' switch-group '[' ']'
fi
