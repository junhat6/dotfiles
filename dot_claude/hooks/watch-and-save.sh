#!/bin/bash
# Watch Claude Code / Codex sessions and sync to Obsidian in real-time (append mode)
# Supports multiple concurrent sessions with project/date/branch organization
#
# 出力構造（Claude / Codex 共通の1つのツリーに統合）:
#   main/master での作業: <OBSIDIAN_DIR>/<repo>/<日付>.md
#   ブランチでの作業:     <OBSIDIAN_DIR>/<repo>/<日付>/<ラベル>.md
#     ラベルは Issue 番号を含むブランチ (feature/104 等) なら gh CLI で
#     「104 <Issueタイトル>」に解決し、それ以外はブランチ名をそのまま使う。
#     Orca IDE 等で worktree を並列に動かしてもブランチ単位で会話が分かれる。
#
# ソースごとの抽出方法:
#   Claude: ~/.claude/projects/**/*.jsonl
#     各 user/assistant 行の .cwd / .gitBranch を利用
#   Codex:  ~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl
#     session_meta 行の .payload.cwd / .payload.git.branch / .payload.git.repository_url を利用
#     会話は event_msg の user_message / agent_message から取る
#
# usage: watch-and-save.sh [--once]
#   --once: 1回だけ同期して終了（テスト・手動同期用）

# launchd 起動時は locale が C になり cut -c などが multibyte を壊すため明示する
export LC_ALL=en_US.UTF-8

OBSIDIAN_DIR="${OBSIDIAN_DIR:-$HOME/ghq/github.com/junhat6/my-vault/claude}"
SESSION_DIR="${SESSION_DIR:-$HOME/.claude/projects}"
CODEX_SESSION_DIR="${CODEX_SESSION_DIR:-$HOME/.codex/sessions}"
SYNC_STATE_DIR="${SYNC_STATE_DIR:-$HOME/.claude/sync-state}"  # セッションごとの同期状態を保存
LOG_DIR="$HOME/.claude/logs"                # LaunchAgentのStandardOut/ErrorPath先
MAX_LOG_BYTES=$((10 * 1024 * 1024))         # このサイズを超えたら切り詰める
LOG_KEEP_LINES=5000                         # 切り詰め後に残す行数
TITLE_CACHE_DIR="$SYNC_STATE_DIR/issue-titles"  # Issue タイトルのキャッシュ

mkdir -p "$OBSIDIAN_DIR" "$SYNC_STATE_DIR" "$TITLE_CACHE_DIR"

# ghqオーナー一覧をキャッシュ（新規cloneを拾えるようループ内で定期リフレッシュする）
refresh_ghq_owners() {
    GHQ_OWNERS=$(ls -1 "$HOME/ghq/github.com" 2>/dev/null | tr '\n' '|' | sed 's/|$//')
}
refresh_ghq_owners

# セッションファイルのパスからプロジェクト名を抽出（JSONLにcwdが無い場合のフォールバック）
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

# JSONLに記録された cwd からリポジトリ名を導出する。
# ディレクトリ名のハイフン連結を逆パースするより owner/repo の区切りが曖昧にならない
get_repo_from_cwd() {
    local cwd="$1"
    # ghq: ~/ghq/github.com/<owner>/<repo>(/subdir...)
    if [[ "$cwd" =~ ghq/github\.com/[^/]+/([^/]+) ]]; then
        echo "${BASH_REMATCH[1]}"
        return
    fi
    # Orca IDE の worktree: ~/orca/workspaces/<repo>/<worktree名>
    if [[ "$cwd" =~ orca/workspaces/([^/]+) ]]; then
        echo "${BASH_REMATCH[1]}"
        return
    fi
    local base=$(basename "$cwd")
    echo "${base#.}"   # ~/.claude → claude
}

# GitHub の owner/repo を解決する（Issue タイトル取得用）
resolve_repo_slug() {
    local cwd="$1" repo="$2" repo_url="$3"
    # Codex は remote URL をログに記録しているので最優先で使う
    if [[ "$repo_url" =~ github\.com[:/]([^/]+)/([^/[:space:]]+) ]]; then
        echo "${BASH_REMATCH[1]}/${BASH_REMATCH[2]%.git}"
        return
    fi
    if [[ "$cwd" =~ ghq/github\.com/([^/]+/[^/]+) ]]; then
        echo "${BASH_REMATCH[1]}"
        return
    fi
    # worktree がまだ存在すれば remote から取る
    # （Orca の worktree はマージ後に消えるので ghq からのフォールバックも用意）
    if [ -d "$cwd" ]; then
        local url
        url=$(git -C "$cwd" remote get-url origin 2>/dev/null)
        if [[ "$url" =~ github\.com[:/]([^/]+)/([^/]+)$ ]]; then
            echo "${BASH_REMATCH[1]}/${BASH_REMATCH[2]%.git}"
            return
        fi
    fi
    # ghq 配下から同名リポジトリを探す
    local hit
    hit=$(ls -d "$HOME/ghq/github.com"/*/"$repo" 2>/dev/null | head -1)
    if [ -n "$hit" ]; then
        echo "$(basename "$(dirname "$hit")")/$repo"
    fi
}

# ファイル名・Obsidianリンクを壊す文字を除去して60文字に切り詰める
sanitize_label() {
    printf '%s' "$1" | tr '/\\:|#^[]?*"<>' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//' | cut -c1-60
}

# ブランチ名中の Issue 番号からタイトルを取得する。
# 5秒ループから呼ばれるため必ずファイルキャッシュし、失敗時も1時間は再試行しない
# （オフラインや gh 未認証のときに GitHub API を叩き続けないため）
get_issue_title() {
    local repo="$1" num="$2" cwd="$3" repo_url="$4"
    local cache="$TITLE_CACHE_DIR/${repo}#${num}"
    if [ -f "$cache" ]; then
        cat "$cache"
        return
    fi
    if [ -f "$cache.miss" ] && [ -n "$(find "$cache.miss" -mmin -60 2>/dev/null)" ]; then
        return
    fi
    local slug title=""
    slug=$(resolve_repo_slug "$cwd" "$repo" "$repo_url")
    if [ -n "$slug" ] && command -v gh >/dev/null 2>&1; then
        title=$(gh issue view "$num" -R "$slug" --json title -q .title 2>/dev/null)
    fi
    if [ -n "$title" ]; then
        printf '%s' "$title" > "$cache"
        printf '%s' "$slug" > "$cache.slug"
        rm -f "$cache.miss"
        echo "$title"
    else
        touch "$cache.miss"
    fi
}

# ブランチからファイル名用ラベルを作る。空を返したら main 扱い（リポジトリ直下の日付ファイル）
get_branch_label() {
    local repo="$1" branch="$2" cwd="$3" repo_url="$4"
    case "$branch" in
        "" | main | master) return ;;
    esac
    # ブランチ名に含まれる最初の数字列を Issue 番号とみなす（feature/104 → 104）
    if [[ "$branch" =~ [0-9]+ ]]; then
        local num="${BASH_REMATCH[0]}"
        local title
        title=$(get_issue_title "$repo" "$num" "$cwd" "$repo_url")
        if [ -n "$title" ]; then
            echo "${num} $(sanitize_label "$title")"
            return
        fi
    fi
    sanitize_label "$(printf '%s' "$branch" | tr '/' '-')"
}

# セッションファイルのハッシュを取得（同期状態ファイル名に使用）
get_session_hash() {
    local session_file="$1"
    echo "$session_file" | md5 | cut -c1-12
}

# フォーマット別: チャンクから cwd/branch/repo_url を TSV 3列で抽出する jq フィルタ
META_JQ_CLAUDE='(try fromjson catch empty) | select(.cwd) | [.cwd, (.gitBranch // ""), ""] | @tsv'
META_JQ_CODEX='(try fromjson catch empty) | select(.type == "session_meta") | [.payload.cwd, (.payload.git.branch // ""), (.payload.git.repository_url // "")] | @tsv'

sync_session() {
    local session_file="$1"
    local format="$2"   # claude | codex
    local TODAY=$(date +%Y年%-m月%-d日)
    # システムのローカルタイムゾーンに依存せず「今日のローカル0時」をUTCに変換する
    local TODAY_START_UTC=$(TZ=UTC date -j -f "%s" "$(date -v0H -v0M -v0S +%s)" +%Y-%m-%dT%H:%M:%S 2>/dev/null)

    # セッション固有の同期状態ファイル
    local session_hash=$(get_session_hash "$session_file")
    local LAST_LINE_FILE="${SYNC_STATE_DIR}/${session_hash}.line"
    local META_FILE="${SYNC_STATE_DIR}/${session_hash}.meta"

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
    if [ "$current_lines" -le "$last_line" ]; then
        return
    fi

    local meta_jq="$META_JQ_CLAUDE"
    if [ "$format" = "codex" ]; then
        meta_jq="$META_JQ_CODEX"
    fi

    # 新規行から cwd / ブランチを抽出。チャンクに含まれなければ前回値を使い、
    # それも無ければファイル先頭付近から探す（Codexは先頭行が必ずsession_meta）。
    # 最後の手段として旧来のディレクトリ名パースに落ちる
    local meta
    meta=$(head -n "$current_lines" "$session_file" | tail -n +$((last_line + 1)) | \
        jq -R -r "$meta_jq" 2>/dev/null | tail -1)
    if [ -z "$meta" ] && [ -f "$META_FILE" ]; then
        meta=$(cat "$META_FILE")
    fi
    if [ -z "$meta" ]; then
        meta=$(head -100 "$session_file" | jq -R -r "$meta_jq" 2>/dev/null | tail -1)
    fi
    if [ -n "$meta" ]; then
        printf '%s\n' "$meta" > "$META_FILE"
    fi

    local cwd="" branch="" repo_url=""
    if [ -n "$meta" ]; then
        cwd=$(printf '%s\n' "$meta" | cut -f1)
        branch=$(printf '%s\n' "$meta" | cut -f2)
        repo_url=$(printf '%s\n' "$meta" | cut -f3)
    fi

    local project_name
    if [ -n "$cwd" ]; then
        project_name=$(get_repo_from_cwd "$cwd")
    else
        project_name=$(get_project_name "$session_file")
    fi

    # main/master → <repo>/<日付>.md、それ以外 → <repo>/<日付>/<ラベル>.md
    local label
    label=$(get_branch_label "$project_name" "$branch" "$cwd" "$repo_url")
    local project_dir OUTPUT_FILE
    if [ -n "$label" ]; then
        project_dir="${OBSIDIAN_DIR}/${project_name}/${TODAY}"
        OUTPUT_FILE="${project_dir}/${label}.md"
    else
        project_dir="${OBSIDIAN_DIR}/${project_name}"
        OUTPUT_FILE="${project_dir}/${TODAY}.md"
    fi

    # current_lines算出後にファイルが追記される可能性があるため、tailではなく
    # head -n current_lines で読む範囲をカウント時点に固定する（レースで重複書き込みを防ぐ）
    # -R + try/catchで壊れたJSON行を1行単位でスキップし、バッチ中の1行の破損で
    # それ以降の行が全て失われないようにする
    local new_content jq_status
    if [ "$format" = "codex" ]; then
        # Codex: event_msg の user_message / agent_message が会話本文。
        # environment_context 等は response_item 側にしか入らないため除外フィルタ不要
        new_content=$(head -n "$current_lines" "$session_file" | tail -n +$((last_line + 1)) | jq -R -r --arg today_start "$TODAY_START_UTC" '
        (try fromjson catch empty) |
        select(.type == "event_msg") |
        select((.timestamp // "9999") >= $today_start) |
        if .payload.type == "user_message" then
            "**ユーザー**: " + (.payload.message | rtrimstr("\n")) + "\n"
        elif .payload.type == "agent_message" then
            "**Codex**: " + (.payload.message | rtrimstr("\n")) + "\n"
        else
            empty
        end
        ')
        jq_status=$?
    else
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
        jq_status=$?
    fi

    if [ "$jq_status" -ne 0 ]; then
        # jqが失敗した場合はlast_lineを進めない（次回同じ範囲を再試行させる）
        echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] jq failed (exit=$jq_status) for session=$session_file, will retry next cycle" >&2
        return
    fi

    # Append new content if any
    # 書き込む内容があるときだけディレクトリ・ヘッダーを作る
    # （会話の無いセッションで空の日付ファイルを量産しないため）
    if [ -n "$new_content" ]; then
        mkdir -p "$project_dir"
        if [ ! -f "$OUTPUT_FILE" ]; then
            if [ -n "$label" ]; then
                echo "# ${TODAY} - ${project_name} (${branch})" > "$OUTPUT_FILE"
                # Issue タイトルに解決できたラベルなら冒頭に Issue リンクを置く
                if [[ "$label" =~ ^([0-9]+)[[:space:]] ]]; then
                    local num="${BASH_REMATCH[1]}"
                    local slug_file="$TITLE_CACHE_DIR/${project_name}#${num}.slug"
                    if [ -f "$slug_file" ]; then
                        echo "" >> "$OUTPUT_FILE"
                        echo "Issue: [#${num}](https://github.com/$(cat "$slug_file")/issues/${num})" >> "$OUTPUT_FILE"
                    fi
                fi
            else
                echo "# ${TODAY} - ${project_name}" > "$OUTPUT_FILE"
            fi
            echo "" >> "$OUTPUT_FILE"
        fi

        printf '%s\n' "$new_content" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"

        # Git commit はObsidian Gitプラグインに任せる
    fi

    # Update last synced line for THIS session
    echo "$current_lines" > "$LAST_LINE_FILE"
}

# Find ALL active sessions (not just the most recent one)
find_claude_sessions() {
    find "$SESSION_DIR" -path "*/subagents/*" -prune -o \
        -name "*.jsonl" -type f -mmin -60 -size +1000c -print 2>/dev/null
}

find_codex_sessions() {
    find "$CODEX_SESSION_DIR" -name "*.jsonl" -type f -mmin -60 -size +1000c -print 2>/dev/null
}

# Clean up old sync state files (older than 7 days)
cleanup_old_state() {
    find "$SYNC_STATE_DIR" \( -name "*.line" -o -name "*.meta" \) -type f -mtime +7 -delete 2>/dev/null
}

# KeepAliveで無期限に常駐し続けるためlaunchdのStandardOut/ErrorPathはローテーション
# されない。肥大化を防ぐため、一定サイズを超えたら末尾のみ残して切り詰める。
rotate_logs() {
    local log size
    for log in "$LOG_DIR/obsidian-sync.log" "$LOG_DIR/obsidian-sync-error.log"; do
        if [ -f "$log" ]; then
            size=$(stat -f%z "$log" 2>/dev/null || echo 0)
            if [ "$size" -gt "$MAX_LOG_BYTES" ]; then
                tail -n "$LOG_KEEP_LINES" "$log" > "${log}.tmp" && mv "${log}.tmp" "$log"
            fi
        fi
    done
}

run_sync_cycle() {
    while IFS= read -r session; do
        if [ -n "$session" ]; then
            sync_session "$session" claude
        fi
    done < <(find_claude_sessions)

    while IFS= read -r session; do
        if [ -n "$session" ]; then
            sync_session "$session" codex
        fi
    done < <(find_codex_sessions)
}

# --once: 1回同期して終了（テスト・手動同期用）
if [ "${1:-}" = "--once" ]; then
    run_sync_cycle
    exit 0
fi

echo "Watching for Claude Code / Codex session changes (multi-session mode)..."
echo "Saving to: $OBSIDIAN_DIR/<project-name>/<date>[/<branch-label>].md"

# Initial cleanup
cleanup_old_state

loop_count=0

while true; do
    run_sync_cycle

    # 720ループ（5秒間隔で約1時間）ごとにメンテナンス処理を実行する
    # KeepAliveで数週間常駐し続けるため、起動時1回だけでは
    # 古いstateファイルの掃除も新規ghq cloneの反映もされない
    loop_count=$((loop_count + 1))
    if [ $((loop_count % 720)) -eq 0 ]; then
        cleanup_old_state
        refresh_ghq_owners
        rotate_logs
    fi

    sleep 5
done
