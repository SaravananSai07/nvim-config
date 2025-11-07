local M = {}

M.context = {}

function M.add_file(filepath)
  local content = vim.fn.readfile(filepath)
  if not content then
    vim.notify('Could not read file: ' .. filepath, vim.log.levels.ERROR)
    return
  end
  
  table.insert(M.context, {
    type = 'file',
    filepath = filepath,
    content = table.concat(content, '\n'),
  })

  vim.notify('Added to context: ' .. filepath, vim.log.levels.INFO)
end

function M.add_selection()
  local start_pos = vim.fn.getpos "'<"
  local end_pos = vim.fn.getpos "'>"
  local start_line = start_pos[2]
  local end_line = end_pos[2]

  local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
  local selection = table.concat(lines, '\n')

  if not selection or selection == '' then
    vim.notify('No selection found', vim.log.levels.WARN)
    return
  end

  table.insert(M.context, {
    type = 'selection',
    content = selection,
  })

  vim.notify('Added selection to context', vim.log.levels.INFO)
end

function M.get_context()
  if #M.context == 0 then
    return ''
  end

  local context_str = 'Context:\n'
  for _, item in ipairs(M.context) do
    if item.type == 'file' then
      context_str = context_str .. string.format('File: %s\n```\n%s\n```\n', item.filepath, item.content)
    elseif item.type == 'selection' then
      context_str = context_str .. string.format('Selection:\n```\n%s\n```\n', item.content)
    end
  end

  return context_str
end

function M.clear_context()
  M.context = {}
  vim.notify('Context cleared', vim.log.levels.INFO)
end

return M
