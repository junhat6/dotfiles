#!/bin/bash
# Watch Claude Code / Codex sessions and sync to Obsidian in real-time (append mode)
# Supports multiple concurrent sessions with project/date/session organization
#
# 出力構造:
#   Claude: <OBSIDIAN_DIR>/<repo>/<開始日>/<開始時刻> <タイトル> [Claude] <ID>.md
#   Codex:  <CODEX_OBSIDIAN_DIR>/<repo>/<開始日>/<開始時刻> <タイトル> [Codex] <ID>.md
#   ブランチと Issue はノートのメタデータに記録する。
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

# 2つの vault のうち、この Mac で GitHub に push する側へ保存する。
# 書き手が未設定／重複している間は誤った vault に書かずに停止する。
if [ -z "${OBSIDIAN_DIR:-}" ]; then
    WRITER_VAULT=$(python3 - "$HOME/ghq/github.com/junhat6" <<'PY'
import json
import pathlib
import subprocess
import sys

base = pathlib.Path(sys.argv[1])
vaults = []
for setup in sorted(base.glob("*/setup/obsidian-git-role.py")):
    vault = setup.parent.parent
    settings = vault / ".obsidian/plugins/obsidian-git/data.json"
    if not settings.is_file():
        continue
    try:
        origin = subprocess.check_output(
            ["git", "-C", str(vault), "remote", "get-url", "origin"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
        role = json.loads(settings.read_text()).get("disablePush")
    except (OSError, ValueError, subprocess.CalledProcessError):
        continue
    vaults.append((vault, origin, role))
if len(vaults) != 2 or len({origin for _, origin, _ in vaults}) != 2:
    sys.exit("Expected two distinct configured Obsidian vaults before session capture; set OBSIDIAN_DIR explicitly to override.")
writers = [vault for vault, _, role in vaults if role is False]
readers = [vault for vault, _, role in vaults if role is True]
if len(writers) != 1 or len(readers) != 1:
    sys.exit("Expected one writable and one read-only Obsidian vault. Run setup/obsidian-git-role.py in both vaults or set OBSIDIAN_DIR explicitly.")
print(writers[0])
PY
    ) || exit 1
    OBSIDIAN_DIR="$WRITER_VAULT/claude"
fi
CODEX_OBSIDIAN_DIR="${CODEX_OBSIDIAN_DIR:-$(dirname "$OBSIDIAN_DIR")/Codex}"
SESSION_DIR="${SESSION_DIR:-$HOME/.claude/projects}"
CODEX_SESSION_DIR="${CODEX_SESSION_DIR:-$HOME/.codex/sessions}"
SYNC_STATE_DIR="${SYNC_STATE_DIR:-$HOME/.claude/sync-state}"  # セッションごとの同期状態を保存
LOG_DIR="$HOME/.claude/logs"                # LaunchAgentのStandardOut/ErrorPath先
MAX_LOG_BYTES=$((10 * 1024 * 1024))         # このサイズを超えたら切り詰める
LOG_KEEP_LINES=5000                         # 切り詰め後に残す行数
TITLE_CACHE_DIR="$SYNC_STATE_DIR/issue-titles"  # Issue タイトルのキャッシュ
CODEX_STATE_DB="${CODEX_STATE_DB:-$HOME/.codex/state_5.sqlite}"

mkdir -p "$OBSIDIAN_DIR" "$CODEX_OBSIDIAN_DIR" "$SYNC_STATE_DIR" "$TITLE_CACHE_DIR"

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
    printf '%s' "$1" | tr '\n\r\t' '   ' | tr '/\\:|#^[]?*"<>' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//' | cut -c1-60
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

# ソースの最初の timestamp をローカル日時へ変換する。日付は再開後も変えない。
get_session_start() {
    local timestamp
    timestamp=$(head -100 "$1" | jq -R -r '(try fromjson catch empty) | .timestamp // empty' 2>/dev/null | head -1)
    python3 - "$timestamp" "$1" <<'PY'
import datetime
import os
import sys

try:
    started = datetime.datetime.fromisoformat(sys.argv[1].replace("Z", "+00:00"))
    if started.tzinfo is None:
        started = started.replace(tzinfo=datetime.timezone.utc)
    started = started.astimezone()
except ValueError:
    started = datetime.datetime.fromtimestamp(os.path.getmtime(sys.argv[2]))
print(f"{started.year}年{started.month}月{started.day}日\t{started:%H%M}\t{started:%Y-%m-%d}")
PY
}

get_codex_title() {
    local session_id="$1" session_file="$2" title=""
    # Codex アプリの表示名。name がまだ無ければ title（初回プロンプト）を使う。
    if [[ "$session_id" =~ ^[0-9a-f-]{36}$ ]] && [ -f "$CODEX_STATE_DB" ] && command -v sqlite3 >/dev/null 2>&1; then
        title=$(sqlite3 -readonly "$CODEX_STATE_DB" \
            "SELECT COALESCE(NULLIF(name, ''), NULLIF(title, ''), '') FROM threads WHERE id = '$session_id' LIMIT 1;" 2>/dev/null)
    fi
    if [ -z "$title" ]; then
        title=$(head -100 "$session_file" | jq -R -r '
            (try fromjson catch empty) |
            if .type == "event_msg" and .payload.type == "user_message" then
                .payload.message // empty
            elif .type == "response_item" and .payload.type == "message" and .payload.role == "user" then
                .payload.content[]? | select(.type == "input_text") |
                .text // empty |
                select(test("^\\s*<(environment_context|codex_internal_context|system-reminder|system_reminder)\\b"; "i") | not)
            else empty end' 2>/dev/null | head -1)
    fi
    printf '%s' "$title"
}

update_note_heading() {
    python3 - "$1" "$2" <<'PY'
import os
import sys
import tempfile

path, title = sys.argv[1:]
fd, temporary = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".session-title-")
try:
    with open(path, encoding="utf-8") as source, os.fdopen(fd, "w", encoding="utf-8") as target:
        changed = False
        for line in source:
            if not changed and line.startswith("# "):
                target.write(f"# {title}\n")
                changed = True
            else:
                target.write(line)
    os.replace(temporary, path)
finally:
    if os.path.exists(temporary):
        os.unlink(temporary)
PY
}

get_claude_title() {
    local previous_type="$1" session_file="$2" last_line="$3" current_lines="$4"
    local custom ai
    custom=$(head -n "$current_lines" "$session_file" | tail -n +$((last_line + 1)) | jq -R -r '
        (try fromjson catch empty) | select(.type == "custom-title") | .customTitle // empty' 2>/dev/null | tail -1)
    if [ -n "$custom" ]; then
        printf 'custom\t%s\n' "$custom"
        return
    fi
    if [ "$previous_type" = "custom" ]; then
        return
    fi
    ai=$(head -n "$current_lines" "$session_file" | tail -n +$((last_line + 1)) | jq -R -r '
        (try fromjson catch empty) | select(.type == "ai-title") | .aiTitle // empty' 2>/dev/null | tail -1)
    if [ -n "$ai" ]; then
        printf 'ai\t%s\n' "$ai"
    fi
}

# フォーマット別: チャンクから cwd/branch/repo_url を TSV 3列で抽出する jq フィルタ
META_JQ_CLAUDE='(try fromjson catch empty) | select(.cwd) | [.cwd, (.gitBranch // ""), ""] | @tsv'
META_JQ_CODEX='(try fromjson catch empty) | select(.type == "session_meta") | [.payload.cwd, (.payload.git.branch // ""), (.payload.git.repository_url // "")] | @tsv'

sync_session() {
    local session_file="$1"
    local format="$2"   # claude | codex

    # セッション固有の同期状態ファイル
    local session_hash=$(get_session_hash "$session_file")
    # 旧集約ノートとカーソルを分離し、切替時に全会話を新しいノートへ記録する。
    local STATE_PREFIX="${SYNC_STATE_DIR}/${session_hash}.v2"
    local LAST_LINE_FILE="${STATE_PREFIX}.cursor"
    local META_FILE="${STATE_PREFIX}.meta"
    local NOTE_FILE="${STATE_PREFIX}.note"
    local START_FILE="${STATE_PREFIX}.start"
    local TITLE_FILE="${STATE_PREFIX}.title"
    local TITLE_TYPE_FILE="${STATE_PREFIX}.title-type"

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
    if [ -f "$NOTE_FILE" ] && [ ! -f "$(cat "$NOTE_FILE")" ]; then
        # 既存ノートが無い場合は、本文を失わないよう最初から再構築する。
        last_line=0
    fi

    # Count current lines in session file
    local current_lines=$(wc -l < "$session_file" | tr -d ' ')

    # Only process new lines (append mode - no overwriting)
    if [ "$current_lines" -lt "$last_line" ] || { [ "$current_lines" -eq "$last_line" ] && [ "$format" != "codex" ]; }; then
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

    local start_info
    if [ -f "$START_FILE" ]; then
        start_info=$(cat "$START_FILE")
    else
        start_info=$(get_session_start "$session_file")
        printf '%s\n' "$start_info" > "$START_FILE"
    fi
    local session_date start_time created_at
    IFS=$'\t' read -r session_date start_time created_at <<< "$start_info"

    local session_id agent
    if [ "$format" = "codex" ]; then
        session_id=$(head -1 "$session_file" | jq -r '.payload.id // empty' 2>/dev/null)
        agent="Codex"
    else
        session_id=$(basename "$session_file" .jsonl)
        agent="Claude"
    fi
    [ -n "$session_id" ] || session_id="$session_hash"

    local title="" title_type="" title_update=""
    [ -f "$TITLE_FILE" ] && title=$(cat "$TITLE_FILE")
    [ -f "$TITLE_TYPE_FILE" ] && title_type=$(cat "$TITLE_TYPE_FILE")
    if [ "$format" = "codex" ]; then
        title_update=$(get_codex_title "$session_id" "$session_file")
        [ -n "$title_update" ] && title="$title_update"
    else
        # 初回は全行、以後は差分からタイトル変更を探す。
        title_update=$(get_claude_title "$title_type" "$session_file" "$last_line" "$current_lines")
        if [ -n "$title_update" ]; then
            title_type=${title_update%%$'\t'*}
            title=${title_update#*$'\t'}
            printf '%s\n' "$title_type" > "$TITLE_TYPE_FILE"
        fi
    fi
    [ -n "$title" ] || title="無題のセッション"
    title=$(sanitize_label "$title")
    [ -n "$title" ] || title="無題のセッション"
    printf '%s\n' "$title" > "$TITLE_FILE"

    local output_root="$OBSIDIAN_DIR"
    [ "$format" = "codex" ] && output_root="$CODEX_OBSIDIAN_DIR"
    local project_dir="${output_root}/${project_name}/${session_date}"
    local short_id="${session_id:0:8}"
    local OUTPUT_FILE="${project_dir}/${start_time} ${title} [${agent}] ${short_id}.md"
    if [ -f "$NOTE_FILE" ]; then
        local previous_note
        previous_note=$(cat "$NOTE_FILE")
        if [ "$previous_note" != "$OUTPUT_FILE" ] && [ -f "$previous_note" ] && [ ! -e "$OUTPUT_FILE" ]; then
            mkdir -p "$project_dir"
            mv "$previous_note" "$OUTPUT_FILE"
            update_note_heading "$OUTPUT_FILE" "$title"
        fi
    fi

    # current_lines算出後にファイルが追記される可能性があるため、tailではなく
    # head -n current_lines で読む範囲をカウント時点に固定する（レースで重複書き込みを防ぐ）
    # -R + try/catchで壊れたJSON行を1行単位でスキップし、バッチ中の1行の破損で
    # それ以降の行が全て失われないようにする
    local new_content jq_status
    if [ "$format" = "codex" ]; then
        # 現行 Codex は response_item.message、旧形式は event_msg に会話がある。
        local codex_chat_source="event_msg"
        if head -100 "$session_file" | jq -R -e '
            (try fromjson catch empty) |
            select(.type == "response_item" and .payload.type == "message" and .payload.role == "user")' >/dev/null 2>&1; then
            codex_chat_source="response_item"
        fi
        new_content=$(head -n "$current_lines" "$session_file" | tail -n +$((last_line + 1)) | jq -R -r --arg source "$codex_chat_source" '
            (try fromjson catch empty) |
            if $source == "response_item" then
                select(.type == "response_item" and .payload.type == "message") |
                if .payload.role == "user" then
                    .payload.content[]? | select(.type == "input_text") |
                    select(.text | test("^\\s*<(environment_context|codex_internal_context|system-reminder|system_reminder)\\b"; "i") | not) |
                    "**ユーザー**: " + (.text | rtrimstr("\n")) + "\n"
                elif .payload.role == "assistant" then
                    .payload.content[]? | select(.type == "output_text") |
                    "**Codex**: " + (.text | rtrimstr("\n")) + "\n"
                else empty end
            else
                select(.type == "event_msg") |
                if .payload.type == "user_message" then
                    "**ユーザー**: " + (.payload.message | rtrimstr("\n")) + "\n"
                elif .payload.type == "agent_message" then
                    "**Codex**: " + (.payload.message | rtrimstr("\n")) + "\n"
                else empty end
            end')
        jq_status=$?
    else
        new_content=$(head -n "$current_lines" "$session_file" | tail -n +$((last_line + 1)) | jq -R -r '
        (try fromjson catch empty) |
        select(.type == "user" or .type == "assistant") |
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
            {
                echo "---"
                echo "tags: [ai-session, ${format}]"
                echo "created: ${created_at}"
                echo "agent: ${agent}"
                printf 'session_id: %s\n' "$session_id"
                [ -n "$branch" ] && printf 'branch: %s\n' "$(printf '%s' "$branch" | jq -Rsa .)"
                echo "---"
                echo ""
                echo "# ${title}"
                echo ""
                local label
                label=$(get_branch_label "$project_name" "$branch" "$cwd" "$repo_url")
                if [[ "$label" =~ ^([0-9]+)[[:space:]] ]]; then
                    local num="${BASH_REMATCH[1]}"
                    local slug_file="$TITLE_CACHE_DIR/${project_name}#${num}.slug"
                    if [ -f "$slug_file" ]; then
                        echo "Issue: [#${num}](https://github.com/$(cat "$slug_file")/issues/${num})"
                        echo ""
                    fi
                fi
            } > "$OUTPUT_FILE"
        fi

        printf '%s\n' "$new_content" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"

        # Git commit はObsidian Gitプラグインに任せる
    fi

    printf '%s\n' "$OUTPUT_FILE" > "$NOTE_FILE"

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

# 旧版で claude/ に置いた Codex のセッション別ノートだけを Codex/ へ移す。
# 同期状態のパスも同時に更新し、次の追記が元のノートへ続くようにする。
migrate_codex_notes() {
    local pointer old relative target
    while IFS= read -r pointer; do
        old=$(cat "$pointer")
        case "$old" in
            "$OBSIDIAN_DIR"/*"[Codex]"*.md) ;;
            *) continue ;;
        esac
        relative=${old#"$OBSIDIAN_DIR"/}
        target="$CODEX_OBSIDIAN_DIR/$relative"
        if [ -f "$old" ] && [ ! -e "$target" ]; then
            mkdir -p "$(dirname "$target")"
            mv "$old" "$target" || continue
            printf '%s\n' "$target" > "$pointer"
        elif [ -f "$target" ] && [ ! -f "$old" ]; then
            printf '%s\n' "$target" > "$pointer"
        elif [ -f "$old" ] && [ -e "$target" ]; then
            echo "[ERROR] Codex note already exists at both paths: $old / $target" >&2
        fi
    done < <(find "$SYNC_STATE_DIR" -name '*.v2.note' -type f -print 2>/dev/null)
}

migrate_codex_notes

# --once: 1回同期して終了（テスト・手動同期用）
if [ "${1:-}" = "--once" ]; then
    run_sync_cycle
    exit 0
fi

echo "Watching for Claude Code / Codex session changes (multi-session mode)..."
echo "Saving Claude to: $OBSIDIAN_DIR/<project-name>/<session-start-date>/<time> <title> [Claude] <id>.md"
echo "Saving Codex to: $CODEX_OBSIDIAN_DIR/<project-name>/<session-start-date>/<time> <title> [Codex] <id>.md"

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
