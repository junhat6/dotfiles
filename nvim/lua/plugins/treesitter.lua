pcall(function()
	require("nvim-treesitter.install").update({ with_sync = false })
end)
---@diagnostic disable-next-line: missing-fields
require("nvim-treesitter.configs").setup({
	ensure_installed = { "lua", "typescript", "javascript", "yaml", "json", "html", "css", "query" },
	sync_install = false,
	auto_install = true,
	highlight = {
		enable = true,
		additional_vim_regex_highlighting = false,
	},
	indent = { enable = true },
	textsubjects = { enable = true },
})

require("nvim-treesitter-textsubjects").configure({
	prev_selection = ",", -- ビジュアル選択から戻るキー（既定: ,）
	keymaps = {
		["."] = "textsubjects-smart",
	},
})
