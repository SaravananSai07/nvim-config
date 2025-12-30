local M = {}

M.context = {}

-- Expand file path (handle ~, relative paths, etc.)
local function expand_path(filepath)
  -- Expand ~ to home directory
  if filepath:sub(1, 1) == '~' then
    filepath = vim.fn.expand(filepath)
  end
  
  -- If not absolute, make it relative to current working directory
  if filepath:sub(1, 1) ~= '/' then
    local cwd = vim.fn.getcwd()
    filepath = cwd .. '/' .. filepath
  end
  
  -- Normalize the path
  filepath = vim.fn.fnamemodify(filepath, ':p')
  
  return filepath
end

-- Check if file already in context
local function file_in_context(filepath)
  for _, item in ipairs(M.context) do
    if item.type == 'file' and item.filepath == filepath then
      return true
    end
  end
  return false
end

-- Add a file to context
function M.add_file(filepath)
  if not filepath or filepath == '' then
    vim.notify('No file path provided', vim.log.levels.WARN)
    return false
  end
  
  local expanded_path = expand_path(filepath)
  
  -- Check if file exists
  if vim.fn.filereadable(expanded_path) ~= 1 then
    vim.notify('File not found: ' .. filepath, vim.log.levels.ERROR)
    return false
  end
  
  -- Check if already in context
  if file_in_context(expanded_path) then
    vim.notify('File already in context: ' .. filepath, vim.log.levels.INFO)
    return true
  end
  
  -- Read file content
  local content = vim.fn.readfile(expanded_path)
  if not content then
    vim.notify('Could not read file: ' .. filepath, vim.log.levels.ERROR)
    return false
  end
  
  -- Get file info
  local filename = vim.fn.fnamemodify(expanded_path, ':t')
  local filetype = vim.filetype.match({ filename = filename }) or ''
  
  table.insert(M.context, {
    type = 'file',
    filepath = expanded_path,
    filename = filename,
    filetype = filetype,
    content = table.concat(content, '\n'),
  })

  -- Show shortened path in notification
  local display_path = vim.fn.fnamemodify(expanded_path, ':~:.')
  vim.notify('📄 Added to context: ' .. display_path, vim.log.levels.INFO)
  return true
end

-- Add current buffer to context
function M.add_current_buffer()
  local bufnr = vim.api.nvim_get_current_buf()
  local filepath = vim.api.nvim_buf_get_name(bufnr)
  
  if filepath == '' then
    vim.notify('Current buffer has no file path', vim.log.levels.WARN)
    return false
  end
  
  return M.add_file(filepath)
end

-- Add visual selection to context
function M.add_selection()
  local start_pos = vim.fn.getpos "'<"
  local end_pos = vim.fn.getpos "'>"
  local start_line = start_pos[2]
  local end_line = end_pos[2]
  local start_col = start_pos[3]
  local end_col = end_pos[3]

  local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
  
  if #lines == 0 then
    vim.notify('No selection found', vim.log.levels.WARN)
    return false
  end
  
  -- Handle partial line selections
  if #lines == 1 then
    lines[1] = lines[1]:sub(start_col, end_col)
  else
    lines[1] = lines[1]:sub(start_col)
    lines[#lines] = lines[#lines]:sub(1, end_col)
  end
  
  local selection = table.concat(lines, '\n')

  if not selection or selection == '' then
    vim.notify('No selection found', vim.log.levels.WARN)
    return false
  end

  -- Get current file info for context
  local bufnr = vim.api.nvim_get_current_buf()
  local filepath = vim.api.nvim_buf_get_name(bufnr)
  local filename = vim.fn.fnamemodify(filepath, ':t')
  local filetype = vim.bo[bufnr].filetype or ''
  
  table.insert(M.context, {
    type = 'selection',
    filepath = filepath,
    filename = filename,
    filetype = filetype,
    start_line = start_line,
    end_line = end_line,
    content = selection,
  })

  local line_count = end_line - start_line + 1
  vim.notify(string.format('📝 Added selection to context (%d lines from %s)', line_count, filename), vim.log.levels.INFO)
  return true
end

-- Parse @file:path mentions from prompt text
-- Returns: files_to_add (table), clean_prompt (string with mentions removed)
function M.parse_mentions(prompt)
  local files = {}
  local clean_prompt = prompt
  
  -- Match @file:path patterns (path can be quoted or unquoted)
  -- Pattern 1: @file:"path with spaces"
  for path in prompt:gmatch('@file:"([^"]+)"') do
    table.insert(files, path)
  end
  clean_prompt = clean_prompt:gsub('@file:"[^"]+"', '')
  
  -- Pattern 2: @file:'path with spaces'
  for path in prompt:gmatch("@file:'([^']+)'") do
    table.insert(files, path)
  end
  clean_prompt = clean_prompt:gsub("@file:'[^']+'", '')
  
  -- Pattern 3: @file:path (no spaces)
  for path in prompt:gmatch('@file:([^%s"\']+)') do
    table.insert(files, path)
  end
  clean_prompt = clean_prompt:gsub('@file:[^%s"\']+', '')
  
  -- Also support just @path for common patterns
  -- Pattern 4: @./path or @../path (relative paths)
  for path in prompt:gmatch('@(%.[^%s]+)') do
    if not path:match('^%.%.$') then  -- Exclude just ".."
      table.insert(files, path)
    end
  end
  clean_prompt = clean_prompt:gsub('@%.[^%s]+', '')
  
  -- Trim extra whitespace
  clean_prompt = clean_prompt:gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
  
  return files, clean_prompt
end

-- Pick file to add using telescope
function M.pick_file_to_add()
  local ok, telescope = pcall(require, 'telescope.builtin')
  if not ok then
    vim.notify('Telescope not available. Use :CursorAddFile <path> instead.', vim.log.levels.WARN)
    return
  end
  
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  
  telescope.find_files({
    prompt_title = 'Add File to Context',
    attach_mappings = function(prompt_bufnr, map)
      -- Override default select action
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        
        if selection then
          local filepath = selection.path or selection[1]
          M.add_file(filepath)
        end
      end)
      
      -- Allow multi-select with Tab
      map('i', '<Tab>', function()
        actions.toggle_selection(prompt_bufnr)
        actions.move_selection_next(prompt_bufnr)
      end)
      
      -- Add all selected with Ctrl+a
      map('i', '<C-a>', function()
        local picker = action_state.get_current_picker(prompt_bufnr)
        local selections = picker:get_multi_selection()
        actions.close(prompt_bufnr)
        
        if #selections > 0 then
          for _, selection in ipairs(selections) do
            local filepath = selection.path or selection[1]
            M.add_file(filepath)
          end
        else
          -- No multi-selection, add current selection
          local selection = action_state.get_selected_entry()
          if selection then
            local filepath = selection.path or selection[1]
            M.add_file(filepath)
          end
        end
      end)
      
      return true
    end,
  })
end

-- Get formatted context string for prompt
function M.get_context()
  if #M.context == 0 then
    return ''
  end

  local context_parts = {}
  table.insert(context_parts, '--- CONTEXT ---\n')
  
  for i, item in ipairs(M.context) do
    if item.type == 'file' then
      local display_path = vim.fn.fnamemodify(item.filepath, ':~:.')
      local lang = item.filetype ~= '' and item.filetype or ''
      table.insert(context_parts, string.format(
        'File: %s\n```%s\n%s\n```\n',
        display_path,
        lang,
        item.content
      ))
    elseif item.type == 'selection' then
      local source = item.filename or 'unknown'
      local lines_info = ''
      if item.start_line and item.end_line then
        lines_info = string.format(' (lines %d-%d)', item.start_line, item.end_line)
      end
      local lang = item.filetype ~= '' and item.filetype or ''
      table.insert(context_parts, string.format(
        'Selection from %s%s:\n```%s\n%s\n```\n',
        source,
        lines_info,
        lang,
        item.content
      ))
    end
  end
  
  table.insert(context_parts, '--- END CONTEXT ---\n\n')

  return table.concat(context_parts, '\n')
end

-- Get context summary (for display)
function M.get_context_summary()
  if #M.context == 0 then
    return 'No files in context'
  end
  
  local files = {}
  local selections = 0
  
  for _, item in ipairs(M.context) do
    if item.type == 'file' then
      table.insert(files, vim.fn.fnamemodify(item.filepath, ':t'))
    elseif item.type == 'selection' then
      selections = selections + 1
    end
  end
  
  local parts = {}
  if #files > 0 then
    table.insert(parts, string.format('%d files: %s', #files, table.concat(files, ', ')))
  end
  if selections > 0 then
    table.insert(parts, string.format('%d selections', selections))
  end
  
  return table.concat(parts, ', ')
end

-- Remove item from context by index
function M.remove_item(index)
  if index < 1 or index > #M.context then
    vim.notify('Invalid context index', vim.log.levels.WARN)
    return
  end
  
  local removed = table.remove(M.context, index)
  if removed.type == 'file' then
    vim.notify('Removed from context: ' .. vim.fn.fnamemodify(removed.filepath, ':t'), vim.log.levels.INFO)
  else
    vim.notify('Removed selection from context', vim.log.levels.INFO)
  end
end

-- Clear all context
function M.clear_context()
  local count = #M.context
  M.context = {}
  if count > 0 then
    vim.notify(string.format('Context cleared (%d items removed)', count), vim.log.levels.INFO)
  end
end

-- Get context item count
function M.count()
  return #M.context
end

return M
