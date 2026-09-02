-- Snacks.nvim configuration
-- Add keymaps for floating terminal windows (like lazygit) to navigate or resize multiplexer panes
return {
  "folke/snacks.nvim",
  opts = function(_, opts)
    local pane_navigation = require("config.pane-navigation")
    -- Configure lazygit to use maximum space
    opts.lazygit = {
      win = {
        width = 0,  -- 0 means full width
        height = 0, -- 0 means full height
      },
    }
    -- Fix scrambled terminal UI (lazygit) after pane hops / zoom changes
    local function refresh_lazygit_terminal()
      vim.schedule(function()
        local buf = vim.api.nvim_get_current_buf()
        local win = vim.api.nvim_get_current_win()
        
        if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_win_is_valid(win) then
          return
        end
        
        local snacks_term = vim.b[buf].snacks_terminal
        if not snacks_term or not snacks_term.cmd then
          return
        end
        
        local cmd = snacks_term.cmd
        local is_lazygit = (type(cmd) == "string" and cmd:match("lazygit"))
          or (type(cmd) == "table" and vim.tbl_contains(cmd, "lazygit"))
        
        if not is_lazygit then
          return
        end
        
        local job_id = vim.b[buf].terminal_job_id
        if not job_id then
          return
        end
        
        -- Simply send Ctrl-L to lazygit to trigger its native refresh
        -- This is simpler and more reliable than resize signals
        pcall(vim.api.nvim_chan_send, job_id, "\x0c")
      end)
    end
    
    -- Create a user command for manual refresh (as a workaround)
    vim.api.nvim_create_user_command("RefreshLazygit", refresh_lazygit_terminal, {
      desc = "Manually refresh lazygit terminal to fix UI glitches"
    })

    -- Refresh on focus gained (returning to the nvim pane)
    vim.api.nvim_create_autocmd("FocusGained", {
      callback = function()
        vim.defer_fn(refresh_lazygit_terminal, 150)
      end,
    })
    
    -- Manual keymap to refresh lazygit (use this when UI glitches)
    vim.api.nvim_create_autocmd("TermOpen", {
      callback = function()
        vim.defer_fn(function()
          local buf = vim.api.nvim_get_current_buf()
          local snacks_term = vim.b[buf].snacks_terminal
          if snacks_term and snacks_term.cmd then
            local cmd = snacks_term.cmd
            local is_lazygit = (type(cmd) == "string" and cmd:match("lazygit"))
              or (type(cmd) == "table" and vim.tbl_contains(cmd, "lazygit"))
            if is_lazygit then
              -- Add a keymap to manually refresh (Ctrl-R in terminal mode)
              vim.keymap.set("t", "<C-r>", function()
                refresh_lazygit_terminal()
              end, { buffer = buf, silent = true, desc = "Refresh lazygit UI" })
            end
          end
        end, 10)
      end,
    })

    -- Set up autocmd to add keymaps for floating terminal windows
    vim.api.nvim_create_autocmd("TermOpen", {
      callback = function()
        -- Small delay to let the window configuration settle
        vim.defer_fn(function()
          local buf = vim.api.nvim_get_current_buf()
          local win = vim.api.nvim_get_current_win()
          
          -- Check if this is a valid window and buffer
          if not vim.api.nvim_win_is_valid(win) or not vim.api.nvim_buf_is_valid(buf) then
            return
          end
          
          local win_config = vim.api.nvim_win_get_config(win)
          
          -- Only add these keymaps for floating windows
          if win_config.relative ~= "" then
            local keymap_opts = { buffer = buf, silent = true }
            
            -- Match the normal split controls: Alt navigates and Ctrl resizes.
            for _, direction in ipairs({ "h", "j", "k", "l" }) do
              vim.keymap.set("t", "<A-" .. direction .. ">", function()
                pane_navigation.move(direction)
              end, keymap_opts)
              vim.keymap.set("t", "<C-" .. direction .. ">", function()
                pane_navigation.resize(direction)
              end, keymap_opts)
            end
          end
        end, 10)
      end,
    })

    return opts
  end,
}
