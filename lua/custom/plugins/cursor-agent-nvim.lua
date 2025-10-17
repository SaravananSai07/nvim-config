return {
  'cursor-agent-integration',
  dir = vim.fn.stdpath 'config' .. '/lua/custom/cursor-agent',
  config = function()
    -- Load the cursor-agent module
    local cursor_agent = require 'custom.cursor-agent.init'
    cursor_agent.setup()
  end,
}

