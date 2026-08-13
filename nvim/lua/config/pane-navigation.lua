local M = {}

local in_herdr = vim.env.HERDR_ENV == "1"
-- Move under Herdr is owned by herdr-nvim-nav keymaps (fast C action).
-- Resize uses herdr-splits in Herdr and smart-splits under tmux.
local resize_backend = require(in_herdr and "herdr-splits" or "smart-splits")
local move_backend = in_herdr and nil or require("smart-splits")

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

  move_backend["move_cursor_" .. dir.name]()
end

function M.resize(key)
  local dir = direction(key)
  resize_backend["resize_" .. dir.name]()
end

function M.swap(key)
  local dir = direction(key)
  if not in_herdr then
    move_backend["swap_buf_" .. dir.name]()
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
