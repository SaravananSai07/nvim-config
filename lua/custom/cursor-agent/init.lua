local M = {}

-- State management
M.state = {
  diff_bufnr = nil,
  diff_winnr = nil,
  original_bufnr = nil,
  original_winnr = nil,
  changes = {}, -- Stack of applied changes for undo
  current_file = nil,
}

-- Utility: Check if cursor-agent CLI is available
local function check_cursor_agent()
  local handle = io.popen 'which cursor-agent 2>/dev/null'
  if handle then
    local result = handle:read '*a'
    handle:close()
    if result and result ~= '' then
      return true
    end
  end
  vim.notify('cursor-agent CLI not found. Please install it first:\ncurl https://cursor.com/install -fsSL | bash', vim.log.levels.ERROR)
  return false
end

-- Utility: Get file context
local function get_file_context()
  local bufnr = vim.api.nvim_get_current_buf()
  local filepath = vim.api.nvim_buf_get_name(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local content = table.concat(lines, '\n')

  return {
    filepath = filepath,
    content = content,
    bufnr = bufnr,
  }
end

-- Utility: Get visual selection
local function get_visual_selection()
  local start_pos = vim.fn.getpos "'<"
  local end_pos = vim.fn.getpos "'>"
  local start_line = start_pos[2] - 1
  local end_line = end_pos[2]

  local lines = vim.api.nvim_buf_get_lines(0, start_line, end_line, false)
  return table.concat(lines, '\n')
end

-- Utility: Run cursor-agent command
local function run_cursor_agent(cmd, args)
  if not check_cursor_agent() then
    return nil
  end

  local full_cmd = string.format('cursor-agent %s %s 2>&1', cmd, args)
  local handle = io.popen(full_cmd)
  if not handle then
    vim.notify('Failed to execute cursor-agent', vim.log.levels.ERROR)
    return nil
  end

  local result = handle:read '*a'
  handle:close()

  return result
end

-- Create an input buffer for multi-line prompts
local function create_input_buffer(title, initial_lines, callback)
  -- Save the original window and buffer
  local original_win = vim.api.nvim_get_current_win()
  local original_buf = vim.api.nvim_get_current_buf()

  -- Create a new buffer for input
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
  vim.api.nvim_buf_set_option(buf, 'filetype', 'markdown')
  vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_name(buf, 'Cursor Input')

  -- Set initial content with instructions
  local instructions = {
    '# ' .. title,
    '',
    '<!-- Type your prompt below. You can use multiple lines, paste JSON, code, etc. -->',
    '<!-- Press <Esc> then <leader><CR> to submit (or <C-j> in insert mode) -->',
    '<!-- Press :q to cancel | <C-w>h/l to switch windows -->',
    '',
    '---',
    '',
  }

  if initial_lines then
    vim.list_extend(instructions, initial_lines)
    table.insert(instructions, '') -- Add blank line after initial content
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, instructions)

  -- Open in a vertical split on the right
  vim.cmd 'vsplit'
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  vim.api.nvim_win_set_width(win, math.floor(vim.o.columns * 0.4))

  -- Move cursor to the end of the buffer for typing
  local line_count = vim.api.nvim_buf_line_count(buf)
  vim.api.nvim_win_set_cursor(win, { line_count, 0 })

  -- Function to submit the prompt
  local function submit()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    
    -- Remove instruction lines (first 8 lines)
    local prompt_lines = {}
    for i = 9, #lines do
      table.insert(prompt_lines, lines[i])
    end
    
    local prompt = table.concat(prompt_lines, '\n'):gsub('^%s*(.-)%s*$', '%1') -- trim whitespace
    
    if prompt == '' then
      vim.notify('Prompt is empty', vim.log.levels.WARN)
      return
    end
    
    -- Make buffer read-only and add separator
    vim.api.nvim_buf_set_option(buf, 'modifiable', true)
    vim.api.nvim_buf_set_lines(buf, -1, -1, false, {
      '',
      '---',
      '',
      '⏳ Waiting for Cursor Agent...',
      '',
    })
    vim.api.nvim_buf_set_option(buf, 'modifiable', false)
    
    -- Show notification
    vim.notify('🤖 Sending to Cursor Agent...', vim.log.levels.INFO)
    
    -- Scroll to bottom
    local line_count = vim.api.nvim_buf_line_count(buf)
    vim.api.nvim_win_set_cursor(win, { line_count, 0 })
    
    -- Use vim.defer_fn to allow UI to update, then get response
    vim.defer_fn(function()
      -- Call the callback with the prompt and buffer info
      callback(prompt, buf, win)
    end, 100)
  end

  -- Function to cancel
  local function cancel()
    vim.notify('Cancelled', vim.log.levels.INFO)
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
    if vim.api.nvim_win_is_valid(original_win) then
      vim.api.nvim_set_current_win(original_win)
    end
  end

  -- Set up keymaps
  -- Submit with <leader><CR> (works everywhere)
  vim.keymap.set('n', '<leader><CR>', submit, { buffer = buf, desc = 'Submit prompt' })
  vim.keymap.set('i', '<leader><CR>', function()
    vim.cmd 'stopinsert'
    submit()
  end, { buffer = buf, desc = 'Submit prompt' })
  
  -- Also allow <C-j> as alternative (more reliable than <C-s>)
  vim.keymap.set('n', '<C-j>', submit, { buffer = buf, desc = 'Submit prompt' })
  vim.keymap.set('i', '<C-j>', function()
    vim.cmd 'stopinsert'
    submit()
  end, { buffer = buf, desc = 'Submit prompt' })
  
  -- Cancel with :q or <leader>q
  vim.keymap.set('n', '<leader>q', cancel, { buffer = buf, desc = 'Cancel prompt' })
  
  -- Add user command for quitting
  vim.api.nvim_buf_create_user_command(buf, 'Q', cancel, {})
  vim.api.nvim_buf_create_user_command(buf, 'Quit', cancel, {})

  -- Start in insert mode at the end
  vim.cmd 'startinsert!'
end

-- Create a floating window for chat responses
local function create_float_window(content)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
  vim.api.nvim_buf_set_option(buf, 'filetype', 'markdown')

  -- Split content into lines
  local lines = vim.split(content, '\n')
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)

  -- Calculate window size (80% of editor size)
  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.8)

  -- Calculate starting position
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
    title = ' Cursor Agent Response ',
    title_pos = 'center',
  }

  local win = vim.api.nvim_open_win(buf, true, opts)
  vim.api.nvim_win_set_option(win, 'wrap', true)
  vim.api.nvim_win_set_option(win, 'linebreak', true)

  -- Keymaps for the floating window
  vim.keymap.set('n', 'q', '<cmd>close<CR>', { buffer = buf, nowait = true })
  vim.keymap.set('n', '<Esc>', '<cmd>close<CR>', { buffer = buf, nowait = true })

  return buf, win
end

-- Chat command: Interactive chat with cursor-agent
function M.chat(prompt_text)
  if prompt_text and prompt_text ~= '' then
    -- Direct prompt provided, execute immediately
    local ctx = get_file_context()

    vim.notify('Querying Cursor Agent...', vim.log.levels.INFO)

    local result = run_cursor_agent('chat', string.format('"%s"', vim.fn.shellescape(prompt_text)))

    if result then
      create_float_window(result)
    end
  else
    -- No prompt provided, open input buffer
    create_input_buffer('Cursor Chat', nil, function(prompt, response_buf, response_win)
      vim.notify('⏳ Cursor Agent is thinking...', vim.log.levels.INFO)

      -- Run cursor-agent chat with progress updates
      vim.defer_fn(function()
        local result = run_cursor_agent('chat', string.format('"%s"', vim.fn.shellescape(prompt)))

        if result then
          vim.notify('✅ Response received!', vim.log.levels.INFO)
          
          -- Display response in the same buffer
          if vim.api.nvim_buf_is_valid(response_buf) then
            vim.api.nvim_buf_set_option(response_buf, 'modifiable', true)
            
            -- Remove the loading message
            local line_count = vim.api.nvim_buf_line_count(response_buf)
            vim.api.nvim_buf_set_lines(response_buf, line_count - 2, -1, false, {})
            
            -- Add response
            local response_lines = { '# Response:', '' }
            for line in result:gmatch('[^\r\n]+') do
              table.insert(response_lines, line)
            end
            table.insert(response_lines, '')
            table.insert(response_lines, '---')
            table.insert(response_lines, '')
            table.insert(response_lines, '<!-- Press :q to close | <C-w>h to go back to your file -->')
            
            vim.api.nvim_buf_set_lines(response_buf, -1, -1, false, response_lines)
            vim.api.nvim_buf_set_option(response_buf, 'modifiable', false)
            
            -- Scroll to show response
            if vim.api.nvim_win_is_valid(response_win) then
              local new_line_count = vim.api.nvim_buf_line_count(response_buf)
              vim.api.nvim_win_set_cursor(response_win, { new_line_count, 0 })
            end
          end
        else
          vim.notify('❌ Failed to get response from Cursor Agent', vim.log.levels.ERROR)
          
          if vim.api.nvim_buf_is_valid(response_buf) then
            vim.api.nvim_buf_set_option(response_buf, 'modifiable', true)
            vim.api.nvim_buf_set_lines(response_buf, -1, -1, false, {
              '',
              '❌ Error: Failed to get response from Cursor Agent',
              '',
              'Press :q to close',
            })
            vim.api.nvim_buf_set_option(response_buf, 'modifiable', false)
          end
        end
      end, 50)
    end)
  end
end

-- Chat with visual selection
function M.chat_visual()
  local selection = get_visual_selection()
  if not selection or selection == '' then
    vim.notify('No selection found', vim.log.levels.WARN)
    return
  end

  -- Prepare initial lines with the selected code
  local initial_lines = {
    '',
    '# Selected Code:',
    '```',
  }
  for line in selection:gmatch '[^\r\n]+' do
    table.insert(initial_lines, line)
  end
  table.insert(initial_lines, '```')
  table.insert(initial_lines, '')

  create_input_buffer('Cursor Chat (with selection)', initial_lines, function(prompt, response_buf, response_win)
    local full_prompt = string.format('%s\n\nContext:\n```\n%s\n```', prompt, selection)

    vim.notify('⏳ Cursor Agent is thinking...', vim.log.levels.INFO)

    -- Run cursor-agent chat
    vim.defer_fn(function()
      local result = run_cursor_agent('chat', string.format('"%s"', vim.fn.shellescape(full_prompt)))

      if result then
        vim.notify('✅ Response received!', vim.log.levels.INFO)
        
        -- Display response in the same buffer
        if vim.api.nvim_buf_is_valid(response_buf) then
          vim.api.nvim_buf_set_option(response_buf, 'modifiable', true)
          
          -- Remove the loading message
          local line_count = vim.api.nvim_buf_line_count(response_buf)
          vim.api.nvim_buf_set_lines(response_buf, line_count - 2, -1, false, {})
          
          -- Add response
          local response_lines = { '# Response:', '' }
          for line in result:gmatch('[^\r\n]+') do
            table.insert(response_lines, line)
          end
          table.insert(response_lines, '')
          table.insert(response_lines, '---')
          table.insert(response_lines, '')
          table.insert(response_lines, '<!-- Press :q to close | <C-w>h to go back to your file -->')
          
          vim.api.nvim_buf_set_lines(response_buf, -1, -1, false, response_lines)
          vim.api.nvim_buf_set_option(response_buf, 'modifiable', false)
          
          -- Scroll to show response
          if vim.api.nvim_win_is_valid(response_win) then
            local new_line_count = vim.api.nvim_buf_line_count(response_buf)
            vim.api.nvim_win_set_cursor(response_win, { new_line_count, 0 })
          end
        end
      else
        vim.notify('❌ Failed to get response from Cursor Agent', vim.log.levels.ERROR)
      end
    end, 50)
  end)
end

-- Apply command: Generate and show code changes in diff view
function M.apply(prompt_text)
  -- Get current file context first
  local ctx = get_file_context()
  if not ctx.filepath or ctx.filepath == '' then
    vim.notify('No file open', vim.log.levels.WARN)
    return
  end

  if prompt_text and prompt_text ~= '' then
    -- Direct prompt provided, execute immediately
    M.state.original_bufnr = ctx.bufnr
    M.state.original_winnr = vim.api.nvim_get_current_win()
    M.state.current_file = ctx.filepath

    vim.notify('Generating changes with Cursor Agent...', vim.log.levels.INFO)

    local full_prompt = string.format('Apply the following changes to the code:\n%s', prompt_text)

    local result = run_cursor_agent('chat', string.format('"%s"', vim.fn.shellescape(full_prompt)))

    if result then
      M.show_diff_view(result, ctx)
    end
  else
    -- No prompt provided, open input buffer
    create_input_buffer('Cursor Apply', nil, function(prompt, response_buf, response_win)
      M.state.original_bufnr = ctx.bufnr
      M.state.original_winnr = vim.api.nvim_get_current_win()
      M.state.current_file = ctx.filepath

      vim.notify('⏳ Cursor Agent is generating code changes...', vim.log.levels.INFO)

      vim.defer_fn(function()
        local full_prompt = string.format('Apply the following changes to the code:\n%s', prompt)

        local result = run_cursor_agent('chat', string.format('"%s"', vim.fn.shellescape(full_prompt)))

        if result then
          -- Close the input buffer before opening diff
          if vim.api.nvim_buf_is_valid(response_buf) then
            vim.api.nvim_buf_delete(response_buf, { force = true })
          end
          
          vim.notify('✅ Changes ready! Opening diff view...', vim.log.levels.INFO)
          M.show_diff_view(result, ctx)
        else
          vim.notify('❌ Failed to generate changes from Cursor Agent', vim.log.levels.ERROR)
          
          if vim.api.nvim_buf_is_valid(response_buf) then
            vim.api.nvim_buf_set_option(response_buf, 'modifiable', true)
            vim.api.nvim_buf_set_lines(response_buf, -1, -1, false, {
              '',
              '❌ Error: Failed to generate changes',
              '',
              'Press :q to close',
            })
            vim.api.nvim_buf_set_option(response_buf, 'modifiable', false)
          end
        end
      end, 50)
    end)
  end
end

-- Show diff view with proposed changes
function M.show_diff_view(ai_response, ctx)
  -- Create a new buffer for the modified version
  local diff_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(diff_buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(diff_buf, 'bufhidden', 'wipe')

  -- Extract code from the AI response (look for code blocks)
  local code_lines = {}
  local in_code_block = false
  for line in ai_response:gmatch '[^\r\n]+' do
    if line:match '^```' then
      in_code_block = not in_code_block
    elseif in_code_block then
      table.insert(code_lines, line)
    end
  end

  -- If no code blocks found, show the response in a float and return
  if #code_lines == 0 then
    create_float_window(ai_response)
    vim.notify('No code changes detected in response. Showing full response instead.', vim.log.levels.WARN)
    return
  end

  -- Set the new content to the diff buffer
  vim.api.nvim_buf_set_lines(diff_buf, 0, -1, false, code_lines)
  vim.api.nvim_buf_set_option(diff_buf, 'filetype', vim.bo[ctx.bufnr].filetype)

  -- Store state
  M.state.diff_bufnr = diff_buf
  M.state.changes = {} -- Reset changes stack

  -- Create a vertical split
  vim.cmd 'vsplit'
  local diff_win = vim.api.nvim_get_current_win()
  M.state.diff_winnr = diff_win

  -- Show the diff buffer in the new window
  vim.api.nvim_win_set_buf(diff_win, diff_buf)

  -- Go back to original window and enable diff mode
  vim.api.nvim_set_current_win(M.state.original_winnr)
  vim.cmd 'diffthis'

  -- Go to diff window and enable diff mode
  vim.api.nvim_set_current_win(diff_win)
  vim.cmd 'diffthis'

  -- Set up keymaps for diff navigation
  M.setup_diff_keymaps(diff_buf)

  vim.notify('Diff view ready. Use [q/]q to navigate, <leader>qa/qr to accept/reject chunks', vim.log.levels.INFO)
end

-- Set up keymaps for diff view
function M.setup_diff_keymaps(bufnr)
  local opts = { buffer = bufnr, noremap = true, silent = true }

  -- Navigate between changes
  vim.keymap.set('n', ']q', ']c', vim.tbl_extend('force', opts, { desc = 'Next diff chunk' }))
  vim.keymap.set('n', '[q', '[c', vim.tbl_extend('force', opts, { desc = 'Previous diff chunk' }))

  -- Accept current chunk
  vim.keymap.set('n', '<leader>qa', function()
    M.accept_chunk()
  end, vim.tbl_extend('force', opts, { desc = 'Accept current chunk' }))

  -- Reject current chunk (do nothing, just move to next)
  vim.keymap.set('n', '<leader>qr', function()
    vim.cmd 'normal! ]c'
    vim.notify('Chunk rejected (skipped)', vim.log.levels.INFO)
  end, vim.tbl_extend('force', opts, { desc = 'Reject current chunk' }))

  -- Accept all chunks
  vim.keymap.set('n', '<leader>qA', function()
    M.accept_all()
  end, vim.tbl_extend('force', opts, { desc = 'Accept all chunks' }))

  -- Reject all chunks (close diff)
  vim.keymap.set('n', '<leader>qR', function()
    M.close_diff()
    vim.notify('All changes rejected', vim.log.levels.INFO)
  end, vim.tbl_extend('force', opts, { desc = 'Reject all chunks' }))

  -- Undo last acceptance
  vim.keymap.set('n', '<leader>qu', function()
    M.undo_last()
  end, vim.tbl_extend('force', opts, { desc = 'Undo last acceptance' }))

  -- Undo all acceptances
  vim.keymap.set('n', '<leader>qU', function()
    M.undo_all()
  end, vim.tbl_extend('force', opts, { desc = 'Undo all acceptances' }))

  -- Close diff view
  vim.keymap.set('n', 'q', function()
    M.close_diff()
  end, vim.tbl_extend('force', opts, { desc = 'Close diff view' }))
end

-- Accept current chunk
function M.accept_chunk()
  -- Use 'do' to obtain changes from the other buffer
  local cursor_pos = vim.api.nvim_win_get_cursor(M.state.diff_winnr)
  
  -- Switch to original buffer
  vim.api.nvim_set_current_win(M.state.original_winnr)
  
  -- Store the change for undo
  local start_line = vim.fn.line '.'
  local original_lines = vim.api.nvim_buf_get_lines(M.state.original_bufnr, start_line - 1, start_line, false)
  
  -- Accept the change using 'do' (diff obtain)
  vim.cmd 'normal! do'
  
  -- Store for undo
  table.insert(M.state.changes, {
    line = start_line,
    original = original_lines,
  })
  
  -- Return to diff window
  vim.api.nvim_set_current_win(M.state.diff_winnr)
  vim.api.nvim_win_set_cursor(M.state.diff_winnr, cursor_pos)
  
  vim.notify('Chunk accepted', vim.log.levels.INFO)
end

-- Accept all chunks
function M.accept_all()
  -- Switch to original buffer
  vim.api.nvim_set_current_win(M.state.original_winnr)
  
  -- Get all lines from diff buffer
  local diff_lines = vim.api.nvim_buf_get_lines(M.state.diff_bufnr, 0, -1, false)
  local original_lines = vim.api.nvim_buf_get_lines(M.state.original_bufnr, 0, -1, false)
  
  -- Store for undo
  table.insert(M.state.changes, {
    line = 1,
    original = original_lines,
    full_replace = true,
  })
  
  -- Replace all content
  vim.api.nvim_buf_set_lines(M.state.original_bufnr, 0, -1, false, diff_lines)
  
  vim.notify('All changes accepted', vim.log.levels.INFO)
  
  -- Close diff view after a moment
  vim.defer_fn(function()
    M.close_diff()
  end, 500)
end

-- Undo last acceptance
function M.undo_last()
  if #M.state.changes == 0 then
    vim.notify('No changes to undo', vim.log.levels.WARN)
    return
  end
  
  local last_change = table.remove(M.state.changes)
  
  -- Switch to original buffer
  vim.api.nvim_set_current_win(M.state.original_winnr)
  
  if last_change.full_replace then
    -- Restore full content
    vim.api.nvim_buf_set_lines(M.state.original_bufnr, 0, -1, false, last_change.original)
  else
    -- Restore specific line
    vim.api.nvim_buf_set_lines(M.state.original_bufnr, last_change.line - 1, last_change.line, false, last_change.original)
  end
  
  -- Return to diff window
  vim.api.nvim_set_current_win(M.state.diff_winnr)
  
  vim.notify('Last change undone', vim.log.levels.INFO)
end

-- Undo all acceptances
function M.undo_all()
  if #M.state.changes == 0 then
    vim.notify('No changes to undo', vim.log.levels.WARN)
    return
  end
  
  -- Undo in reverse order
  while #M.state.changes > 0 do
    M.undo_last()
  end
  
  vim.notify('All changes undone', vim.log.levels.INFO)
end

-- Close diff view
function M.close_diff()
  -- Disable diff mode in both windows
  if M.state.original_winnr and vim.api.nvim_win_is_valid(M.state.original_winnr) then
    vim.api.nvim_set_current_win(M.state.original_winnr)
    vim.cmd 'diffoff'
  end
  
  if M.state.diff_winnr and vim.api.nvim_win_is_valid(M.state.diff_winnr) then
    vim.api.nvim_win_close(M.state.diff_winnr, true)
  end
  
  -- Clean up state
  M.state.diff_bufnr = nil
  M.state.diff_winnr = nil
  M.state.original_bufnr = nil
  M.state.original_winnr = nil
end

-- Setup function
function M.setup()
  -- Create user commands
  vim.api.nvim_create_user_command('CursorChat', function(opts)
    M.chat(opts.args)
  end, { nargs = '?', desc = 'Chat with Cursor Agent' })

  vim.api.nvim_create_user_command('CursorApply', function(opts)
    M.apply(opts.args)
  end, { nargs = '?', desc = 'Apply changes with Cursor Agent' })

  -- Global keymaps
  vim.keymap.set('n', '<leader>qc', function()
    M.chat()
  end, { desc = 'Cursor: Chat' })

  vim.keymap.set('v', '<leader>qv', function()
    M.chat_visual()
  end, { desc = 'Cursor: Chat with selection' })

  vim.keymap.set('n', '<leader>qa', function()
    M.apply()
  end, { desc = 'Cursor: Apply changes' })

  -- Check if cursor-agent is installed
  vim.defer_fn(function()
    if not check_cursor_agent() then
      vim.notify(
        'cursor-agent CLI not found. Install it with:\ncurl https://cursor.com/install -fsSL | bash\n\nThen authenticate with: cursor-agent login',
        vim.log.levels.WARN
      )
    end
  end, 1000)
end

return M

