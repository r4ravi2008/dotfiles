return {
  "gruvw/strudel.nvim",
  build = "npm ci",
  config = function()
    require("strudel").setup({
      ui = {
        maximise_menu_panel = true,
        hide_menu_panel = false,
        hide_top_bar = false,
        hide_code_editor = false,
        hide_error_display = false,
      },
      start_on_launch = true,
      update_on_save = true,
      sync_cursor = true,
      report_eval_errors = true,
      -- custom_css_file = "/path/to/your/custom.css",
      headless = false,
      browser_data_dir = "~/.cache/strudel-nvim/",
      -- browser_exec_path = "/path/to/browser/executable",
    })

    vim.api.nvim_create_autocmd("FileType", {
      pattern = "javascript",
      callback = function()
        vim.keymap.set("n", "<leader>sl", function() require("strudel").launch() end, { buffer = true, desc = "Launch Strudel" })
        vim.keymap.set("n", "<leader>sq", function() require("strudel").quit() end, { buffer = true, desc = "Quit Strudel" })
        vim.keymap.set("n", "<leader>st", function() require("strudel").toggle() end, { buffer = true, desc = "Strudel Toggle Play/Stop" })
        vim.keymap.set("n", "<leader>su", function() require("strudel").update() end, { buffer = true, desc = "Strudel Update" })
        vim.keymap.set("n", "<leader>ss", function() require("strudel").stop() end, { buffer = true, desc = "Strudel Stop Playback" })
        vim.keymap.set("n", "<leader>sb", function() require("strudel").set_buffer() end, { buffer = true, desc = "Strudel set current buffer" })
        vim.keymap.set("n", "<leader>sx", function() require("strudel").execute() end, { buffer = true, desc = "Strudel set current buffer and update" })
      end,
    })
  end,
}
