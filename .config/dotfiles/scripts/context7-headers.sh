#!/bin/sh
# Claude Code の headersHelper。Context7 の API キーをこの Mac のキーチェーンから読み、
# ヘッダー JSON を出す。キーが無ければ {} を出し、匿名 (低い利用上限) で接続させる。
# MCP サーバーの登録は dotfiles では配らない (端末ごと)。登録済みの端末の ~/.claude.json が
# このスクリプトを参照しているため残している。
k=$(/usr/bin/security find-generic-password -s context7-api-key -w 2>/dev/null) || k=
case $k in
  ''|*[!A-Za-z0-9_-]*) echo '{}' ;;
  *) printf '{"X-Context7-API-Key":"%s"}\n' "$k" ;;
esac
