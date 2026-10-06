return {
  {
    "lewis6991/gitsigns.nvim",
    opts = function(_, opts)
      opts.worktrees = opts.worktrees or {}
      local context = require("dotfiles").git_context()
      if vim.uv.fs_stat(context.gitdir) then
        table.insert(opts.worktrees, context)
      end
    end,
  },
  {
    "folke/snacks.nvim",
    keys = {
      { "<leader>fd", function() require("dotfiles").pick(false) end, desc = "Dotfiles (shared settings)" },
      { "<leader>fD", function() require("dotfiles").pick(true) end, desc = "Dotfiles (changed settings)" },
      { "<leader>gy", function() require("dotfiles").lazygit() end, desc = "Lazygit (dotfiles)" },
    },
  },
}
