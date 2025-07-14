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

}
