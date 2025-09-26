require("hlchunk").setup({
	chunk = {
		enable = true,
		use_treesitter = true, -- Treesitterでブロック範囲を解析
		style = {
			{ fg = "#7aa2f7" }, -- 縦ラインの色（例: ゴールド）
		},
		exclude_filetypes = {
			"markdown",
			"help",
			"neo-tree",
			"dashboard",
		},
	},
	indent = {
		enable = false, -- インデント線はオフ
	},
	line_num = {
		enable = false, -- 行番号ハイライトもオフ
	},
})
