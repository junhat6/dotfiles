return {
  {
    "sindrets/diffview.nvim",
    cmd = { "DiffviewOpen", "DiffviewFileHistory" },
    keys = {
      { "<leader>dv", "<cmd>DiffviewOpen<cr>", desc = "Diff View (VSCode style)" },
      { "<leader>dh", "<cmd>DiffviewFileHistory %<cr>", desc = "Diff File History" },
      { "<leader>dc", "<cmd>DiffviewClose<cr>", desc = "Diff View Close" },
    },
    opts = {
      enhanced_diff_hl = true,
      view = {
        default = {
          layout = "diff2_horizontal",  -- 横並び表示
        },
        merge_tool = {
          layout = "diff3_horizontal",
        },
        file_history = {
          layout = "diff2_horizontal",
        },
      },
    },
  },
}
