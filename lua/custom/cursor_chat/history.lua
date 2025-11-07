local M = {}
local ui = require('custom.cursor_chat.ui')

local chat_dir = vim.fn.stdpath('data') .. '/cursor/chats'

local function get_workspace_dir()
  local cwd = vim.fn.getcwd()
  return vim.fn.fnamemodify(cwd, ':t')
end

function M.save_chat(buffer)
  local workspace = get_workspace_dir()
  local timestamp = os.date('%Y-%m-%d_%H-%M-%S')
  local filename = string.format('%s/%s/%s.md', chat_dir, workspace, timestamp)

  vim.fn.mkdir(vim.fn.fnamemodify(filename, ':h'), 'p')

  local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
  vim.fn.writefile(lines, filename)

  vim.notify('Chat saved to ' .. filename, vim.log.levels.INFO)
end

function M.load_chat(filename)
  if not ui.state.history_buf or not vim.api.nvim_buf_is_valid(ui.state.history_buf) then
    vim.notify('History buffer not available', vim.log.levels.ERROR)
    return
  end

  local lines = vim.fn.readfile(filename)
  if not lines then
    vim.notify('Could not read file: ' .. filename, vim.log.levels.ERROR)
    return
  end

  vim.api.nvim_buf_set_option(ui.state.history_buf, 'modifiable', true)
  vim.api.nvim_buf_set_lines(ui.state.history_buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(ui.state.history_buf, 'modifiable', false)

  vim.notify('Loaded chat: ' .. filename, vim.log.levels.INFO)
end

function M.list_chats()
  local workspace = get_workspace_dir()
  local workspace_chat_dir = string.format('%s/%s', chat_dir, workspace)

  local files = vim.fn.glob(workspace_chat_dir .. '/*.md', true, true)
  return files
end

return M
