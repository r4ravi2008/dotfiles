-- Fast Alt+hjkl navigation across Herdr panes and Neovim splits.
-- Uses a C herdr action + marker file (~10ms) instead of herdr-splits' bash
-- scripts that shell out to the herdr CLI multiple times per keypress (~300ms).
local dir = vim.fn.expand("~/.dotfiles/herdr/nvim-nav")
local lua_mod = dir .. "/lua/herdr-nvim-nav/init.lua"

return {
  dir = dir,
  name = "herdr-nvim-nav",
  cond = vim.env.HERDR_ENV == "1" and vim.uv.fs_stat(lua_mod) ~= nil,
  lazy = false,
  opts = {
    with_tmux = false,
    keymaps = {
      left = { "<M-h>" },
      down = { "<M-j>" },
      up = { "<M-k>" },
      right = { "<M-l>" },
    },
  },
  config = function(_, opts)
    local ok, nav = pcall(require, "herdr-nvim-nav")
    if not ok then
      return
    end
    nav.setup(opts)
  end,
}
