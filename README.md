# Dotfiles

個人用の dotfiles セット。zsh + fzf を中心に、軽くて実用的な最小構成。

## 構成
- `.gitconfig` : Git エイリアスと基本設定
- `.zshrc` : zsh 設定（補完・履歴・fzf・zoxide・Gitユーティリティ）
- `install.sh` : シンボリックリンク作成と初期セットアップ

## インストール
```bash
git clone https://github.com/yourusername/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh
source ~/.zshrc
```

`install.sh` は既存の `~/.gitconfig` / `~/.zshrc` がある場合にバックアップを案内します。

## 依存ツール（主なもの）
- fzf
- eza / bat / ripgrep (rg)
- zoxide
- mise / direnv
- ghq
- starship
- zsh-syntax-highlighting
- docker (alias 用、任意)

macOS (Homebrew) の例:
```bash
brew install fzf eza bat ripgrep zoxide ghq starship direnv
```

## 主な機能 (.zshrc)
- 補完: `compinit` と大文字小文字無視、メニュー選択。
- 履歴: 重複排除（追加時・検索時）、スペース始まり無視、履歴展開確認。
- fzf 基本: `FZF_DEFAULT_COMMAND=rg --files --hidden --follow --glob "!.git/*"` を設定。Ctrl-T でファイル選択が高速。
- ナビゲーション: zoxide + `AUTO_CD`。`Ctrl-Q` で zoxide 一覧を fzf から選んで移動（プレビューは eza/ls）。
- 表示: `ls/ll/la/lt/llt` を eza で置換、`cat` を bat で置換、`rg` に便利オプション付与。
- Git:
  - `g` で git エイリアス、補完有効。
  - `gadd`: `git status -sb` から fzf で複数選択して add（diff プレビュー付）。
  - `gstp`: スタッシュを fzf で選んで pop（パッチプレビュー付）。
- ghq: `ghqcd` でリポジトリ移動、`ghqclone` で取得して即移動。
- プロンプト: starship。
- ショートカット: `zshconfig` / `reload`、`d` / `dc`、`anti`（Antigravity 起動）。

## Git ユーザー情報セット
```bash
git config --global user.name "Your Name"
git config --global user.email "your@email.com"
```
