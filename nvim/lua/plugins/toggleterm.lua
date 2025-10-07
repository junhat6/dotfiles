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
