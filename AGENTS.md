# Learning Preferences

- 方法だけでなく、採用した意図・背景・設計上の理由を必ず説明する。可能なら、採用しない場合の影響も簡潔に添える。

# dotfiles を変更するときだけ適用

- コミットメッセージは件名・本文とも日本語にする。
- HOME の dotfiles は `yadm` で操作し、変更したパスだけをステージする。
- 管理対象の追加・移動時は `.gitignore` と `.config/dotfiles/ownership.json` も更新する。
