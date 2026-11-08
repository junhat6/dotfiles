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
# WezTerm と競合せず、未読込のシェルでも EOF にならない Ctrl-]。
bindkey -r '^X^D'
bindkey '^]' dotfiles-edit-widget

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

# Mac mini の ~/ghq に clone して Orca のプロジェクトに登録する (MacBook から 1 手)。
# 例: gq owner/repo / gq https://github.com/owner/repo / gq git@github.com:owner/repo.git
# 置き場所は ghq と同じ <root>/github.com/<owner>/<repo>。既にあれば登録だけ行う。
# 環境変数: GQ_ENV (Orca の環境名) / GQ_REMOTE_ROOT (Mac mini 側の ghq root)
gq() {
  emulate -L zsh
  local env="${GQ_ENV:-mac mini}" root="${GQ_REMOTE_ROOT:-/Users/$USER/ghq}"
  local slug="${1:?usage: gq owner/repo | github URL}"
  slug="${slug#https://github.com/}"; slug="${slug#git@github.com:}"; slug="${slug#github.com/}"
  slug="${slug%.git}"; slug="${slug%/}"
  if [[ ! "$slug" =~ '^[^/]+/[^/]+$' ]]; then
    print -u2 "gq: GitHub の owner/repo を指定してください: $1"
    return 1
  fi
  local owner="${slug%%/*}" repo="${slug#*/}" out
  # Orca のプロジェクト ID は小文字で解決されるため、ID だけ小文字にする
  out=$(orca project setup-clone --project "github:${slug:l}" --host "$env" \
    --url "https://github.com/$slug.git" --destination "$root/github.com/$owner" --json 2>/dev/null)
  if [[ "$(print -r -- "$out" | jq -r '.ok' 2>/dev/null)" == true ]]; then
    print "gq: $env の $root/github.com/$slug に clone して登録しました"
  elif print -r -- "$out" | grep -q 'already exists'; then
    orca repo add --environment "$env" --path "$root/github.com/$slug" >/dev/null &&
      print "gq: 既にあったので $env の $root/github.com/$slug を登録しました"
  else
    print -u2 -r -- "gq: 失敗しました: $(print -r -- "$out" | jq -r '.error.message // .' 2>/dev/null)"
    return 1
  fi
}


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
