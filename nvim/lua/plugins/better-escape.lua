return {
  "max397574/better-escape.nvim",
  event = { "InsertEnter", "TermOpen" },
  config = function()
    require("better_escape").setup({
      timeout = 100,
      mappings = {
        i = {
          k = { l = "<Esc>" },
        },
        t = {
          k = { l = "<C-\\><C-n>" },
        },
      },
    })
  end,
}
