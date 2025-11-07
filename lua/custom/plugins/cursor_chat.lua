return {
  'cursor-chat-integration',
  dir = vim.fn.stdpath 'config' .. '/lua/custom/cursor_chat',
  config = function()
    -- Load the cursor-agent module
    local cursor_chat = require 'custom.cursor_chat'
    cursor_chat.setup()
  end,
}

