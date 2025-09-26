local ok, toggleterm = pcall(require, "toggleterm")
if not ok then
	return
end

toggleterm.setup({
	-- ★ Ctrl + \ で「最後に使ったターミナル」をトグル（開閉）
	open_mapping = [[<c-\>]],

	-- ★ デフォルトは横分割
	direction = "horizontal",

	-- 使い勝手系
	size = 12, -- 横分割の高さ(行)
	start_in_insert = true, -- 開いたら挿入モード
	persist_mode = true, -- モードを維持
	close_on_exit = true,
	shade_terminals = true,
	hide_numbers = true,
})

-- keymaps
vim.keymap.set("n", "<leader>t", "<cmd>ToggleTerm direction=horizontal<CR>", { desc = "Terminal horizontal" })
vim.keymap.set("n", "<leader>r", "<cmd>ToggleTerm direction=vertical size=80<CR>", { desc = "Terminal vertical" })

-- 端末内での操作を快適にするキー（ターミナルモード限定）
local function set_term_keymaps()
	local opts = { buffer = 0, silent = true }
	-- Esc / jk でノーマル戻り
	vim.keymap.set("t", "<esc>", [[<C-\><C-n>]], opts)
	-- 窓移動（Ctrl+h/j/k/l）
	vim.keymap.set("t", "<C-h>", [[<C-\><C-n><C-w>h]], opts)
	vim.keymap.set("t", "<C-j>", [[<C-\><C-n><C-w>j]], opts)
	vim.keymap.set("t", "<C-k>", [[<C-\><C-n><C-w>k]], opts)
	vim.keymap.set("t", "<C-l>", [[<C-\><C-n><C-w>l]], opts)
end
vim.api.nvim_create_autocmd("TermOpen", {
	pattern = "term://*",
	callback = set_term_keymaps,
})
