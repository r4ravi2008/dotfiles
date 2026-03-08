-- smart-splits.nvim: seamless navigation and resizing across Neovim splits and tmux panes
-- Integrates with tmux-tilish via @tilish-smartsplits 'on'
--
-- Keybinding scheme (matching tilish conventions):
--   Alt+hjkl          - Move between splits/panes (navigation)
--   Ctrl+hjkl         - Resize splits/panes
--   <leader><leader>hjkl - Swap buffers between Neovim windows
return {
  "mrjones2014/smart-splits.nvim",
  lazy = false, -- must not lazy-load; sets @pane-is-vim for tmux integration
  opts = {
    -- allow navigation when tmux pane is zoomed; tmux select-pane -Z
    -- (set in tmux.conf.local) preserves zoom on the target pane
    disable_multiplexer_nav_when_zoomed = false,
    -- at edge of all neovim splits, hand off to tmux pane navigation
    at_edge = "wrap",
  },
  config = function(_, opts)
    require("smart-splits").setup(opts)
    -- Keymaps are set in config/keymaps.lua (VeryLazy) to ensure they load
    -- AFTER LazyVim's default keymaps and can override <A-j>/<A-k> move-line bindings.
  end,
}
