return {
  'github/copilot.vim',
  event = 'InsertEnter',
  config = function()
    vim.g.copilot_enabled = true

    vim.g.copilot_no_tab_map = true

    vim.keymap.set('i', '<S-Tab>', 'copilot#Accept("\\<CR>")', {
      expr = true,
      replace_keycodes = false,
      desc = 'Copilot: Accept suggestion',
    })

    vim.keymap.set('i', '<M-]>', '<Plug>(copilot-next)', { desc = 'Copilot: Next suggestion' })
    vim.keymap.set('i', '<M-[>', '<Plug>(copilot-previous)', { desc = 'Copilot: Previous suggestion' })
    vim.keymap.set('i', '<M-\\>', '<Plug>(copilot-dismiss)', { desc = 'Copilot: Dismiss suggestion' })

    vim.keymap.set('n', '<leader>tc', function()
      if vim.g.copilot_enabled == true or vim.g.copilot_enabled == 1 then
        vim.cmd 'Copilot disable'
        vim.g.copilot_enabled = false
        vim.notify('Copilot disabled', vim.log.levels.INFO)
      else
        vim.cmd 'Copilot enable'
        vim.g.copilot_enabled = true
        vim.notify('Copilot enabled', vim.log.levels.INFO)
      end
    end, { desc = '[T]oggle [C]opilot' })

    vim.api.nvim_create_autocmd('User', {
      pattern = 'CopilotStatusUpdate',
      callback = function()
        vim.cmd 'redrawstatus'
      end,
    })
  end,
}

