# === ナビゲーション zoxide (brew install zoxide) ===
eval "$(zoxide init zsh)"
setopt AUTO_CD                       # ディレクトリ名だけで cd
setopt AUTO_PUSHD PUSHD_IGNORE_DUPS PUSHD_SILENT PUSHDMINUS  # cd をスタックに積む、重複排除
[[ -t 0 ]] && stty -ixon                          # Ctrl-S/Ctrl-Q のフロー制御を無効化（Ctrl-Q をショートカットで使うため）


# === ghq - Git リポジトリ管理 ===
# fzf でリポジトリ選択して移動 (Ctrl-Q) — 訪問履歴に関係なく ghq 管理下の全リポジトリ + ~/.config 配下の独立リポジトリが対象
# ドットファイル選択後も入力中のコマンドとカーソルを維持する。
dotfiles-edit-widget() {
  local saved_buffer="$BUFFER" saved_cursor="$CURSOR" saved_pwd="$PWD"
  zle -I
  dedit
  cd -- "$saved_pwd"
  BUFFER="$saved_buffer"
  CURSOR="$saved_cursor"
  zle reset-prompt
}
zle -N dotfiles-edit-widget
bindkey '^X^D' dotfiles-edit-widget

fzf-ghq-widget() {
  local root selected dir config_dirs=()
  local saved_buffer="$BUFFER" saved_cursor="$CURSOR" saved_pwd="$PWD"
  root="$(ghq root)" || return

  for dir in "$HOME"/.config/*/; do
    [[ -d "${dir}.git" ]] && config_dirs+=("${dir#$HOME/}")
  done

  selected=$(
    { ghq list; (( ${#config_dirs} )) && printf '%s\n' "${config_dirs[@]}"; print -r -- '[dotfiles] shared settings'; } | \
      DOTFILES_GHQ_ROOT="$root" DOTFILES_HOME="$HOME" fzf \
      --preview 'if [ {} = "[dotfiles] shared settings" ]; then printf "%s\n" "Shared settings: Enter opens dedit"; else eza -lah --icons --git "$DOTFILES_GHQ_ROOT"/{} 2>/dev/null || eza -lah --icons --git "$DOTFILES_HOME"/{} 2>/dev/null; fi' \
      --preview-window=right:60%
  ) || { BUFFER="$saved_buffer"; CURSOR="$saved_cursor"; zle reset-prompt; return; }

  if [[ "$selected" == '[dotfiles] shared settings' ]]; then
    zle -I
    dedit
    cd -- "$saved_pwd"
  elif [[ -d "$root/$selected" ]]; then
    cd -- "$root/$selected"
  elif [[ -d "$HOME/$selected" ]]; then
    cd -- "$HOME/$selected"
  fi
  BUFFER="$saved_buffer"
  CURSOR="$saved_cursor"
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
