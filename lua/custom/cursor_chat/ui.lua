local M = {}

M.state = {
  win = nil,
  history_buf = nil,
  input_buf = nil,
  history_win = nil,
  input_win = nil,
  last_line_partial = false,
}

function M.create_chat_window()
  if M.state.win and vim.api.nvim_win_is_valid(M.state.win) then
    vim.api.nvim_set_current_win(M.state.win)
    return
  end

  -- Create a new buffer for history
  M.state.history_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(M.state.history_buf, 'bufhidden', 'wipe')
  vim.api.nvim_buf_set_option(M.state.history_buf, 'filetype', 'markdown')
  vim.api.nvim_buf_set_option(M.state.history_buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_name(M.state.history_buf, 'Cursor Chat')
  vim.api.nvim_buf_set_option(M.state.history_buf, 'modifiable', false)

  -- Create a new buffer for input
  M.state.input_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(M.state.input_buf, 'bufhidden', 'wipe')
  vim.api.nvim_buf_set_option(M.state.input_buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_name(M.state.input_buf, 'Cursor Input')

  -- Open in a vertical split on the right
  vim.cmd 'vsplit'
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_width(win, math.floor(vim.o.columns * 0.4))
  M.state.win = win

  -- Show the history buffer in the main part of the window
  M.state.history_win = win
  vim.api.nvim_win_set_buf(win, M.state.history_buf)
  
  -- Open a small horizontal split at the bottom for the input buffer
  vim.cmd('new')
  local input_win = vim.api.nvim_get_current_win()
  M.state.input_win = input_win
  vim.api.nvim_win_set_height(input_win, 3)
  vim.api.nvim_win_set_buf(input_win, M.state.input_buf)
  
  -- Go back to the input window and start insert mode
  vim.api.nvim_set_current_win(input_win)
  vim.cmd('startinsert')
  
  -- Set up keymaps for the input buffer
  -- We'll do this in a separate function to keep it clean
  M.setup_input_keymaps()
end

function M.setup_input_keymaps()
  local function submit()
    local lines = vim.api.nvim_buf_get_lines(M.state.input_buf, 0, -1, false)
    local prompt = table.concat(lines, '\n')

    -- Clear input buffer
    vim.api.nvim_buf_set_lines(M.state.input_buf, 0, -1, false, { '' })

    -- Add prompt to history
    M.update_history('**You:**\n\n' .. prompt)

    -- Pass the prompt to the main logic
    require('custom.cursor_chat.main').submit_prompt(prompt)
  end

  vim.keymap.set('i', '<CR>', submit, { buffer = M.state.input_buf })
end


function M.get_input()
  -- TODO: Implement getting input from the input buffer
  vim.notify('UI: Getting input (not implemented)', vim.log.levels.INFO)
  return ''
end

function M.update_history(content)
  if not M.state.history_buf or not vim.api.nvim_buf_is_valid(M.state.history_buf) then
    return
  end

  local lines = vim.split(content, '\n')
  
  vim.api.nvim_buf_set_option(M.state.history_buf, 'modifiable', true)
  vim.api.nvim_buf_set_lines(M.state.history_buf, -1, -1, false, lines)
  -- Add a separator
  vim.api.nvim_buf_set_lines(M.state.history_buf, -1, -1, false, { '', '---', '' })
  vim.api.nvim_buf_set_option(M.state.history_buf, 'modifiable', false)

  -- Auto-scroll to bottom
  if M.state.history_win and vim.api.nvim_win_is_valid(M.state.history_win) then
    local last_line = vim.api.nvim_buf_line_count(M.state.history_buf)
    vim.api.nvim_win_set_cursor(M.state.history_win, { last_line, 0 })
  end
end

function M.append_to_history(text)
  if not M.state.history_buf or not vim.api.nvim_buf_is_valid(M.state.history_buf) then
    return
  end
  
  vim.api.nvim_buf_set_option(M.state.history_buf, 'modifiable', true)

  local lines = vim.split(text, '\n', { plain = true })
  
  if M.state.last_line_partial then
    -- Append to the last line
    local last_line_num = vim.api.nvim_buf_line_count(M.state.history_buf)
    local last_line_content = vim.api.nvim_buf_get_lines(M.state.history_buf, last_line_num - 1, last_line_num, false)[1] or ''
    vim.api.nvim_buf_set_lines(M.state.history_buf, last_line_num - 1, last_line_num, false, { last_line_content .. lines[1] })
    table.remove(lines, 1)
  end

  if #lines > 0 then
    vim.api.nvim_buf_set_lines(M.state.history_buf, -1, -1, false, lines)
  end

  if text:sub(-1) ~= '\n' then
    M.state.last_line_partial = true
  else
    M.state.last_line_partial = false
  end

  vim.api.nvim_buf_set_option(M.state.history_buf, 'modifiable', false)

  -- Auto-scroll to bottom
  if M.state.history_win and vim.api.nvim_win_is_valid(M.state.history_win) then
      local last_line_num = vim.api.nvim_buf_line_count(M.state.history_buf)
      vim.api.nvim_win_set_cursor(M.state.history_win, { last_line_num, 0 })
  end
end

function M.set_thinking(is_thinking)
  if not M.state.win or not vim.api.nvim_win_is_valid(M.state.win) then
    return
  end

  if is_thinking then
    vim.api.nvim_win_set_option(M.state.win, 'statusline', '🤖 Thinking...')
  else
    vim.api.nvim_win_set_option(M.state.win, 'statusline', '')
  end
end

function M.show_context(context_str)
  if context_str == '' then
    vim.notify('Context is empty', vim.log.levels.INFO)
    return
  end
  
  -- Create a floating window to show the context
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
  vim.api.nvim_buf_set_option(buf, 'filetype', 'markdown')

  local lines = vim.split(context_str, '\n')
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)

  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.8)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local opts = {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = 'rounded',
    title = 'Current Context',
    title_pos = 'center',
  }

  local win = vim.api.nvim_open_win(buf, true, opts)
  vim.api.nvim_win_set_option(win, 'wrap', true)
  vim.api.nvim_win_set_option(win, 'linebreak', true)

  vim.keymap.set('n', 'q', '<cmd>close<CR>', { buffer = buf, nowait = true })
end


return M
