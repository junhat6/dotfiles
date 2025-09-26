vim.pack.add({
	-- LSP
	{ src = "https://github.com/neovim/nvim-lspconfig" },
	{ src = "https://github.com/mason-org/mason.nvim" },
	{ src = "https://github.com/mason-org/mason-lspconfig.nvim" },
	{ src = "https://github.com/WhoIsSethDaniel/mason-tool-installer.nvim" },

	-- Formatting
	{ src = "https://github.com/stevearc/conform.nvim" },

	-- UI
	{ src = "https://github.com/nvim-lualine/lualine.nvim" },
	{ src = "https://github.com/romgrk/barbar.nvim" },
	{ src = "https://github.com/nvim-neo-tree/neo-tree.nvim" },
	{ src = "https://github.com/shellRaining/hlchunk.nvim" },
	{ src = "https://github.com/akinsho/toggleterm.nvim" },

	-- Dependencies
	{ src = "https://github.com/nvim-lua/plenary.nvim" },
	{ src = "https://github.com/nvim-tree/nvim-web-devicons" },
	{ src = "https://github.com/MunifTanjim/nui.nvim" },

	-- git
	{ src = "https://github.com/lewis6991/gitsigns.nvim" },
})
