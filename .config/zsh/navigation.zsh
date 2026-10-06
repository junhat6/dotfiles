# === ナビゲーション zoxide (brew install zoxide) ===
eval "$(zoxide init zsh)"
setopt AUTO_CD                       # ディレクトリ名だけで cd
setopt AUTO_PUSHD PUSHD_IGNORE_DUPS PUSHD_SILENT PUSHDMINUS  # cd をスタックに積む、重複排除
[[ -t 0 ]] && stty -ixon                          # Ctrl-S/Ctrl-Q のフロー制御を無効化（Ctrl-Q をショートカットで使うため）


# === ghq - Git リポジトリ管理 ===
# fzf でリポジトリ選択して移動 (Ctrl-Q) — 訪問履歴に関係なく ghq 管理下の全リポジトリ + ~/.config 配下の独立リポジトリが対象
fzf-ghq-widget() {
  local root selected config_dirs=()
  root="$(ghq root)"

  for dir in "$HOME"/.config/*/; do
    [[ -d "${dir}.git" ]] && config_dirs+=("${dir#$HOME/}")
  done

  selected=$(
    { ghq list; printf '%s\n' "${config_dirs[@]}"; } | fzf \
      --preview 'eza -lah --icons --git "'"$root"'/{}" 2>/dev/null || eza -lah --icons --git "'"$HOME"'/{}" 2>/dev/null' \
      --preview-window=right:60%
  ) || return

  if [[ -d "$root/$selected" ]]; then
    cd "$root/$selected"
  elif [[ -d "$HOME/$selected" ]]; then
    cd "$HOME/$selected"
  fi
  zle reset-prompt
}
zle -N fzf-ghq-widget
bindkey '^Q' fzf-ghq-widget


# Finder の現在位置へ移動。失敗時は現在のディレクトリを保つ。
cdf() {
  local dest
  dest=$(osascript -e 'tell application "Finder" to POSIX path of (insertion location as alias)') || return
  if [[ ! -d "$dest" ]]; then
    print -u2 -- "cdf: Finder の場所がディレクトリではありません: $dest"
    return 1
  fi
  cd -- "$dest"
}
