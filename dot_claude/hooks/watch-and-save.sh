#!/bin/bash
# Watch Claude Code sessions and sync to Obsidian in real-time (append mode)
# Supports multiple concurrent sessions with project-based organization

OBSIDIAN_DIR="$HOME/ghq/github.com/junhat6/my-vault/claude"
SESSION_DIR="$HOME/.claude/projects"
SYNC_STATE_DIR="$HOME/.claude/sync-state"  # セッションごとの同期状態を保存

mkdir -p "$OBSIDIAN_DIR"
mkdir -p "$SYNC_STATE_DIR"

# ghqオーナー一覧をキャッシュ（新規cloneを拾えるようループ内で定期リフレッシュする）
refresh_ghq_owners() {
    GHQ_OWNERS=$(ls -1 "$HOME/ghq/github.com" 2>/dev/null | tr '\n' '|' | sed 's/|$//')
}
refresh_ghq_owners

# セッションファイルのパスからプロジェクト名を抽出
get_project_name() {
    local session_file="$1"
    local project_dir=$(dirname "$session_file" | xargs basename)

    # ghqパターンの場合: -Users-junhat6-ghq-github-com-owner-repo
    if [[ "$project_dir" =~ ghq-github-com-(.+)$ ]]; then
        local suffix="${BASH_REMATCH[1]}"

        # オーナー一覧から最長一致するものを探す
        local best_match=""
        local best_repo=""

        # オーナーリストをループ
        while IFS='|' read -ra owners; do
            for owner in "${owners[@]}"; do
                # オーナー名のハイフンをそのまま使って照合
                local owner_pattern="${owner}-"
                if [[ "$suffix" == ${owner_pattern}* ]]; then
                    local repo="${suffix#${owner_pattern}}"
                    # より長いオーナー名を優先（assari-harassment > assari）
                    if [[ ${#owner} -gt ${#best_match} ]]; then
                        best_match="$owner"
                        best_repo="$repo"
                    fi
                fi
            done
        done <<< "$GHQ_OWNERS"

        if [[ -n "$best_repo" ]]; then
            echo "$best_repo"
            return
        fi

        # フォールバック: 最後のハイフン区切り部分
        echo "${suffix##*-}"
        return
    fi

    # 非ghqパス（dotfilesなど）
    # -Users-junhat6-dotfiles → dotfiles
    # -Users-junhat6--claude → claude
    if [[ "$project_dir" =~ ^-Users-[^-]+-+(.+)$ ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        # フォールバック
        echo "${project_dir##*-}"
    fi
}

# セッションファイルのハッシュを取得（同期状態ファイル名に使用）
get_session_hash() {
    local session_file="$1"
    echo "$session_file" | md5 | cut -c1-12
}

sync_session() {
    local session_file="$1"
    local TODAY=$(date +%Y年%-m月%-d日)
    # システムのローカルタイムゾーンに依存せず「今日のローカル0時」をUTCに変換する
    local TODAY_START_UTC=$(TZ=UTC date -j -f "%s" "$(date -v0H -v0M -v0S +%s)" +%Y-%m-%dT%H:%M:%S 2>/dev/null)

    # プロジェクト名を取得
    local project_name=$(get_project_name "$session_file")
    local project_dir="${OBSIDIAN_DIR}/${project_name}"
    local OUTPUT_FILE="${project_dir}/${TODAY}.md"

    # セッション固有の同期状態ファイル
    local session_hash=$(get_session_hash "$session_file")
    local LAST_LINE_FILE="${SYNC_STATE_DIR}/${session_hash}.line"

    # プロジェクトディレクトリを作成
    mkdir -p "$project_dir"

    # Create file with header if it doesn't exist
    if [ ! -f "$OUTPUT_FILE" ]; then
        echo "# ${TODAY} - ${project_name}" > "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
    fi

    # Get last synced line number for THIS session
    # ファイルが空/破損している場合は0にフォールバックする（不正値のまま比較すると
    # 同期が永久にスタックするため）
    local last_line=0
    if [ -f "$LAST_LINE_FILE" ]; then
        local raw_last_line
        raw_last_line=$(cat "$LAST_LINE_FILE" 2>/dev/null)
        if [[ "$raw_last_line" =~ ^[0-9]+$ ]]; then
            last_line="$raw_last_line"
        fi
    fi

    # Count current lines in session file
    local current_lines=$(wc -l < "$session_file" | tr -d ' ')

    # Only process new lines (append mode - no overwriting)
    if [ "$current_lines" -gt "$last_line" ]; then
        # current_lines算出後にファイルが追記される可能性があるため、tailではなく
        # head -n current_lines で読む範囲をカウント時点に固定する（レースで重複書き込みを防ぐ）
        # -R + try/catchで壊れたJSON行を1行単位でスキップし、バッチ中の1行の破損で
        # それ以降の行が全て失われないようにする
        local new_content
        new_content=$(head -n "$current_lines" "$session_file" | tail -n +$((last_line + 1)) | jq -R -r --arg today_start "$TODAY_START_UTC" '
        (try fromjson catch empty) |
        select(.type == "user" or .type == "assistant") |
        select((.timestamp // "9999") >= $today_start) |
        if .type == "user" then
            (.message.content // .content // "") as $content |
            if ($content | type) == "string" then
                if ($content | test("<local-command|<command-name>|<system-reminder>|<task-notification>"; "i")) then
                    empty
                else
                    "**ユーザー**: " + $content + "\n"
                end
            else
                empty
            end
        elif .type == "assistant" then
            if (.message.content | type) == "array" then
                (.message.content[] | select(.type == "text") |
                    if (.text | test("^No response requested"; "i")) then
                        empty
                    else
                        "**Claude**: " + .text + "\n"
                    end
                )
            else
                empty
            end
        else
            empty
        end
        ')
        local jq_status=$?

        if [ "$jq_status" -ne 0 ]; then
            # jqが失敗した場合はlast_lineを進めない（次回同じ範囲を再試行させる）
            echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] jq failed (exit=$jq_status) for session=$session_file, will retry next cycle" >&2
        else
            # Append new content if any
            if [ -n "$new_content" ]; then
                printf '%s\n' "$new_content" >> "$OUTPUT_FILE"
                echo "" >> "$OUTPUT_FILE"

                # Git commit はObsidian Gitプラグインに任せる
            fi

            # Update last synced line for THIS session
            echo "$current_lines" > "$LAST_LINE_FILE"
        fi
    fi
}

# Find ALL active sessions (not just the most recent one)
find_sessions() {
    find "$SESSION_DIR" -path "*/subagents/*" -prune -o \
        -name "*.jsonl" -type f -mmin -60 -size +1000c -print 2>/dev/null
}

# Clean up old sync state files (older than 7 days)
cleanup_old_state() {
    find "$SYNC_STATE_DIR" -name "*.line" -type f -mtime +7 -delete 2>/dev/null
}

echo "Watching for Claude session changes (multi-session mode)..."
echo "Saving to: $OBSIDIAN_DIR/<project-name>/<date>.md"

# Initial cleanup
cleanup_old_state

loop_count=0

while true; do
    # Process ALL active sessions
    while IFS= read -r session; do
        if [ -n "$session" ]; then
            sync_session "$session"
        fi
    done < <(find_sessions)

    # 720ループ（5秒間隔で約1時間）ごとにメンテナンス処理を実行する
    # KeepAliveで数週間常駐し続けるため、起動時1回だけでは
    # 古いstateファイルの掃除も新規ghq cloneの反映もされない
    loop_count=$((loop_count + 1))
    if [ $((loop_count % 720)) -eq 0 ]; then
        cleanup_old_state
        refresh_ghq_owners
    fi

    sleep 5
done
