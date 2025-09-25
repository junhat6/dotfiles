-- Luaモジュールキャッシュ機能 起動を少し高速化
pcall(function()
	vim.loader.enable()
end)

require("colors")
require("options")
require("keymaps")
require("plugins")
require("lsp")
require("format")
require("statusline")
