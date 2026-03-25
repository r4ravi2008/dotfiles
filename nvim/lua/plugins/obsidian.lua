return {
  "epwalsh/obsidian.nvim",
  version = "*",
  lazy = true,
  ft = "markdown",
  dependencies = {
    "nvim-lua/plenary.nvim",
  },
  opts = {
    workspaces = {
      {
        name = "vault",
        path = "~/Library/Mobile Documents/com~apple~CloudDocs/ObsidianMind",
      },
    },
    completion = {
      min_chars = 2,
    },
    note_id_func = function(title)
      return title
    end,
    note_frontmatter_func = function(note)
      local out = { id = note.id, aliases = note.aliases, tags = note.tags }
      if note.metadata ~= nil and not vim.tbl_isempty(note.metadata) then
        for k, v in pairs(note.metadata) do
          out[k] = v
        end
      end
      return out
    end,
    templates = {
      folder = "04-Templates",
      date_format = "%Y-%m-%d",
      time_format = "%H:%M",
    },
    follow_url_func = function(url)
      vim.cmd('silent !open "' .. url .. '"')
    end,
    use_advanced_uri = true,
  },
  keys = {
    { "<leader>on", "<cmd>ObsidianNew<cr>", desc = "Create new note" },
    { "<leader>os", "<cmd>ObsidianSearch<cr>", desc = "Search notes" },
    { "<leader>ot", "<cmd>ObsidianTemplate<cr>", desc = "Insert template" },
    { "<leader>ob", "<cmd>ObsidianBacklinks<cr>", desc = "Show backlinks" },
    { "<leader>od", "<cmd>ObsidianToday<cr>", desc = "Open daily note" },
    { "<leader>oy", "<cmd>ObsidianYesterday<cr>", desc = "Open yesterday's note" },
    { "<leader>ol", "<cmd>ObsidianLinks<cr>", desc = "Show links" },
    { "<leader>oq", "<cmd>ObsidianQuickSwitch<cr>", desc = "Quick switch" },
    {
      "<leader>oo",
      function()
        vim.cmd('silent !open -a "Obsidian"')
      end,
      desc = "Open vault in Obsidian app",
    },
    {
      "<leader>of",
      function()
        vim.cmd('silent !open "$HOME/Library/Mobile Documents/com~apple~CloudDocs/ObsidianMind"')
      end,
      desc = "Open vault folder in Finder",
    },
    {
      "<leader>og",
      "<cmd>ObsidianFollowLink<cr>",
      desc = "Follow link under cursor",
    },
  },
}
