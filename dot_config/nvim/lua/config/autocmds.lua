-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

-- 外部変更を積極的にチェック（Claude Codeが編集した後など）
vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold", "CursorHoldI" }, {
  pattern = "*",
  callback = function()
    if vim.fn.mode() ~= "c" then
      vim.cmd("checktime")
    end
  end,
})

-- 日本語など非ASCII文字をスペルチェック対象から除外する
-- LazyVim は markdown / gitcommit / text などで spell=true を有効化するため、
-- そのままだと treesitter の @spell キャプチャ経由で日本語にも赤線が引かれる。
-- 非ASCII連続部分を @NoSpell クラスタに入れることで、英語のスペルチェックは
-- 維持しつつ日本語だけ除外する。
vim.api.nvim_create_autocmd({ "BufWinEnter", "FileType", "Syntax" }, {
  group = vim.api.nvim_create_augroup("nospell_non_ascii", { clear = true }),
  pattern = "*",
  callback = function()
    vim.cmd([[syntax match NonAsciiNoSpell /[^\x00-\x7F]\+/ contains=@NoSpell containedin=ALL transparent]])
  end,
})
