-- 行番号　余白関連
vim.opt.number = true
vim.opt.signcolumn = "yes"
vim.opt.scrolloff = 6

-- カーソルライン
vim.opt.cursorline = true
vim.opt.cursorlineopt = "number"

-- インデント・タブ関連
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true
vim.opt.smartindent = true
vim.opt.list = true -- 不可視文字の可視化
vim.opt.listchars = { tab = "» ", trail = "·", extends = "›", precedes = "‹" }

-- ウィンドウ表示
vim.opt.winborder = "single"
vim.opt.termguicolors = true
vim.opt.splitright = true -- vsplitは右に
vim.opt.splitbelow = true -- splitは下に

-- 検索の使い勝手
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.incsearch = true
-- 入力レスポンス
vim.opt.updatetime = 300 -- CursorHold/diagnosticsの反応を速く
vim.opt.timeoutlen = 600

-- === クリップボード / 保存まわり ===
vim.opt.clipboard = "unnamedplus" -- OSクリップボード共有
vim.opt.undofile = true -- 永続Undo
