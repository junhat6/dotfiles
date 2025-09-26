vim.pack.add({
	-- ── Core dependencies（いろんなプラグインが使う土台） ───────────────
	{ src = "https://github.com/nvim-lua/plenary.nvim" },
	{ src = "https://github.com/nvim-tree/nvim-web-devicons" },
	{ src = "https://github.com/MunifTanjim/nui.nvim" }, -- neo-tree などで使用
	{ src = "https://github.com/kkharji/sqlite.lua" }, -- telescope-all-recent 用
	{ src = "https://github.com/nvim-treesitter/nvim-treesitter" },
	{ src = "https://github.com/RRethy/nvim-treesitter-textsubjects" },

	-- ── Telescope: 本体 → 拡張（依存→本体→拡張の順が◎） ─────────────
	{ src = "https://github.com/nvim-telescope/telescope.nvim" }, -- 本体
	{ src = "https://github.com/nvim-telescope/telescope-fzf-native.nvim" }, -- 高速ソーター（要: make）
	{ src = "https://github.com/prochri/telescope-all-recent.nvim" }, -- frecency/recency

	-- ── UI / UX（見た目や操作感） ──────────────────────────────
	{ src = "https://github.com/stevearc/dressing.nvim" }, -- vim.ui.* をリッチに
	{ src = "https://github.com/nvim-lualine/lualine.nvim" },
	{ src = "https://github.com/romgrk/barbar.nvim" },
	{ src = "https://github.com/nvim-neo-tree/neo-tree.nvim" },
	{ src = "https://github.com/shellRaining/hlchunk.nvim" },
	{ src = "https://github.com/akinsho/toggleterm.nvim" },
	{ src = "https://github.com/windwp/nvim-autopairs" },

	-- ── LSP / Tools ───────────────────────────────────────────
	{ src = "https://github.com/neovim/nvim-lspconfig" },
	{ src = "https://github.com/mason-org/mason.nvim" },
	{ src = "https://github.com/mason-org/mason-lspconfig.nvim" },
	{ src = "https://github.com/WhoIsSethDaniel/mason-tool-installer.nvim" },

	-- ── Formatting ────────────────────────────────────────────
	{ src = "https://github.com/stevearc/conform.nvim" },

	-- ── Git ──────────────────────────────────────────────────
	{ src = "https://github.com/lewis6991/gitsigns.nvim" },
	{ src = "https://github.com/sindrets/diffview.nvim" },
})
