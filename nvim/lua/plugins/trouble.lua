require("trouble").setup()

vim.keymap.set("n", "<leader>pt", "<cmd>Trouble diagnostics toggle<cr>")
