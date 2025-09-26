---@diagnostic disable-next-line: missing-fields, param-type-mismatch
require("telescope-all-recent").setup({
	default = { disable = true }, -- 未知のピッカーは無効（推奨）
	pickers = { find_files = { disable = false, sorting = "frecency" } },
})

-- fzf-native をロード（最小）
pcall(function()
	require("telescope").load_extension("fzf")
end)

-- UI改善プラグイン　依存関係で入れといた
require("dressing").setup()

-- キーマップは関数ラップで
vim.keymap.set("n", "<leader>pf", function()
	require("telescope.builtin").find_files()
end, { desc = "Telescope find files" })

vim.keymap.set("n", "<leader>pg", function()
	require("telescope.builtin").live_grep()
end, { desc = "Telescope live grep" })

vim.keymap.set("n", "<leader>sd", vim.diagnostic.open_float, { desc = "Show diagnostics" })
