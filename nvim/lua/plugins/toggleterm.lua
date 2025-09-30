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
	size = function(term)
		if term.direction == "horizontal" then
			return 8 -- 横分割の高さ
		elseif term.direction == "vertical" then
			return 40 -- 縦分割の幅
		end
	end,

	start_in_insert = true, -- 開いたら挿入モード
	persist_mode = true, -- モードを維持
	close_on_exit = true,
	shade_terminals = false,
	hide_numbers = true,
})

-- keymaps
vim.keymap.set("n", "<leader>t", "<cmd>ToggleTerm direction=horizontal<CR>", { desc = "Terminal horizontal" })
vim.keymap.set("n", "<leader>r", "<cmd>ToggleTerm direction=vertical<CR>", { desc = "Terminal vertical" })

-- ─────────────────────────────────────────────────────────────
-- Terminalモード固定: Escや<C-\><C-n>でノーマルに戻れないようにする
-- かつ、Terminalモードのままウィンドウ移動できるようにする
-- ─────────────────────────────────────────────────────────────
local function set_term_keymaps()
	local opts = { buffer = 0, silent = true, noremap = true }

	-- (重要) ノーマルに戻す操作を潰す
	-- Esc はそのまま端末アプリに送る（ノーマルに戻さない）
	vim.keymap.set("t", "<Esc>", "<Esc>", opts)
	-- Ctrl-\ Ctrl-n を完全に無効化（ノーマルに戻れない）
	vim.keymap.set("t", [[<C-\><C-n>]], "<Nop>", opts)

	-- Terminalモードのままウィンドウ移動（:wincmd を直接叩く）
	vim.keymap.set("t", "<C-h>", "<Cmd>wincmd h<CR>", opts)
	vim.keymap.set("t", "<C-j>", "<Cmd>wincmd j<CR>", opts)
	vim.keymap.set("t", "<C-k>", "<Cmd>wincmd k<CR>", opts)
	vim.keymap.set("t", "<C-l>", "<Cmd>wincmd l<CR>", opts)

	-- 念のため、ターミナルに入ったら常に挿入モードへ
	vim.cmd("startinsert")
end

vim.api.nvim_create_autocmd("TermOpen", {
	pattern = "term://*",
	callback = set_term_keymaps,
})
