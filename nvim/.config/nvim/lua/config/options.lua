-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- 外部変更を自動で読み込む
vim.opt.autoread = true

-- CursorHold時間を短くする（ミリ秒）
vim.opt.updatetime = 250

-- コメント行で改行した時に自動でコメントリーダーを挿入しない
vim.opt.formatoptions:remove({ "r", "o" })

-- 絶対行番号を表示（相対行番号を無効化）
vim.opt.relativenumber = false
