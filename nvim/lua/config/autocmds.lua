-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

-- Claude Code連携用の自動保存設定
-- フォーカスを失った時に自動保存（Claude Codeに切り替えた時など）
vim.api.nvim_create_autocmd("FocusLost", {
  pattern = "*",
  callback = function()
    vim.cmd("silent! wall")
  end,
})

-- フォーカスを取り戻した時に外部変更をチェック（Claude Codeが編集した後など）
vim.api.nvim_create_autocmd("FocusGained", {
  pattern = "*",
  callback = function()
    vim.cmd("checktime")
  end,
})
