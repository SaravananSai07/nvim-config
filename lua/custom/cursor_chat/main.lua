local M = {}
local ui = require('custom.cursor_chat.ui')
local history = require('custom.cursor_chat.history')
local context = require('custom.cursor_chat.context')

-- Available models (based on cursor-agent CLI)
M.models = {
  { name = 'Auto (Best Available)', value = 'auto' },
  { name = 'Claude Sonnet 4.5', value = 'sonnet-4.5' },
  { name = 'Claude Sonnet 4.5 (Thinking)', value = 'sonnet-4.5-thinking' },
  { name = 'Claude Opus 4.1', value = 'opus-4.1' },
  { name = 'GPT-5', value = 'gpt-5' },
  { name = 'Cheetah', value = 'cheetah' },
  { name = 'Grok', value = 'grok' },
}

-- State management
M.state = {
  diff_bufnr = nil,
  diff_winnr = nil,
  original_bufnr = nil,
  original_winnr = nil,
  changes = {}, -- Stack of applied changes for undo
  current_file = nil,
  current_model = 'sonnet-4.5', -- Default model
  streaming_job = nil, -- Job ID for streaming responses
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

-- Utility: Run cursor-agent command (non-streaming)
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

-- Utility: Run cursor-agent with streaming support
local function run_cursor_agent_streaming(prompt, model, on_chunk)
  if not check_cursor_agent() then
    return
  end

  -- Build command with streaming options
  local selected_model = model or M.state.current_model
  local cmd = string.format(
    'cursor-agent agent --print --output-format stream-json --stream-partial-output --model %s %s',
    selected_model,
    vim.fn.shellescape(prompt)
  )

  local has_received_data = false

  -- Kill any existing streaming job
  if M.state.streaming_job then
    vim.fn.jobstop(M.state.streaming_job)
    M.state.streaming_job = nil
  end

  -- Start streaming job
  vim.notify('Starting cursor-agent job with command: ' .. cmd, vim.log.levels.INFO)
  M.state.streaming_job = vim.fn.jobstart(cmd, {
    on_stdout = function(_, data, _)
      vim.notify('Received stdout data: ' .. vim.inspect(data), vim.log.levels.INFO)
      for _, line in ipairs(data) do
        if line ~= '' then
          has_received_data = true
          
          -- Parse JSON chunks
          local ok, parsed = pcall(vim.json.decode, line)
          if ok and parsed then
            -- Handle different message types
            if parsed.type == 'assistant' and parsed.message then
              -- Extract text from assistant messages
              local content = parsed.message.content
              if content then
                for _, item in ipairs(content) do
                  if item.type == 'text' and item.text then
                    on_chunk(item.text)
                  end
                end
              end
            elseif parsed.type == 'thinking' then
              ui.set_thinking(true)
            elseif parsed.type == 'system' and parsed.subtype == 'init' then
              -- Show which model is being used
              if parsed.model then
                vim.schedule(function()
                  vim.notify(string.format('🤖 Using model: %s', parsed.model), vim.log.levels.INFO)
                end)
              end
            elseif parsed.type == 'result' then
              -- Final result message
              if parsed.result then
                -- Already accumulated, just notify completion
                vim.schedule(function()
                  vim.notify('✅ Response complete!', vim.log.levels.INFO)
                end)
              end
            end
          else
            -- If JSON parsing fails, maybe it's plain text - show it anyway
            if not line:match('^%s*$') then
              vim.schedule(function()
                -- Don't spam with debug messages
                -- vim.notify('Raw output: ' .. line:sub(1, 100), vim.log.levels.DEBUG)
              end)
            end
          end
        end
      end
    end,
    on_stderr = function(_, data, _)
      vim.notify('Received stderr data: ' .. vim.inspect(data), vim.log.levels.ERROR)
      for _, line in ipairs(data) do
        if line ~= '' then
          vim.schedule(function()
            -- TODO: Show errors in the UI
            vim.notify('Cursor Agent Error: ' .. line, vim.log.levels.ERROR)
          end)
        end
      end
    end,
    on_exit = function(_, exit_code, _)
      vim.notify('Job exited with code: ' .. tostring(exit_code), vim.log.levels.INFO)
      M.state.streaming_job = nil
      ui.set_thinking(false)
      vim.schedule(function()
        if exit_code == 0 then
          if not has_received_data then
            vim.notify('⚠️  No response received - check model availability', vim.log.levels.WARN)
          end
          -- Success notification is already shown in the result handler
        else
          vim.notify(string.format('❌ Agent exited with code %d', exit_code), vim.log.levels.ERROR)
        end
      end)
    end,
  })

  if M.state.streaming_job > 0 then
    vim.fn.chansend(M.state.streaming_job, prompt)
    vim.fn.chanclose(M.state.streaming_job, 'stdin')
  end
end

-- Show model selector
local function show_model_selector(callback)
  local options = {}
  for i, model in ipairs(M.models) do
    local current_marker = (model.value == M.state.current_model) and ' ✓' or ''
    table.insert(options, string.format('%d. %s%s', i, model.name, current_marker))
  end
  
  vim.ui.select(options, {
    prompt = 'Select Model:',
    format_item = function(item)
      return item
    end,
  }, function(choice, idx)
    if idx then
      M.state.current_model = M.models[idx].value
      vim.notify(string.format('🤖 Selected: %s', M.models[idx].name), vim.log.levels.INFO)
      if callback then
        callback()
      end
    end
  end)
end

-- Get current model name
local function get_current_model_name()
  for _, model in ipairs(M.models) do
    if model.value == M.state.current_model then
      return model.name
    end
  end
  return M.state.current_model
end

function M.submit_prompt(prompt)
  local full_prompt = context.get_context() .. prompt
  context.clear_context()

  run_cursor_agent_streaming(full_prompt, M.state.current_model, function(chunk)
    ui.append_to_history(chunk)
  end)
end

-- Chat command: Interactive chat with cursor-agent
function M.chat(prompt_text)
  ui.create_chat_window()
  if prompt_text and prompt_text ~= '' then
    M.submit_prompt(prompt_text)
  end
end

function M.chat_visual()
  context.add_selection()
  ui.create_chat_window()
end

function M.apply()
  vim.ui.input({ prompt = 'Prompt for changes:' }, function(prompt)
    if not prompt or prompt == '' then
      return
    end

    local ctx = get_file_context()
    if not ctx.filepath or ctx.filepath == '' then
      vim.notify('No file open', vim.log.levels.WARN)
      return
    end

    M.state.original_bufnr = ctx.bufnr
    M.state.original_winnr = vim.api.nvim_get_current_win()
    M.state.current_file = ctx.filepath

    local full_prompt = string.format('Apply the following changes to the code:\n%s\n\nFile: %s\n```\n%s\n```', prompt, ctx.filepath, ctx.content)
    
    local result = run_cursor_agent('chat', string.format('"%s"', vim.fn.shellescape(full_prompt)))

    if result then
      M.show_diff_view(result, ctx)
    end
  end)
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

  vim.api.nvim_create_user_command('CursorNewChat', function()
    history.save_chat(ui.state.history_buf)
    -- Clear the history buffer
    vim.api.nvim_buf_set_option(ui.state.history_buf, 'modifiable', true)
    vim.api.nvim_buf_set_lines(ui.state.history_buf, 0, -1, false, { '# New Chat', '', '**Welcome to Cursor Chat!**' })
    vim.api.nvim_buf_set_option(ui.state.history_buf, 'modifiable', false)
  end, { desc = 'Start a new chat' })

  vim.api.nvim_create_user_command('CursorOpenChat', function()
    local chats = history.list_chats()
    if #chats == 0 then
      vim.notify('No chats found for this workspace', vim.log.levels.INFO)
      return
    end
    vim.ui.select(chats, { prompt = 'Select a chat to open' }, function(choice)
      if choice then
        history.load_chat(choice)
      end
    end)
  end, { desc = 'Open a previous chat' })

  vim.api.nvim_create_user_command('CursorAddFile', function(opts)
    context.add_file(opts.fargs[1] or vim.api.nvim_buf_get_name(0))
  end, { nargs = '?', complete = 'file', desc = 'Add a file to the chat context' })
  
  vim.api.nvim_create_user_command('CursorAddSelection', function()
    context.add_selection()
  end, { range = true, desc = 'Add the visual selection to the chat context' })

  vim.api.nvim_create_user_command('CursorShowContext', function()
    ui.show_context(context.get_context())
  end, { desc = 'Show the current chat context' })

  vim.api.nvim_create_user_command('CursorModel', function()
    show_model_selector()
  end, { desc = 'Select Cursor Agent model' })

  -- Global keymaps
  vim.keymap.set('n', '<leader>qc', function()
    M.chat()
  end, { desc = 'Cursor: Chat' })

  vim.keymap.set('v', '<leader>qc', function()
    M.chat_visual()
  end, { desc = 'Cursor: Chat with selection' })

  vim.keymap.set('n', '<leader>qa', function()
    M.apply()
  end, { desc = 'Cursor: Apply changes' })

  vim.keymap.set('n', '<leader>qs', function()
    ui.show_context(context.get_context())
  end, { desc = 'Cursor: Show context' })

  vim.keymap.set('n', '<leader>qm', function()
    show_model_selector()
  end, { desc = 'Cursor: Select model' })

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
