-- barbar.nvim の基本設定
vim.g.barbar_auto_setup = false -- 自動セットアップを無効化
require("barbar").setup({
	animation = true, -- バッファ移動時にアニメーション
	auto_hide = false, -- バッファが1つでもタブラインを表示
	clickable = true, -- マウスクリックでバッファ切替/閉じる
	icons = {
		buffer_index = true, -- タブ番号を表示
		diagnostics = {
			[vim.diagnostic.severity.ERROR] = { enabled = true, icon = " " },
			[vim.diagnostic.severity.WARN] = { enabled = true, icon = " " },
			[vim.diagnostic.severity.INFO] = { enabled = true, icon = " " },
			[vim.diagnostic.severity.HINT] = { enabled = true, icon = " " },
		},
	},
})
-- バッファ切り替え
vim.keymap.set("n", "<A-,>", "<Cmd>BufferPrevious<CR>", { desc = "Previous buffer" })
vim.keymap.set("n", "<A-.>", "<Cmd>BufferNext<CR>", { desc = "Next buffer" })

-- バッファ並べ替え
vim.keymap.set("n", "<A-<>", "<Cmd>BufferMovePrevious<CR>", { desc = "Move buffer left" })
vim.keymap.set("n", "<A->>", "<Cmd>BufferMoveNext<CR>", { desc = "Move buffer right" })

-- バッファを閉じる
vim.keymap.set("n", "<A-c>", "<Cmd>BufferClose<CR>", { desc = "Close buffer" })

-- 直接番号で切り替え (例: Alt+1 でバッファ1)
for i = 1, 9 do
	vim.keymap.set("n", "<A-" .. i .. ">", "<Cmd>BufferGoto " .. i .. "<CR>", { desc = "Go to buffer " .. i })
end
