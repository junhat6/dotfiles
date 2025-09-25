vim.g.mapleader = " "
vim.keymap.set("n", "<leader>j", vim.cmd.Ex)
vim.keymap.set({ "n", "v", "x" }, "<leader>y", '"+y<CR>')
vim.keymap.set("n", "<leader>q", "<cmd>q<CR>", { desc = "Close window" })
vim.keymap.set("n", "<leader>Q", "<cmd>qa<CR>", { desc = "Quit all" })
vim.keymap.set("n", "<leader>o", "<cmd>only<CR>", { desc = "Close other windows" })
vim.keymap.set("n", "<leader>w", "<cmd>w<CR>", { desc = "Save file" })
