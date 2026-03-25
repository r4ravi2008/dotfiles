-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
-- Add any additional autocmds here

-- Write nvim window layout to file for tmux pane-minimap
-- This allows the minimap to show internal nvim splits and highlight the active one
local function write_nvim_layout()
  local tmux_pane = os.getenv("TMUX_PANE")
  if not tmux_pane then
    return
  end
  -- TMUX_PANE is like %0, %1, etc - remove the % prefix
  local pane_id = tmux_pane:sub(2)
  local layout = vim.fn.winlayout()
  local active_win = vim.api.nvim_get_current_win()
  local data = {
    layout = layout,
    active_win = active_win,
  }
  local filepath = "/tmp/nvim_layout_" .. pane_id
  local f = io.open(filepath, "w")
  if f then
    f:write(vim.json.encode(data))
    f:close()
  end
end

-- Update layout file whenever windows change
vim.api.nvim_create_autocmd({ "WinNew", "WinClosed", "WinEnter", "VimResized" }, {
  callback = write_nvim_layout,
})

-- Also write on startup
write_nvim_layout()
