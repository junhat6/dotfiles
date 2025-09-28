vim.g.mapleader = " "
vim.keymap.set({ "n", "v", "x" }, "<leader>y", '"+y<CR>')

-- :q :wなどのコマンド系
vim.keymap.set("n", "<leader>q", "<cmd>q<CR>", { desc = "Close window" })
vim.keymap.set("n", "<leader>Q", "<cmd>qa<CR>", { desc = "Quit all" })
vim.keymap.set("n", "<leader>o", "<cmd>only<CR>", { desc = "Close other windows" })
vim.keymap.set("n", "<leader>w", "<cmd>w<CR>", { desc = "Save file" })

-- ウィンドウ移動
vim.keymap.set("n", "<C-h>", "<C-w>h", { desc = "Move to left window" })
vim.keymap.set("n", "<C-l>", "<C-w>l", { desc = "Move to right window" })
vim.keymap.set("n", "<C-j>", "<C-w>j", { desc = "Move to lower window" })
vim.keymap.set("n", "<C-k>", "<C-w>k", { desc = "Move to upper window" })
