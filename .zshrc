# ==================== Git ====================

# g で git を短縮
alias g='git'

# git の補完を g でも効くようにする
compdef g=git

# ==================== fzf Git 拡張 ====================

# fzf を使ったブランチ切り替え
gb() {
  local branches branch
  branches=$(git branch -a) &&
  branch=$(echo "$branches" | fzf +m) &&
  git checkout $(echo "$branch" | sed "s/.* //" | sed "s#remotes/[^/]*/##")
}

# fzf を使ったブランチ削除
gbd() {
  local branches branch
  branches=$(git branch) &&
  branch=$(echo "$branches" | fzf -m) &&
  git branch -d $(echo "$branch" | sed "s/.* //")
}

# fzf を使ったコミット選択（git show）
gshow() {
  git log --oneline --graph --decorate --all |
  fzf --ansi --no-sort --reverse --tiebreak=index --preview \
    'echo {} | grep -o "[a-f0-9]\{7\}" | head -1 | xargs git show --color=always' |
  grep -o "[a-f0-9]\{7\}" | head -1 | xargs git show
}

# fzf を使ったファイル選択して git add
gaf() {
  git status --short |
  fzf -m --ansi --preview 'git diff --color=always {2}' |
  awk '{print $2}' |
  xargs git add
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
  git branch -a |
  fzf --preview 'echo {} | sed "s/.* //" | sed "s#remotes/[^/]*/##" | xargs git log --oneline --graph --decorate --color=always' |
  sed "s/.* //" |
  sed "s#remotes/[^/]*/##" |
  xargs git checkout
}
