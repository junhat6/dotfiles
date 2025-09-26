require("lualine").setup({
	options = {
		theme = "tokyonight", -- カラースキームに合わせる
		globalstatus = true, -- laststatus = 3 と連動
	},
	sections = {
		lualine_a = { "mode" }, -- モード (NORMAL/INSERT など)
		lualine_b = { "branch", "diff" }, -- Gitブランチ / 差分
		lualine_c = { "filename" }, -- ファイル名
		lualine_x = { "encoding", "filetype" },
		lualine_y = { "progress" }, -- 進行率 (%)
		lualine_z = { "location" }, -- 行:列
	},
})
