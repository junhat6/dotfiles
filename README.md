# Dotfiles

個人用の dotfiles 設定

## 構成

- `.gitconfig` - Git エイリアスと基本設定
- `.zshrc` - zsh 設定と fzf を使った Git 拡張機能
- `install.sh` - セットアップスクリプト

## セットアップ

```bash
cd ~/dotfiles
./install.sh
source ~/.zshrc
```

## Git の設定

インストール後、以下を実行してユーザー情報を設定してください：

```bash
git config --global user.name "Your Name"
git config --global user.email "your@email.com"
```

## 使用可能なコマンド

### 基本コマンド（.gitconfig）

```bash
g st              # git status
g ad file.txt     # git add file.txt
g cm "message"    # git commit -m "message"
g co main         # git checkout main
g br              # git branch
g df              # git diff

g lg              # git log --oneline --graph --decorate
g lga             # 全ブランチのログ
g lgg             # 見やすいカラフルなログ
g last            # 最後のコミット

g ps              # git push
g psf             # git push --force-with-lease
g pl              # git pull

g aa              # git add .
g cob feature     # git checkout -b feature
g amend           # git commit --amend --no-edit
g aliases         # エイリアス一覧表示
```

### fzf 拡張コマンド（.zshrc）

```bash
gb                # fzf でブランチ選択して切り替え
gbd               # fzf でブランチ選択して削除
gbr               # fzf でリモートブランチも含めて検索

gshow             # fzf でコミット選択して詳細表示
gcp               # fzf でコミット選択してチェリーピック

gaf               # fzf でファイル選択して git add
gstp              # fzf でスタッシュ選択して pop
```

## 必要な依存関係

- [fzf](https://github.com/junegunn/fzf) - ファジーファインダー

```bash
brew install fzf
```

## Git で管理

```bash
cd ~/dotfiles
git init
git add .
git commit -m "Initial dotfiles"
git remote add origin https://github.com/yourusername/dotfiles.git
git push -u origin main
```

## 新しいマシンでのセットアップ

```bash
git clone https://github.com/yourusername/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh
source ~/.zshrc
```
