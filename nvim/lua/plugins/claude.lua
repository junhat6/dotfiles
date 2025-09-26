require("claudecode").setup({
	-- Gitリポジトリのルートディレクトリを作業ディレクトリとして使用
	git_repo_cwd = true,
})

vim.keymap.set("n", "<leader>c", "<cmd>ClaudeCode<CR>", { desc = "Toggle Claude" })
vim.keymap.set({ "n", "v" }, "<leader>b", "<cmd>ClaudeCodeSend<CR>", { desc = "Send selection to Claude" })
vim.keymap.set("n", "<leader>n", "<cmd>ClaudeCodeDiffAccept<CR>", { desc = "Accept diff from Claude" })
