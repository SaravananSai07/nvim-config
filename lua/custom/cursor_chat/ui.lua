local M = {}

M.state = {
  win = nil,
  history_buf = nil,
  input_buf = nil,
  history_win = nil,
  input_win = nil,
  last_line_partial = false,
  -- Thinking state
  is_thinking = false,
  thinking_start_line = nil,
  thinking_lines = {},
}

-- Highlight groups for thinking and tool use
local function setup_highlights()
  -- Thinking text - dimmed, italic style
  vim.api.nvim_set_hl(0, 'CursorThinking', { fg = '#7aa2f7', italic = true })
  vim.api.nvim_set_hl(0, 'CursorThinkingHeader', { fg = '#bb9af7', bold = true })
  -- Tool use - distinct color
  vim.api.nvim_set_hl(0, 'CursorToolUse', { fg = '#9ece6a', italic = true })
  vim.api.nvim_set_hl(0, 'CursorToolHeader', { fg = '#73daca', bold = true })
  -- User message
  vim.api.nvim_set_hl(0, 'CursorUser', { fg = '#7dcfff', bold = true })
  -- Assistant message
  vim.api.nvim_set_hl(0, 'CursorAssistant', { fg = '#c0caf5', bold = true })
end

function M.create_chat_window()
  -- Check if both windows are valid before reusing them
  local win_valid = M.state.win and vim.api.nvim_win_is_valid(M.state.win)
  local input_win_valid = M.state.input_win and vim.api.nvim_win_is_valid(M.state.input_win)

  if win_valid and input_win_valid then
    -- Both windows exist, just focus the input window
    vim.api.nvim_set_current_win(M.state.input_win)
    vim.cmd('startinsert')
    return
  elseif win_valid or input_win_valid then
    -- Partial state - close any remaining windows and recreate
    M.close_chat()
  end

  -- Setup highlight groups
  setup_highlights()

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
  
  -- Enable wrap for better readability
  vim.api.nvim_win_set_option(win, 'wrap', true)
  vim.api.nvim_win_set_option(win, 'linebreak', true)
  
  -- Open a small horizontal split at the bottom for the input buffer
  vim.cmd('belowright new')
  local input_win = vim.api.nvim_get_current_win()
  M.state.input_win = input_win
  vim.api.nvim_win_set_height(input_win, 5)
  vim.api.nvim_win_set_buf(input_win, M.state.input_buf)
  
  -- Set input window options
  vim.api.nvim_win_set_option(input_win, 'wrap', true)
  vim.api.nvim_win_set_option(input_win, 'linebreak', true)
  
  -- Add welcome message
  M.add_welcome_message()
  
  -- Go back to the input window and start insert mode
  vim.api.nvim_set_current_win(input_win)
  vim.cmd('startinsert')
  
  -- Set up keymaps for the input buffer
  M.setup_input_keymaps()
end

function M.add_welcome_message()
  if not M.state.history_buf or not vim.api.nvim_buf_is_valid(M.state.history_buf) then
    return
  end
  
  vim.api.nvim_buf_set_option(M.state.history_buf, 'modifiable', true)
  vim.api.nvim_buf_set_lines(M.state.history_buf, 0, -1, false, {
    '# Cursor Agent Chat',
    '',
    'Type your message below and press **Enter** to send.',
    '',
    '**Tips:**',
    '- Use `@file:path/to/file` to add files to context',
    '- `<leader>cf` to pick files with telescope',
    '- `<leader>cm` to change model',
    '- `<leader>cv` to view current context',
    '',
    '---',
    '',
  })
  vim.api.nvim_buf_set_option(M.state.history_buf, 'modifiable', false)
end

function M.setup_input_keymaps()
  local function submit()
    local lines = vim.api.nvim_buf_get_lines(M.state.input_buf, 0, -1, false)
    local prompt = table.concat(lines, '\n')
    
    -- Don't submit empty prompts
    if prompt:match('^%s*$') then
      return
    end

    -- Clear input buffer
    vim.api.nvim_buf_set_lines(M.state.input_buf, 0, -1, false, { '' })

    -- Pass the prompt to the main logic (don't add to history here, main.lua does it)
    require('custom.cursor_chat.main').submit_prompt(prompt)
  end

  -- Enter to submit
  vim.keymap.set('i', '<CR>', submit, { buffer = M.state.input_buf, desc = 'Submit prompt' })
  
  -- Shift+Enter for newline
  vim.keymap.set('i', '<S-CR>', '<CR>', { buffer = M.state.input_buf, desc = 'Insert newline' })
  
  -- Escape to go to normal mode in input
  vim.keymap.set('i', '<Esc>', '<Esc>', { buffer = M.state.input_buf })
  
  -- q in normal mode to close chat
  vim.keymap.set('n', 'q', function()
    M.close_chat()
  end, { buffer = M.state.input_buf, desc = 'Close chat' })
  
  -- Also add q to history buffer
  if M.state.history_buf and vim.api.nvim_buf_is_valid(M.state.history_buf) then
    vim.keymap.set('n', 'q', function()
      M.close_chat()
    end, { buffer = M.state.history_buf, desc = 'Close chat' })
  end
end

function M.close_chat()
  if M.state.input_win and vim.api.nvim_win_is_valid(M.state.input_win) then
    vim.api.nvim_win_close(M.state.input_win, true)
  end
  if M.state.history_win and vim.api.nvim_win_is_valid(M.state.history_win) then
    vim.api.nvim_win_close(M.state.history_win, true)
  end
  M.state.win = nil
  M.state.history_win = nil
  M.state.input_win = nil
  M.state.history_buf = nil
  M.state.input_buf = nil
end

function M.update_history(content)
  if not M.state.history_buf or not vim.api.nvim_buf_is_valid(M.state.history_buf) then
    return
  end

  local lines = vim.split(content, '\n')
  
  vim.api.nvim_buf_set_option(M.state.history_buf, 'modifiable', true)
  vim.api.nvim_buf_set_lines(M.state.history_buf, -1, -1, false, lines)
  vim.api.nvim_buf_set_option(M.state.history_buf, 'modifiable', false)

  M.scroll_to_bottom()
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

  M.scroll_to_bottom()
end

-- Start a thinking section
function M.start_thinking()
  if M.state.is_thinking then
    return
  end
  
  M.state.is_thinking = true
  M.state.thinking_lines = {}
  
  if not M.state.history_buf or not vim.api.nvim_buf_is_valid(M.state.history_buf) then
    return
  end
  
  vim.api.nvim_buf_set_option(M.state.history_buf, 'modifiable', true)
  
  -- Add thinking header
  local thinking_header = { '', '> 💭 **Thinking...**', '>' }
  vim.api.nvim_buf_set_lines(M.state.history_buf, -1, -1, false, thinking_header)
  
  -- Store the line where thinking content starts
  M.state.thinking_start_line = vim.api.nvim_buf_line_count(M.state.history_buf)
  
  vim.api.nvim_buf_set_option(M.state.history_buf, 'modifiable', false)
  
  -- Update statusline
  if M.state.history_win and vim.api.nvim_win_is_valid(M.state.history_win) then
    vim.api.nvim_win_set_option(M.state.history_win, 'statusline', '🧠 Thinking...')
  end
  
  M.scroll_to_bottom()
end

-- Append thinking content
function M.append_thinking(text)
  if not M.state.is_thinking then
    M.start_thinking()
  end
  
  if not M.state.history_buf or not vim.api.nvim_buf_is_valid(M.state.history_buf) then
    return
  end
  
  -- Accumulate thinking text
  table.insert(M.state.thinking_lines, text)
  
  vim.api.nvim_buf_set_option(M.state.history_buf, 'modifiable', true)
  
  -- Format thinking lines with blockquote prefix
  local lines = vim.split(text, '\n', { plain = true })
  local formatted_lines = {}
  for _, line in ipairs(lines) do
    if line ~= '' then
      table.insert(formatted_lines, '> ' .. line)
    else
      table.insert(formatted_lines, '>')
    end
  end
  
  -- Append to buffer
  if #formatted_lines > 0 then
    local last_line_num = vim.api.nvim_buf_line_count(M.state.history_buf)
    local last_line = vim.api.nvim_buf_get_lines(M.state.history_buf, last_line_num - 1, last_line_num, false)[1] or ''
    
    -- If last line is just '>', append to it
    if last_line == '>' and #formatted_lines > 0 then
      vim.api.nvim_buf_set_lines(M.state.history_buf, last_line_num - 1, last_line_num, false, { formatted_lines[1] })
      table.remove(formatted_lines, 1)
    end
    
    if #formatted_lines > 0 then
      vim.api.nvim_buf_set_lines(M.state.history_buf, -1, -1, false, formatted_lines)
    end
  end
  
  vim.api.nvim_buf_set_option(M.state.history_buf, 'modifiable', false)
  
  M.scroll_to_bottom()
end

-- End thinking section
function M.end_thinking()
  if not M.state.is_thinking then
    return
  end
  
  M.state.is_thinking = false
  
  if not M.state.history_buf or not vim.api.nvim_buf_is_valid(M.state.history_buf) then
    return
  end
  
  vim.api.nvim_buf_set_option(M.state.history_buf, 'modifiable', true)
  
  -- Add thinking complete marker
  vim.api.nvim_buf_set_lines(M.state.history_buf, -1, -1, false, { '>', '> ✅ *Thinking complete*', '', '' })
  
  vim.api.nvim_buf_set_option(M.state.history_buf, 'modifiable', false)
  
  -- Reset statusline
  if M.state.history_win and vim.api.nvim_win_is_valid(M.state.history_win) then
    vim.api.nvim_win_set_option(M.state.history_win, 'statusline', '')
  end
  
  -- Clear thinking state
  M.state.thinking_lines = {}
  M.state.thinking_start_line = nil
  
  M.scroll_to_bottom()
end

-- Show tool use in the chat
function M.append_tool_use(tool_name, tool_data)
  if not M.state.history_buf or not vim.api.nvim_buf_is_valid(M.state.history_buf) then
    return
  end
  
  vim.api.nvim_buf_set_option(M.state.history_buf, 'modifiable', true)
  
  -- Format tool use display
  local tool_lines = {
    '',
    string.format('🔧 **Tool:** `%s`', tool_name),
  }
  
  -- Add input if available
  if tool_data.input then
    if type(tool_data.input) == 'table' then
      for k, v in pairs(tool_data.input) do
        table.insert(tool_lines, string.format('   - %s: `%s`', k, tostring(v)))
      end
    else
      table.insert(tool_lines, string.format('   - input: `%s`', tostring(tool_data.input)))
    end
  end
  
  table.insert(tool_lines, '')
  
  vim.api.nvim_buf_set_lines(M.state.history_buf, -1, -1, false, tool_lines)
  
  vim.api.nvim_buf_set_option(M.state.history_buf, 'modifiable', false)
  
  M.scroll_to_bottom()
end

-- Legacy compatibility
function M.set_thinking(is_thinking)
  if is_thinking then
    M.start_thinking()
  else
    M.end_thinking()
  end
end

function M.scroll_to_bottom()
  if M.state.history_win and vim.api.nvim_win_is_valid(M.state.history_win) then
    local last_line = vim.api.nvim_buf_line_count(M.state.history_buf)
    vim.api.nvim_win_set_cursor(M.state.history_win, { last_line, 0 })
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
    title = ' Current Context ',
    title_pos = 'center',
  }

  local win = vim.api.nvim_open_win(buf, true, opts)
  vim.api.nvim_win_set_option(win, 'wrap', true)
  vim.api.nvim_win_set_option(win, 'linebreak', true)

  vim.keymap.set('n', 'q', '<cmd>close<CR>', { buffer = buf, nowait = true })
  vim.keymap.set('n', '<Esc>', '<cmd>close<CR>', { buffer = buf, nowait = true })
end

return M
