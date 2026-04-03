return {
  "nvim-neo-tree/neo-tree.nvim",
  opts = {
    filesystem = {
      filtered_items = {
        visible = true, -- ドットファイル（隠しファイル）をデフォルトで表示
        hide_dotfiles = false,
        hide_gitignored = false,
      },
    },
  },
}
