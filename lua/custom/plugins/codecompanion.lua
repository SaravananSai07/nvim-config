return {
  'olimorris/codecompanion.nvim',
  dependencies = {
    'nvim-lua/plenary.nvim',
    'nvim-telescope/telescope.nvim',
  },
  config = function()
    require('codecompanion').setup {
      adapters = {
        http = {
          ollama = function()
            return require('codecompanion.adapters').extend('ollama', {
              env = {
                url = 'http://127.0.0.1:11434',
                api_key = 'dummy', -- Ollama doesn't require API key but plugin might expect it
              },
              headers = {
                ['Content-Type'] = 'application/json',
              },
              parameters = {
                sync = true,
              },
            })
          end,
        },
      },
      strategies = {
        chat = {
          adapter = 'ollama',
        },
        inline = {
          adapter = 'ollama',
        },
        agent = {
          adapter = 'ollama',
        },
      },
    }

    vim.keymap.set('n', '<leader>aq', '<cmd>CodeCompanionChat<cr>', { desc = 'CodeCompanion: Open Chat' })
    vim.keymap.set('v', '<leader>ai', '<cmd>CodeCompanionChat Add<cr>', { desc = 'CodeCompanion: Add to Chat' })
    vim.keymap.set('n', '<leader>ac', '<cmd>CodeCompanionActions<cr>', { desc = 'CodeCompanion: Actions' })
  end,
}
