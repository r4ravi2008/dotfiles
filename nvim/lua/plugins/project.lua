return {
  "ahmedkhalf/project.nvim",
  opts = {
    detection_methods = { "pattern" },
    patterns = { ".git", "_darcs", ".hg", ".bzr", ".svn", "Makefile", "package.json" },
    ignore_lsp = {},
    show_hidden = false,
    silent_chdir = true,
    scope_chdir = "global",
  },
  event = "VeryLazy",
  config = function(_, opts)
    require("project_nvim").setup(opts)
    require("telescope").load_extension("projects")
  end,
  keys = {
    { "<leader>fp", "<cmd>Telescope projects<cr>", desc = "Find projects" },
    {
      "<leader>fP",
      function()
        local project_name = vim.fn.input("Enter project name: ")
        if project_name ~= "" then
          vim.fn.system("git rev-parse --is-inside-work-tree")
          local project_path
          if vim.v.shell_error == 0 then
            project_path = vim.fn.system("git rev-parse --show-toplevel"):gsub("\n", "")
          else
            project_path = vim.fn.getcwd()
          end
          local project = require("project_nvim.project")
          project.set_manual_mode(true)
          project.add(project_name, project_path)
          vim.notify("Added '" .. project_name .. "' to projects", vim.log.levels.INFO)
        else
          vim.notify("Project name cannot be empty", vim.log.levels.WARN)
        end
      end,
      desc = "Add current directory to projects",
    },
  },
}
