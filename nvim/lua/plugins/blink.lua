require("blink.cmp").setup({
	keymap = {
		preset = "default",
		["<S-Tab>"] = { "select_prev", "fallback_to_mappings" },
		["<Tab>"] = { "select_next", "fallback_to_mappings" },
		["<CR>"] = { "accept", "fallback" },
	},
	appearance = {
		nerd_font_variant = "mono",
	},
	completion = { documentation = { auto_show = false } },
	sources = {
		default = { "lsp", "path", "snippets" },
	},
	fuzzy = { implementation = "lua" },
	-- fuzzy = { implementation = "prefer_rust_with_warning" }
})
