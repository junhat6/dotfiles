-- :MasonでGUIを開いてLSPやツールを管理するsetup
require('mason').setup()
-- Mason と lspconfigを連携させるプラグイン
require('mason-lspconfig').setup()
-- ensure_installed内は自動的にインストール・更新される
require('mason-tool-installer').setup({
	ensure_installed = {
		"lua_ls", -- Lua言語サーバー
		"stylua", -- Lua用フォーマッター
		"prettierd",
	}
})

-- lspconfigを直接呼ぶ代わりにこの関数でlspサーバーをセットアップ
vim.lsp.config('lua_ls', {
	settings = {
		Lua = {
			runtime = {
				version = 'LuaJIT', -- Neovimが使っているluaバージョンを指定
			},
-- vimやrequireを未定義変数として警告しないように
			diagnostics = {
				globals = {
					'vim',
					'require'
				},
			},
-- Lua LSにNeovim本体のプラグインのLuaAPIを見せて補完・診断対象に含める
			workspace = {
				library = vim.api.nvim_get_runtime_file("", true),
			},
-- 利用状況のデータ収集を無効化
			telemetry = {
				enable = false,
			},
		},
	},
})
