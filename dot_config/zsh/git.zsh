# === fzf Git ユーティリティ（簡潔版） ===
# git pull の通常の出力に、取り込んだコミット一覧を追加
git() {
  if [[ $1 == pull ]]; then
    shift
    command git-pull-summary commits "$@"
  else
    command git "$@"
  fi
}

# ブランチ切り替え
gb() {
  local branches branch
  branches=$(git branch -a) &&
  branch=$(echo "$branches" | fzf +m) &&
  git checkout "$(echo "$branch" | sed "s/.* //" | sed "s#remotes/[^/]*/##")"
}
