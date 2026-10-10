# Karabinerと割り当て図の更新

- 正本は `karabiner.json`。現在選択中のプロファイルを確認してから編集する。
- `README.md` と `keymap.svg` は生成物。手編集せず、リポジトリのルート（yadmではHOME）で `python3 .config/dotfiles/scripts/karabiner_map.py` を実行する。
- `python3 .config/dotfiles/scripts/karabiner_map.py --check` と `bash .config/dotfiles/scripts/check.sh "$PWD"` を実行する。
- SVGを表示し、印字・割り当て・注釈の対応と、文字や線の重なりを目で確認する。画像の変更には読みやすさの確認も必要。
- JSON・README・SVGは同じコミットに含める。図のレイアウトや対応可能なルールを変える場合は `.config/dotfiles/scripts/karabiner_map.py` とテストも更新する。
- 未対応の条件・イベントを生成エラーから除外しない。動作を正確に表現できるよう生成器を拡張する。
- Karabinerのバックアップ、ログ、assetsはローカル専用。共有するファイルは `.config/dotfiles/ownership.json` とHOMEの `.gitignore` に個別登録する。
