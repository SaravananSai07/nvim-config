-- You can add your own plugins here or in other files in this directory!
--  I promise not to create any merge conflicts in this directory :)
--
-- See the kickstart.nvim README for more information
return {

  {
    'SaravananSai07/takku.nvim',
    dir = '~/SS/takku.nvim',
    dependencies = {
      'nvim-telescope/telescope.nvim',
    },
    opts = { -- Skip this if default bindings and config works for you
      mappings = {
        next_file = '<leader>tj',
        prev_file = '<leader>tk',
        add_file = '<leader>ta',
        delete_file = '<leader>td',
        goto_file = '<leader>t',
        show_list = '<leader>tl',
      },
      enable_telescope_integration = true,
      notifications = true,
    },
    event = 'VimEnter',
    config = function(_, opts)
      require('takku').setup(opts)
    end,
  },

  {
    'SaravananSai07/gitvu',
    dir = '~/SS/gitvu',
    opts = {
      {
        keymaps = {
          toggle_lens = '<Leader>ga', -- Toggle blame info
          next_conflict = '<Leader>gn', -- Go to next conflict
          prev_conflict = '<Leader>gp', -- Go to previous conflict
          take_current = '<Leader>g1', -- Keep current changes (at cursor)
          take_incoming = '<Leader>g2', -- Keep incoming changes (at cursor)
          take_both = '<Leader>g3', -- Combine both (at cursor)
        },
        lens = {
          format = '👤 %s', -- Customize blame format
        },
      },
    },
    event = 'VimEnter',
    config = function(_, opts)
      require('gitvu').setup(opts)
    end,
  },

  -- {
  --   'zbirenbaum/copilot.lua',
  --   cmd = 'Copilot',
  --   event = 'InsertEnter',
  --   config = function()
  --     require('copilot').setup {
  --       suggestion = { enabled = false },
  --       panel = { enabled = false },
  --     }
  --   end,
  -- },
  -- {
  --   'zbirenbaum/copilot-cmp',
  --   dependencies = {
  --     'saghen/blink.cmp',
  --   },
  --   after = { 'copilot.lua', 'blink.cmp' },
  --   config = function()
  --     require('copilot_cmp').setup()
  --   end,
  -- },

  -- {
  --   'olimorris/codecompanion.nvim',
  --   dependencies = {
  --     'nvim-lua/plenary.nvim',
  --     'nvim-treesitter/nvim-treesitter',
  --   },
  --   config = function()
  --     require('codecompanion').setup {
  --       adapter = 'ollama',
  --       adapter_config = {
  --         model = 'deepseek-coder-v2:16b',
  --         url = 'http://localhost:11434',
  --       },
  --       display = {
  --         action_palette = {
  --           provider = 'telescope',
  --         },
  --       },
  --     }
  --   end,
  -- },
  --
  {
    'olimorris/codecompanion.nvim',
    dependencies = { 'nvim-lua/plenary.nvim', 'nvim-treesitter/nvim-treesitter' },
    opts = {
      strategies = {
        inline = {
          adapter = 'ollama',
          inline = false,
          keymaps = { toggle = '<leader>ac', accept = '<Tab>' },
        },
        chat = {
          adapter = 'ollama',
          keymaps = {
            toggle = '<leader>aa',
            add = '<leader>av',
            options = { modes = { n = '?' } },
          },
        },
      },
      adapters = {
        ollama = function()
          return require('codecompanion.adapters').extend('ollama', {
            schema = { model = { default = 'deepseek-coder-v2:16b' } },
            env = { url = 'http://localhost:11434' },
          })
        end,
      },
      display = {
        action_palette = { provider = 'telescope' },
        chat = {
          icons = { user = '', assistant = '' },
        },
      },
    },
    config = function(_, opts)
      require('codecompanion').setup(opts)
    end,
  },
  -- {
  --    'olimorris/codecompanion.nvim',
  --    dependencies = {
  --      'nvim-lua/plenary.nvim',
  --      'nvim-treesitter/nvim-treesitter',
  --      {
  --        'saghen/blink.cmp',
  --        opts = {
  --          sources = {
  --            default = { 'codecompanion' },
  --            providers = {
  --              codecompanion = {
  --                name = 'CodeCompanion',
  --                module = 'codecompanion.providers.completion.blink',
  --                enabled = true,
  --              },
  --            },
  --          },
  --        },
  --      },
  --    },
  --    config = function(_, opts)
  --      require('codecompanion').setup(vim.tbl_deep_extend('force', {
  --        adapter = 'ollama',
  --        adapter_config = {
  --          url = 'http://localhost:11434',
  --          model = 'deepseek-coder-v2:16b',
  --        },
  --        display = {
  --          inline = {
  --            enabled = false, -- Disable auto inline completion by default
  --          },
  --          action_palette = {
  --            provider = 'telescope', -- Use Telescope for action selection
  --          },
  --        },
  --        keymaps = {
  --          ['toggle_inline'] = '<leader>ac', -- toggle inline assist
  --          ['chat'] = '<leader>aa', -- open chat
  --          ['actions'] = '<leader>ao', -- open action palette
  --          ['add_selection'] = '<leader>av', -- use selection in chat
  --        },
  --      }, opts or {}))
  --    end,
  --  },
}
