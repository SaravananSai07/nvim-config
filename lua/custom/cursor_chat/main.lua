local M = {}
local ui = require('custom.cursor_chat.ui')
local history = require('custom.cursor_chat.history')
local context = require('custom.cursor_chat.context')

-- Available models (based on cursor-agent CLI --help)
M.models = {
  { name = 'Claude Sonnet 4 (Thinking)', value = 'sonnet-4-thinking' },
  { name = 'Claude Sonnet 4', value = 'sonnet-4' },
  { name = 'GPT-5', value = 'gpt-5' },
  { name = 'Auto', value = 'auto' },
}

-- State management
M.state = {
  diff_bufnr = nil,
  diff_winnr = nil,
  original_bufnr = nil,
  original_winnr = nil,
  changes = {}, -- Stack of applied changes for undo
  current_file = nil,
  current_model = 'sonnet-4-thinking', -- Default to thinking model
  streaming_job = nil, -- Job ID for streaming responses
  is_authenticated = nil, -- Cache auth status
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

-- Utility: Check if cursor-agent is authenticated
local function check_auth()
  if M.state.is_authenticated ~= nil then
    return M.state.is_authenticated
  end
  
  local handle = io.popen 'cursor-agent status 2>&1'
  if handle then
    local result = handle:read '*a'
    handle:close()
    if result and result:match('Not logged in') then
      M.state.is_authenticated = false
      vim.notify('cursor-agent not authenticated. Run: cursor-agent login', vim.log.levels.WARN)
      return false
    end
    M.state.is_authenticated = true
    return true
  end
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
-- callbacks: { on_thinking = fn, on_text = fn, on_tool = fn, on_complete = fn, on_error = fn }
local function run_cursor_agent_streaming(prompt, model, callbacks)
  if not check_cursor_agent() then
    return
  end
  
  if not check_auth() then
    return
  end

  -- Build command as array (proper way for jobstart)
  local selected_model = model or M.state.current_model
  local cmd = {
    'cursor-agent',
    '--print',
    '--output-format', 'stream-json',
    '--stream-partial-output',
    '--model', selected_model,
    prompt
  }

  local has_received_data = false
  local accumulated_text = ''
  local is_thinking = false

  -- Kill any existing streaming job
  if M.state.streaming_job then
    vim.fn.jobstop(M.state.streaming_job)
    M.state.streaming_job = nil
  end

  -- Show model being used
  vim.schedule(function()
    vim.notify(string.format('🤖 Starting %s...', selected_model), vim.log.levels.INFO)
  end)

  -- Start streaming job
  M.state.streaming_job = vim.fn.jobstart(cmd, {
    on_stdout = function(_, data, _)
      for _, line in ipairs(data) do
        if line ~= '' then
          has_received_data = true
          
          -- Parse JSON chunks
          local ok, parsed = pcall(vim.json.decode, line)
          if ok and parsed then
            -- Handle different message types from cursor-agent stream-json
            
            -- Thinking content
            if parsed.type == 'thinking' then
              if not is_thinking then
                is_thinking = true
                vim.schedule(function()
                  ui.start_thinking()
                end)
              end
              local thinking_content = parsed.content or parsed.text or ''
              if thinking_content ~= '' then
                vim.schedule(function()
                  callbacks.on_thinking(thinking_content)
                end)
              end
              
            -- Text/assistant response
            elseif parsed.type == 'text' or parsed.type == 'content' then
              if is_thinking then
                is_thinking = false
                vim.schedule(function()
                  ui.end_thinking()
                end)
              end
              local text_content = parsed.content or parsed.text or ''
              if text_content ~= '' then
                accumulated_text = accumulated_text .. text_content
                vim.schedule(function()
                  callbacks.on_text(text_content)
                end)
              end
              
            -- Assistant message with nested content
            elseif parsed.type == 'assistant' and parsed.message then
              local content = parsed.message.content
              if content then
                for _, item in ipairs(content) do
                  -- Extract content from either field (API may use either)
                  local item_content = item.content or item.text or ''
                  
                  if item.type == 'thinking' then
                    if not is_thinking then
                      is_thinking = true
                      vim.schedule(function()
                        ui.start_thinking()
                      end)
                    end
                    if item_content ~= '' then
                      vim.schedule(function()
                        callbacks.on_thinking(item_content)
                      end)
                    end
                  elseif item.type == 'text' then
                    if is_thinking then
                      is_thinking = false
                      vim.schedule(function()
                        ui.end_thinking()
                      end)
                    end
                    if item_content ~= '' then
                      accumulated_text = accumulated_text .. item_content
                      vim.schedule(function()
                        callbacks.on_text(item_content)
                      end)
                    end
                  end
                end
              end
              
            -- Tool calls (file reads, commands, etc.)
            elseif parsed.type == 'tool_call' or parsed.type == 'tool_use' then
              vim.schedule(function()
                if callbacks.on_tool then
                  callbacks.on_tool(parsed)
                end
                -- Show tool use in UI
                local tool_name = parsed.name or parsed.tool or 'tool'
                ui.append_tool_use(tool_name, parsed)
              end)
              
            -- System init message
            elseif parsed.type == 'system' and parsed.subtype == 'init' then
              if parsed.model then
                vim.schedule(function()
                  vim.notify(string.format('🤖 Model: %s', parsed.model), vim.log.levels.INFO)
                end)
              end
              
            -- Result/completion message
            elseif parsed.type == 'result' or parsed.type == 'done' then
              vim.schedule(function()
                if callbacks.on_complete then
                  callbacks.on_complete(accumulated_text)
                end
              end)
            end
          else
            -- JSON parse failed - might be partial line, buffer it
            -- For now, just skip malformed lines
          end
        end
      end
    end,
    on_stderr = function(_, data, _)
      for _, line in ipairs(data) do
        if line ~= '' and not line:match('^%s*$') then
          vim.schedule(function()
            if callbacks.on_error then
              callbacks.on_error(line)
            end
            -- Don't spam notifications for every stderr line
            if line:match('error') or line:match('Error') then
              vim.notify('Cursor Agent: ' .. line, vim.log.levels.ERROR)
            end
          end)
        end
      end
    end,
    on_exit = function(_, exit_code, _)
      M.state.streaming_job = nil
      vim.schedule(function()
        ui.end_thinking()
        if exit_code == 0 then
          if not has_received_data then
            vim.notify('⚠️  No response received - check authentication with: cursor-agent status', vim.log.levels.WARN)
          else
            vim.notify('✅ Response complete', vim.log.levels.INFO)
          end
        else
          vim.notify(string.format('❌ Agent exited with code %d', exit_code), vim.log.levels.ERROR)
        end
      end)
    end,
  })

  -- Note: Do NOT use chansend - the prompt is already passed as argument to cmd
  if M.state.streaming_job <= 0 then
    vim.notify('Failed to start cursor-agent job', vim.log.levels.ERROR)
    M.state.streaming_job = nil
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
  -- Parse @file mentions from prompt and add to context
  local files_to_add, clean_prompt = context.parse_mentions(prompt)
  for _, filepath in ipairs(files_to_add) do
    context.add_file(filepath)
  end
  
  local full_prompt = context.get_context() .. clean_prompt
  
  -- Add user message to history
  ui.update_history('**You:**\n\n' .. prompt)
  
  -- Add assistant header
  ui.update_history('\n**Assistant:**\n')

  run_cursor_agent_streaming(full_prompt, M.state.current_model, {
    on_thinking = function(chunk)
      ui.append_thinking(chunk)
    end,
    on_text = function(chunk)
      ui.append_to_history(chunk)
    end,
    on_tool = function(tool_data)
      -- Tool use is handled in run_cursor_agent_streaming
    end,
    on_complete = function(full_response)
      context.clear_context()
    end,
    on_error = function(error_msg)
      ui.append_to_history('\n\n⚠️ Error: ' .. error_msg)
    end,
  })
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

-- Add file to context via telescope
function M.add_file_picker()
  context.pick_file_to_add()
end

-- Clear context
function M.clear_context()
  context.clear_context()
  vim.notify('Context cleared', vim.log.levels.INFO)
end

function M.apply(prompt_arg)
  -- If prompt provided as argument, use it directly
  if prompt_arg and prompt_arg ~= '' then
    M._do_apply(prompt_arg)
    return
  end
  
  -- Otherwise, prompt for input
  vim.ui.input({ prompt = 'Prompt for changes:' }, function(prompt)
    if not prompt or prompt == '' then
      return
    end
    M._do_apply(prompt)
  end)
end

-- Internal function to perform the apply operation
function M._do_apply(prompt)
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
    ui.show_context(ai_response)
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

  vim.notify('Diff view ready. Use ]c/[c to navigate, <leader>ca/cr to accept/reject chunks', vim.log.levels.INFO)
end

-- Set up keymaps for diff view
function M.setup_diff_keymaps(bufnr)
  local opts = { buffer = bufnr, noremap = true, silent = true }

  -- Note: ]c and [c are built-in vim diff navigation commands, no need to remap

  -- Accept current chunk
  vim.keymap.set('n', '<leader>ca', function()
    M.accept_chunk()
  end, vim.tbl_extend('force', opts, { desc = 'Accept current chunk' }))

  -- Reject current chunk (do nothing, just move to next)
  vim.keymap.set('n', '<leader>cr', function()
    vim.cmd 'normal! ]c'
    vim.notify('Chunk rejected (skipped)', vim.log.levels.INFO)
  end, vim.tbl_extend('force', opts, { desc = 'Reject current chunk' }))

  -- Accept all chunks
  vim.keymap.set('n', '<leader>cA', function()
    M.accept_all()
  end, vim.tbl_extend('force', opts, { desc = 'Accept all chunks' }))

  -- Reject all chunks (close diff)
  vim.keymap.set('n', '<leader>cR', function()
    M.close_diff()
    vim.notify('All changes rejected', vim.log.levels.INFO)
  end, vim.tbl_extend('force', opts, { desc = 'Reject all chunks' }))

  -- Undo last acceptance
  vim.keymap.set('n', '<leader>cu', function()
    M.undo_last()
  end, vim.tbl_extend('force', opts, { desc = 'Undo last acceptance' }))

  -- Undo all acceptances
  vim.keymap.set('n', '<leader>cU', function()
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
    -- Check if chat window exists and buffer is valid
    if not ui.state.history_buf or not vim.api.nvim_buf_is_valid(ui.state.history_buf) then
      -- No existing chat, just open a new one
      M.chat()
      return
    end
    
    -- Save existing chat before clearing
    history.save_chat(ui.state.history_buf)
    
    -- Clear the history buffer and add welcome message
    vim.api.nvim_buf_set_option(ui.state.history_buf, 'modifiable', true)
    vim.api.nvim_buf_set_lines(ui.state.history_buf, 0, -1, false, {
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
    vim.api.nvim_buf_set_option(ui.state.history_buf, 'modifiable', false)
    
    -- Clear context for new chat
    context.clear_context()
    
    vim.notify('Started new chat (previous chat saved)', vim.log.levels.INFO)
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
    if opts.fargs[1] then
      context.add_file(opts.fargs[1])
    else
      context.pick_file_to_add()
    end
  end, { nargs = '?', complete = 'file', desc = 'Add a file to the chat context' })
  
  vim.api.nvim_create_user_command('CursorAddSelection', function()
    context.add_selection()
  end, { range = true, desc = 'Add the visual selection to the chat context' })

  vim.api.nvim_create_user_command('CursorShowContext', function()
    ui.show_context(context.get_context())
  end, { desc = 'Show the current chat context' })

  vim.api.nvim_create_user_command('CursorClearContext', function()
    M.clear_context()
  end, { desc = 'Clear the chat context' })

  vim.api.nvim_create_user_command('CursorModel', function()
    show_model_selector()
  end, { desc = 'Select Cursor Agent model' })

  -- Global keymaps (using <leader>c for Cursor)
  vim.keymap.set('n', '<leader>cc', function()
    M.chat()
  end, { desc = 'Cursor: Open Chat' })

  vim.keymap.set('v', '<leader>cc', function()
    M.chat_visual()
  end, { desc = 'Cursor: Chat with selection' })

  vim.keymap.set('n', '<leader>cf', function()
    M.add_file_picker()
  end, { desc = 'Cursor: Add file to context' })

  vim.keymap.set('v', '<leader>cs', function()
    context.add_selection()
    vim.notify('Selection added to context', vim.log.levels.INFO)
  end, { desc = 'Cursor: Add selection to context' })

  vim.keymap.set('n', '<leader>cx', function()
    M.clear_context()
  end, { desc = 'Cursor: Clear context' })

  vim.keymap.set('n', '<leader>cv', function()
    ui.show_context(context.get_context())
  end, { desc = 'Cursor: View context' })

  vim.keymap.set('n', '<leader>cm', function()
    show_model_selector()
  end, { desc = 'Cursor: Select model' })

  -- Check if cursor-agent is installed and authenticated
  vim.defer_fn(function()
    if not check_cursor_agent() then
      vim.notify(
        'cursor-agent CLI not found. Install it with:\ncurl https://cursor.com/install -fsSL | bash\n\nThen authenticate with: cursor-agent login',
        vim.log.levels.WARN
      )
    else
      check_auth()
    end
  end, 1000)
end

return M
