return {
  "jugarpeupv/aws.nvim",
  lazy = false,
  config = function()
    require("aws").setup()
  end,
}
