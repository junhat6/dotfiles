-- =============================================================================
-- WezTerm configuration
-- https://wezterm.org/config/files.html
-- =============================================================================

local wezterm = require("wezterm")
local act = wezterm.action
local config = wezterm.config_builder()
config.automatically_reload_config = true

-- 右ステータスに現在のキーテーブル名を表示（copy_mode 等に入っているか分かる）
wezterm.on("update-right-status", function(window, _pane)
	local name = window:active_key_table()
	if name then
		name = "TABLE: " .. name
	end
	window:set_right_status(name or "")
end)

-- --- フォント ---
config.font = wezterm.font("UDEV Gothic NF")
config.font_size = 18.0

-- --- ウィンドウ ---
config.window_padding = {
	left = 5,
	right = 5,
	top = 5,
	bottom = 5,
}
config.hide_tab_bar_if_only_one_tab = true

-- 枠（タイトルバー/信号機ボタン）を消す。リサイズだけ可能。
-- 背景色は color_scheme（Catppuccin Latte）に任せる。
config.window_decorations = "RESIZE"

-- --- テーマ ---
config.color_scheme = "Catppuccin Latte"

-- --- タブバー ---
-- フラットな retro タブバーを使い、+（新規タブ）と × （閉じる）ボタンを消す。
config.use_fancy_tab_bar = false
config.show_new_tab_button_in_tab_bar = false
config.show_close_tab_button_in_tabs = false
config.tab_max_width = 32

-- Catppuccin Latte 系の配色。
-- 非アクティブタブはバー背景と同色にして境界線（edge）を消し、
-- アクティブタブだけアクセント色（mauve）で目立たせる。
-- colors は color_scheme にマージされるので tab_bar 以外は据え置き。
config.colors = {
	tab_bar = {
		background = "#e6e9ef", -- mantle: バー全体
		active_tab = {
			bg_color = "#8839ef", -- mauve: アクティブだけ強調
			fg_color = "#eff1f5", -- base
		},
		inactive_tab = {
			bg_color = "#e6e9ef", -- バーと同色 → 境界が消える
			fg_color = "#6c6f85", -- subtext0
		},
		inactive_tab_hover = {
			bg_color = "#dce0e8", -- crust: ホバー時だけうっすら
			fg_color = "#4c4f69", -- text
		},
	},
}

-- --- カーソル ---
config.default_cursor_style = "BlinkingBlock"

-- --- macOS: 左 Option を Alt として扱う
-- false = Option を「文字合成(é など)」ではなく Alt/Meta 修飾キーとして使う。
-- これがないと Alt 系キーバインドが効かない。
config.send_composed_key_when_left_alt_is_pressed = false
config.send_composed_key_when_right_alt_is_pressed = true

config.leader = { key = "a", mods = "CTRL", timeout_milliseconds = 1000 }

config.keys = {
	-- =========================================================
	-- LEADER (Ctrl-a) 系：マルチプレクサ操作
	-- =========================================================
	-- ペイン分割：\ = 左右 / - = 上下
	{ key = "\\", mods = "LEADER", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
	{ key = "-", mods = "LEADER", action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },

	-- vi スタイルのペイン移動
	{ key = "h", mods = "LEADER", action = act.ActivatePaneDirection("Left") },
	{ key = "j", mods = "LEADER", action = act.ActivatePaneDirection("Down") },
	{ key = "k", mods = "LEADER", action = act.ActivatePaneDirection("Up") },
	{ key = "l", mods = "LEADER", action = act.ActivatePaneDirection("Right") },

	-- ペインリサイズ
	{ key = "H", mods = "LEADER", action = act.AdjustPaneSize({ "Left", 5 }) },
	{ key = "J", mods = "LEADER", action = act.AdjustPaneSize({ "Down", 5 }) },
	{ key = "K", mods = "LEADER", action = act.AdjustPaneSize({ "Up", 5 }) },
	{ key = "L", mods = "LEADER", action = act.AdjustPaneSize({ "Right", 5 }) },

	-- ペインを閉じる / ズーム（全画面化はもう一度押すと戻る）
	{ key = "x", mods = "LEADER", action = act.CloseCurrentPane({ confirm = true }) },
	{ key = "z", mods = "LEADER", action = act.TogglePaneZoomState },

	-- コピーモード / QuickSelect（URL・パス・ハッシュにラベルを振って飛ぶ）
	{ key = "[", mods = "LEADER", action = act.ActivateCopyMode },
	{ key = "f", mods = "LEADER", action = act.QuickSelect },

	-- スクロールバックのクリア
	{ key = "K", mods = "LEADER|SHIFT", action = act.ClearScrollback("ScrollbackAndViewport") },

	-- --- workspace（tmux のセッション相当）---
	-- 切り替え
	{ key = "w", mods = "LEADER", action = act.ShowLauncherArgs({ flags = "WORKSPACES", title = "Select workspace" }) },
	-- 現在の workspace 名を変更
	{
		key = "$",
		mods = "LEADER",
		action = act.PromptInputLine({
			description = "(wezterm) Set workspace title:",
			action = wezterm.action_callback(function(_win, _pane, line)
				if line then
					wezterm.mux.rename_workspace(wezterm.mux.get_active_workspace(), line)
				end
			end),
		}),
	},
	-- 新規 workspace を作成して移動
	{
		key = "W",
		mods = "LEADER|SHIFT",
		action = act.PromptInputLine({
			description = "(wezterm) Create new workspace:",
			action = wezterm.action_callback(function(window, pane, line)
				if line then
					window:perform_action(act.SwitchToWorkspace({ name = line }), pane)
				end
			end),
		}),
	},

	-- =========================================================
	-- SUPER (⌘) 系：macOS アプリ標準の操作
	-- =========================================================
	-- タブ
	{ key = "t", mods = "SUPER", action = act.SpawnTab("CurrentPaneDomain") },
	{ key = "w", mods = "SUPER", action = act.CloseCurrentTab({ confirm = true }) },
	{ key = "1", mods = "SUPER", action = act.ActivateTab(0) },
	{ key = "2", mods = "SUPER", action = act.ActivateTab(1) },
	{ key = "3", mods = "SUPER", action = act.ActivateTab(2) },
	{ key = "4", mods = "SUPER", action = act.ActivateTab(3) },
	{ key = "5", mods = "SUPER", action = act.ActivateTab(4) },
	{ key = "6", mods = "SUPER", action = act.ActivateTab(5) },
	{ key = "7", mods = "SUPER", action = act.ActivateTab(6) },
	{ key = "8", mods = "SUPER", action = act.ActivateTab(7) },
	{ key = "9", mods = "SUPER", action = act.ActivateTab(-1) }, -- 最後のタブ

	-- タブ順送り：Chrome 準拠（Ctrl+Tab / Ctrl+Shift+Tab）と Alt+h/l の併用
	{ key = "Tab", mods = "CTRL", action = act.ActivateTabRelative(1) },
	{ key = "Tab", mods = "CTRL|SHIFT", action = act.ActivateTabRelative(-1) },
	{ key = "h", mods = "ALT", action = act.ActivateTabRelative(-1) },
	{ key = "l", mods = "ALT", action = act.ActivateTabRelative(1) },

	-- コピー / 貼り付け
	{ key = "c", mods = "SUPER", action = act.CopyTo("Clipboard") },
	{ key = "v", mods = "SUPER", action = act.PasteFrom("Clipboard") },

	-- フォントサイズ（⌘ + / - / 0）
	{ key = "=", mods = "SUPER", action = act.IncreaseFontSize },
	{ key = "-", mods = "SUPER", action = act.DecreaseFontSize },
	{ key = "0", mods = "SUPER", action = act.ResetFontSize },

	-- コマンドパレット（VSCode の ⌘⇧P と同じ位置）
	{ key = "p", mods = "SUPER|SHIFT", action = act.ActivateCommandPalette },

	-- 設定リロード / フルスクリーン
	{ key = "r", mods = "SUPER|SHIFT", action = act.ReloadConfiguration },
	{ key = "Enter", mods = "ALT", action = act.ToggleFullScreen },
}

-- =============================================================================
-- キーテーブル
-- https://wezterm.org/config/key-tables.html
-- =============================================================================
config.key_tables = {
	-- コピーモード（LEADER + [ で起動）：vim 風操作
	copy_mode = {
		-- 移動
		{ key = "h", mods = "NONE", action = act.CopyMode("MoveLeft") },
		{ key = "j", mods = "NONE", action = act.CopyMode("MoveDown") },
		{ key = "k", mods = "NONE", action = act.CopyMode("MoveUp") },
		{ key = "l", mods = "NONE", action = act.CopyMode("MoveRight") },
		-- 行頭/行末（内容ベース）
		{ key = "^", mods = "NONE", action = act.CopyMode("MoveToStartOfLineContent") },
		{ key = "$", mods = "NONE", action = act.CopyMode("MoveToEndOfLineContent") },
		-- 行の左端
		{ key = "0", mods = "NONE", action = act.CopyMode("MoveToStartOfLine") },
		-- 選択の反対端へ
		{ key = "o", mods = "NONE", action = act.CopyMode("MoveToSelectionOtherEnd") },
		{ key = "O", mods = "NONE", action = act.CopyMode("MoveToSelectionOtherEndHoriz") },
		-- 直前のジャンプを繰り返す
		{ key = ";", mods = "NONE", action = act.CopyMode("JumpAgain") },
		-- 単語単位の移動
		{ key = "w", mods = "NONE", action = act.CopyMode("MoveForwardWord") },
		{ key = "b", mods = "NONE", action = act.CopyMode("MoveBackwardWord") },
		{ key = "e", mods = "NONE", action = act.CopyMode("MoveForwardWordEnd") },
		-- f/t ジャンプ
		{ key = "t", mods = "NONE", action = act.CopyMode({ JumpForward = { prev_char = true } }) },
		{ key = "f", mods = "NONE", action = act.CopyMode({ JumpForward = { prev_char = false } }) },
		{ key = "T", mods = "NONE", action = act.CopyMode({ JumpBackward = { prev_char = true } }) },
		{ key = "F", mods = "NONE", action = act.CopyMode({ JumpBackward = { prev_char = false } }) },
		-- スクロールバックの末尾/先頭へ
		{ key = "G", mods = "NONE", action = act.CopyMode("MoveToScrollbackBottom") },
		{ key = "g", mods = "NONE", action = act.CopyMode("MoveToScrollbackTop") },
		-- ビューポート内移動
		{ key = "H", mods = "NONE", action = act.CopyMode("MoveToViewportTop") },
		{ key = "L", mods = "NONE", action = act.CopyMode("MoveToViewportBottom") },
		{ key = "M", mods = "NONE", action = act.CopyMode("MoveToViewportMiddle") },
		-- スクロール
		{ key = "b", mods = "CTRL", action = act.CopyMode("PageUp") },
		{ key = "f", mods = "CTRL", action = act.CopyMode("PageDown") },
		{ key = "d", mods = "CTRL", action = act.CopyMode({ MoveByPage = 0.5 }) },
		{ key = "u", mods = "CTRL", action = act.CopyMode({ MoveByPage = -0.5 }) },
		-- 選択モード（v: セル / C-v: ブロック / V: 行）
		{ key = "v", mods = "NONE", action = act.CopyMode({ SetSelectionMode = "Cell" }) },
		{ key = "v", mods = "CTRL", action = act.CopyMode({ SetSelectionMode = "Block" }) },
		{ key = "V", mods = "NONE", action = act.CopyMode({ SetSelectionMode = "Line" }) },
		-- コピー
		{ key = "y", mods = "NONE", action = act.CopyTo("Clipboard") },
		-- 終了
		{
			key = "Enter",
			mods = "NONE",
			action = act.Multiple({ { CopyTo = "ClipboardAndPrimarySelection" }, { CopyMode = "Close" } }),
		},
		{ key = "Escape", mods = "NONE", action = act.CopyMode("Close") },
		{ key = "c", mods = "CTRL", action = act.CopyMode("Close") },
		{ key = "q", mods = "NONE", action = act.CopyMode("Close") },
	},
}

return config
