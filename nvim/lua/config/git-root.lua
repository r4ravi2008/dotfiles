-- Resolve a git repo from the current editing context.
-- Oil buffers are `oil://` URLs, so LazyVim.root.git() cannot see them and
-- falls back to nvim's process cwd (often a non-git parent like cws-stuff).

local M = {}

---Directory that represents the current context.
---In Oil, that is the folder being browsed, or the directory under the cursor.
---@return string
function M.context_dir()
  if vim.bo.filetype == "oil" then
    local ok, oil = pcall(require, "oil")
    if ok then
      local dir = oil.get_current_dir()
      if dir and dir ~= "" then
        local entry = oil.get_cursor_entry()
        if entry and entry.type == "directory" and entry.name and entry.name ~= "" then
          return vim.fs.joinpath(dir, entry.name)
        end
        return dir
      end
    end
  end

  local name = vim.api.nvim_buf_get_name(0)
  if name ~= "" and not name:match("^%w+://") then
    return vim.fn.fnamemodify(name, ":p:h")
  end
  return vim.uv.cwd() or ""
end

---Nearest git worktree root for the current context.
---@return string
function M.git()
  if vim.bo.filetype ~= "oil" then
    return LazyVim.root.git()
  end

  local dir = M.context_dir()
  if not dir or dir == "" then
    return LazyVim.root.git()
  end

  local git = vim.fs.find(".git", { path = dir, upward = true, limit = 1 })[1]
  return git and vim.fs.dirname(git) or dir
end

return M
