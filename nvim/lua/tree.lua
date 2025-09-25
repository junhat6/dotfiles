require("neo-tree").setup({
	close_if_last_window = true, -- Neo-treeだけ残ってたら自動で閉じる
	filesystem = {
		follow_current_file = true, -- 現在開いてるファイルをツリーで自動ハイライト
		hijack_netrw = true, -- 標準のnetrwを置き換え
	},
})

-- トグル用キーマップ
vim.keymap.set("n", "<leader>e", ":Neotree toggle left<CR>", { silent = true, desc = "Toggle file explorer" })
