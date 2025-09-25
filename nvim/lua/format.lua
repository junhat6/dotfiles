-- Conform.nvim の設定 (保存時フォーマット)
require("conform").setup({
  -- ファイル保存時に自動フォーマットする
  format_on_save = {
    timeout_ms = 2000,
    lsp_fallback = true, -- LSP のフォーマッタがあればそれも使う
  },
  -- ファイルタイプごとに使用するフォーマッタを指定
  formatters_by_ft = {
    lua = { "stylua" },
    python = { "isort", "black" },
    rust = { "rustfmt", lsp_format = "fallback" },

    javascript        = { "prettierd", "prettier", stop_after_first = true },
    typescript        = { "prettierd", "prettier", stop_after_first = true },
    javascriptreact   = { "prettierd", "prettier", stop_after_first = true },
    typescriptreact   = { "prettierd", "prettier", stop_after_first = true },
    vue               = { "prettierd", "prettier", stop_after_first = true },
    svelte            = { "prettierd", "prettier", stop_after_first = true },
    json              = { "prettierd", "prettier", stop_after_first = true },
    yaml              = { "prettierd", "prettier", stop_after_first = true },
    html              = { "prettierd", "prettier", stop_after_first = true },
    css               = { "prettierd", "prettier", stop_after_first = true },
    scss              = { "prettierd", "prettier", stop_after_first = true },

    sh = { "shfmt" },
  },
})

