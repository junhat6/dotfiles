#!/bin/bash
# 会社の情報は Git 管理外のホーム側だけへ保存する。
set -euo pipefail
if [[ $# != 3 || ! "$1" =~ ^[A-Za-z0-9-]+$ || -z "$2" || -z "$3" ]]; then
    printf 'Usage: bash scripts/setup-git-work.sh GITHUB_ORG "COMMIT_NAME" "WORK_EMAIL"\n' >&2
    exit 2
fi
umask 077
git config --file "$HOME/.gitconfig.work" user.name "$2"
git config --file "$HOME/.gitconfig.work" user.email "$3"
git config --file "$HOME/.gitconfig.local" "includeIf.gitdir:~/ghq/github.com/$1/.path" '~/.gitconfig.work'
printf '会社名義の切り替えを設定しました: ~/ghq/github.com/%s/\n' "$1"
printf '対象 repo で確認: git config --show-origin --get user.email\n'
