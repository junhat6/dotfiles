# Google のリンクは gog CLI で読む

会話に `docs.google.com`、`drive.google.com`、`sheets.google.com`、`slides.google.com`、`forms.google.com` の URL が出てきたら、
ユーザーが読み方を言わなくても、まず `google-links` スキルを読み込み、その手順で `gog` CLI を使って中身を取得する。
WebFetch や claude.ai の Google コネクターで代用しない。

このルールを置く理由: スキルは説明文との一致で呼ばれるため、URL が貼られただけだと呼ばれないことがある。
ルールは毎回読み込まれるので、ここから確実にスキルへつなぐ。
