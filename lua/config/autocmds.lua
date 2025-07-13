vim.api.nvim_create_autocmd('ModeChanged', {
  pattern = { 'i:*', 's:*' },
  desc = 'Clear LuaSnip snippet state when leaving insert or select mode',
  callback = function()
    local luasnip = require 'luasnip'
    if luasnip.in_snippet() then
      luasnip.unlink_current()
    end
  end,
})
