return {
  "stevearc/oil.nvim",
  lazy = false,
  dependencies = { "nvim-tree/nvim-web-devicons" },

  -- Global (non-Oil) keymaps
  keys = {
    { "<leader>fo", "<cmd>Oil<cr>", desc = "Open Oil" },
    {
      "<leader>%",
      ":let @+=expand('%:p')<CR>",
      mode = "n",
      desc = "Copy current file path",
    },
  },

  -- Make Oil leave <C-hjkl> alone so tmux navigator can work
  opts = {
    keymaps = {
      ["<C-h>"] = false,
      ["<C-j>"] = false,
      ["<C-k>"] = false,
      ["<C-l>"] = false,
      -- optional: give Oil a different refresh key so you still have one
      ["R"] = "actions.refresh",
    },
    view_options = {
      show_hidden = true,
    },
  },

  -- Put Oil-only maps behind a FileType autocmd so they’re buffer-local
  init = function()
    vim.api.nvim_create_autocmd("FileType", {
      pattern = "oil",
      callback = function(ev)
        vim.keymap.set("n", "<leader>fyp", function()
          require("oil.actions").copy_entry_path.callback()
          vim.fn.setreg("+", vim.fn.getreg(vim.v.register))
        end, { buffer = ev.buf, desc = "Copy filepath to system clipboard (Oil)" })
      end,
    })
  end,
}
