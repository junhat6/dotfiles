return {
  {
    "folke/which-key.nvim",
    opts = function(_, opts)
      -- ファイル相対パスをコピー (yank path)
      vim.keymap.set("n", "<leader>yp", function()
        local path = vim.fn.expand("%:.")
        vim.fn.setreg("+", path)
        vim.notify("Copied: " .. path)
      end, { desc = "Copy relative file path" })

      -- 選択範囲のパス+行番号をコピー (yank location)
      vim.keymap.set("v", "<leader>yl", function()
        local path = vim.fn.expand("%:.")
        local start_line = vim.fn.line("'<")
        local end_line = vim.fn.line("'>")

        local result
        if start_line == end_line then
          result = string.format("%s:%d", path, start_line)
        else
          result = string.format("%s:%d-%d", path, start_line, end_line)
        end

        vim.fn.setreg("+", result)
        vim.notify("Copied: " .. result)
      end, { desc = "Copy file path with line numbers" })

      return opts
    end,
  },
}
