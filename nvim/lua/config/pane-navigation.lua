local M = {}

local in_herdr = vim.env.HERDR_ENV == "1"

-- Do not require backends at import time. snacks.nvim config loads this module
-- before smart-splits / herdr-splits are on the runtimepath.
local function require_optional(name)
  local ok, mod = pcall(require, name)
  if ok then
    return mod
  end
  return nil
end

local function resize_backend()
  if in_herdr then
    return require_optional("herdr-splits")
  end
  return require_optional("smart-splits")
end

local function move_backend()
  if in_herdr then
    return nil
  end
  return require_optional("smart-splits")
end

local directions = {
  h = { name = "left", tmux = "L", vim = "h" },
  j = { name = "down", tmux = "D", vim = "j" },
  k = { name = "up", tmux = "U", vim = "k" },
  l = { name = "right", tmux = "R", vim = "l" },
}

local function direction(key)
  local value = directions[key]
  assert(value, "unsupported pane direction: " .. tostring(key))
  return value
end

local function has_split_in_direction(vim_dir)
  return vim.fn.winnr(vim_dir) ~= vim.fn.winnr()
end

local function tmux_is_zoomed()
  if not (vim.env.TMUX and vim.env.TMUX_PANE) then
    return false
  end

  local zoomed = vim.trim(
    vim.fn.system({ "tmux", "display-message", "-p", "-t", vim.env.TMUX_PANE, "#{window_zoomed_flag}" })
  )
  return vim.v.shell_error == 0 and zoomed == "1"
end

local function tmux_select_pane_preserve_zoom(tmux_dir)
  if not vim.env.TMUX then
    return false
  end

  if vim.env.TMUX_PANE then
    vim.fn.system({ "tmux", "select-pane", "-t", vim.env.TMUX_PANE, "-" .. tmux_dir, "-Z" })
    if vim.v.shell_error == 0 then
      return true
    end
  end

  vim.fn.system({ "tmux", "select-pane", "-" .. tmux_dir, "-Z" })
  return vim.v.shell_error == 0
end

function M.move(key)
  local dir = direction(key)
  if in_herdr then
    -- herdr-nvim-nav owns Alt+hjkl maps under Herdr; this is a fallback for
    -- callers (e.g. snacks) that invoke move() directly.
    local prev = vim.api.nvim_get_current_win()
    vim.cmd("wincmd " .. dir.vim)
    if vim.api.nvim_get_current_win() == prev then
      vim.fn.system({ "herdr", "pane", "focus", "--direction", dir.name, "--current" })
    end
    return
  end

  if not has_split_in_direction(dir.vim) and tmux_is_zoomed() then
    if tmux_select_pane_preserve_zoom(dir.tmux) then
      return
    end
  end

  local backend = move_backend()
  if backend then
    backend["move_cursor_" .. dir.name]()
    return
  end
  vim.cmd("wincmd " .. dir.vim)
end

function M.resize(key)
  local dir = direction(key)
  local backend = resize_backend()
  if backend then
    backend["resize_" .. dir.name]()
    return
  end
  if dir.vim == "h" then
    vim.cmd("vertical resize -3")
  elseif dir.vim == "l" then
    vim.cmd("vertical resize +3")
  elseif dir.vim == "k" then
    vim.cmd("resize -3")
  else
    vim.cmd("resize +3")
  end
end

function M.swap(key)
  local dir = direction(key)
  local backend = move_backend()
  if backend then
    backend["swap_buf_" .. dir.name]()
    return
  end

  local current_win = vim.api.nvim_get_current_win()
  local current_buf = vim.api.nvim_win_get_buf(current_win)
  local target_number = vim.fn.winnr(dir.vim)
  local target_win = vim.fn.win_getid(target_number)
  if target_win == current_win then
    return
  end

  local target_buf = vim.api.nvim_win_get_buf(target_win)
  vim.api.nvim_win_set_buf(current_win, target_buf)
  vim.api.nvim_win_set_buf(target_win, current_buf)
end

return M
