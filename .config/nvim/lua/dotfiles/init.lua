local M = {}

function M.root()
  return vim.fs.normalize(vim.env.DOTFILES_ROOT or vim.env.HOME)
end

function M.git_context()
  local root = M.root()
  if vim.uv.fs_stat(root .. "/.git") then
    local result = vim.system({ "git", "-C", root, "rev-parse", "--absolute-git-dir" }, { text = true }):wait(3000)
    if result.code == 0 then
      return { toplevel = root, gitdir = vim.trim(result.stdout) }
    end
  end
  local data = vim.env.XDG_DATA_HOME or (vim.env.HOME .. "/.local/share")
  return { toplevel = root, gitdir = vim.fs.normalize(data .. "/yadm/repo.git") }
end

local function command(action, args)
  local python = vim.fn.executable("/usr/bin/python3") == 1 and "/usr/bin/python3" or "python3"
  local cmd = { python, vim.env.HOME .. "/.config/dotfiles/scripts/picker.py", "--root", M.root(), action }
  vim.list_extend(cmd, args or {})
  local result = vim.system(cmd, { text = true, cwd = M.root() }):wait(5000)
  if result.code ~= 0 then
    error(vim.trim(result.stderr or "dotfiles command failed"))
  end
  return result.stdout or ""
end

function M.entries(changed)
  local args = { "--json" }
  if changed then
    args[#args + 1] = "--changed"
  end
  return vim.json.decode(command("list", args))
end

function M.preview(key)
  return command("preview", { key, "--plain" })
end

function M.lazygit()
  local git = M.git_context()
  return Snacks.lazygit({
    cwd = git.toplevel,
    args = { "--git-dir=" .. git.gitdir, "--work-tree=" .. git.toplevel },
  })
end

function M.pick(changed)
  local only_changed = changed == true
  local function find()
    local ok, entries = pcall(M.entries, only_changed)
    if not ok then
      Snacks.notify.error(entries, { title = "Dotfiles" })
      return {}
    end
    for _, item in ipairs(entries) do
      item.text = item.path
    end
    return entries
  end
  return Snacks.picker.pick({
    title = only_changed and "Dotfiles · Changes" or "Dotfiles · Shared",
    cwd = M.root(),
    finder = find,
    show_empty = true,
    format = function(item)
      return { { item.status .. "  ", item.changed and "DiagnosticInfo" or "Comment" }, { item.path, "Normal" } }
    end,
    preview = function(ctx)
      ctx.preview:reset()
      local ok, text = pcall(M.preview, ctx.item.key)
      if not ok then
        ctx.preview:notify(text, "warn")
        return
      end
      ctx.preview:set_title(ctx.item.path)
      ctx.preview:set_lines(vim.split(text, "\n", { plain = true }))
      ctx.preview:highlight({ ft = ctx.item.changed and "diff" or "text" })
    end,
    confirm = function(picker, item, action)
      local ok, fresh = pcall(M.entries, false)
      if not ok then
        Snacks.notify.error(fresh, { title = "Dotfiles" })
        return
      end
      local allowed = {}
      for _, entry in ipairs(fresh) do
        allowed[entry.key] = entry
      end
      for _, selected in ipairs(picker:selected({ fallback = true })) do
        local entry = allowed[selected.key]
        if not entry or entry.deleted then
          Snacks.notify.warn("File is missing or no longer shared; inspect its diff before restoring it", { title = "Dotfiles" })
          return
        end
        selected.file = entry.file
      end
      require("snacks.picker.actions").jump(picker, item, action or {})
    end,
    actions = {
      dotfiles_changes = function(picker)
        only_changed = true
        picker.opts.title = "Dotfiles · Changes"
        picker:find()
      end,
      dotfiles_all = function(picker)
        only_changed = false
        picker.opts.title = "Dotfiles · Shared"
        picker:find()
      end,
      dotfiles_git = function(picker)
        picker:close()
        vim.schedule(M.lazygit)
      end,
    },
    win = {
      input = {
        keys = {
          ["<c-s>"] = { "dotfiles_changes", mode = { "i", "n" } },
          ["<c-a>"] = { "dotfiles_all", mode = { "i", "n" } },
          ["<c-g>"] = { "dotfiles_git", mode = { "i", "n" } },
          ["<c-r>"] = { "refresh", mode = { "i", "n" } },
        },
      },
    },
  })
end

return M
