vim.g.mapleader = " "
vim.keymap.set("n", "<leader>j", vim.cmd.Ex)
vim.keymap.set({ "n", "v", "x" }, "<leader>y", '"+y<CR>')
vim.keymap.set("n", "<leader>f", function()
	require("conform").format({ async = true })
end, { silent = true })
