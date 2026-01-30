-- bootstrap lazy.nvim, LazyVim and your plugins
require("config.lazy")



-- local builtin = require("telescope.builtin")

function _G.search_org_dir(keyword)
  builtin.live_grep({
    prompt_title = "< Search >",
    cwd = "~/gtd/",
    search = keyword,
  })
end

vim.cmd([[command! SearchOrgDirectory lua _G.search_org_dir()]])
vim.api.nvim_set_keymap("n", "<leader>sz", [[:SearchOrgDirectory<CR>]], { noremap = true, silent = true })

-- local lfs = require("lfs")
--
-- function _G.list_org_files()
--   local org_files = {}
--   for file in lfs.dir("~/gtd") do
--     if file:match("%.org$") then
--       local path = "~/gtd" .. "/" .. file
--       table.insert(org_files, path)
--     end
--   end
--   return org_files
-- end
--

-- neovide configuration
if vim.g.neovide then
  vim.keymap.set("n", "<D-s>", ":w<CR>") -- Save
  vim.keymap.set("v", "<D-c>", '"+y') -- Copy
  vim.keymap.set("n", "<D-v>", '"+P') -- Paste normal mode
  vim.keymap.set("v", "<D-v>", '"+P') -- Paste visual mode
  vim.keymap.set("c", "<D-v>", "<C-R>+") -- Paste command mode
  vim.keymap.set("i", "<D-v>", "<C-R>+") -- Paste insert modula2_default_extension
  vim.api.nvim_set_keymap(
    "n",
    "<C-+>",
    ":lua vim.g.neovide_scale_factor = vim.g.neovide_scale_factor + 0.1<CR>",
    { silent = true }
  )
  vim.api.nvim_set_keymap(
    "n",
    "<C-->",
    ":lua vim.g.neovide_scale_factor = vim.g.neovide_scale_factor - 0.1<CR>",
    { silent = true }
  )
  vim.api.nvim_set_keymap("n", "<C-0>", ":lua vim.g.neovide_scale_factor = 1<CR>", { silent = true })
end

-- print to console if vsocde is running
if vim.g.vscode then
  print("Running in vscode")
end
