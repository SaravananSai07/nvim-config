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

  {
    'saecki/crates.nvim',
    event = 'BufRead Cargo.toml',
    opts = {
      completion = {
        cmp = { enabled = false },
        crates = { enabled = true },
      },
    },
  },

  {
    'MeanderingProgrammer/render-markdown.nvim',
    dependencies = { 'nvim-treesitter/nvim-treesitter', 'nvim-tree/nvim-web-devicons' },
    ft = { 'markdown' }, -- Load only for markdown files
    opts = {
      enabled = true,
      -- Render markdown in buffers with these names
      file_types = { 'markdown' },
      -- Code blocks will use treesitter highlighting
      code = {
        enabled = true,
        sign = true,
        style = 'full',
        position = 'left',
        width = 'block',
        left_pad = 0,
        right_pad = 0,
        min_width = 0,
        border = 'thin',
      },
      -- Headings
      heading = {
        enabled = true,
        sign = true,
        position = 'overlay',
        icons = { '󰲡 ', '󰲣 ', '󰲥 ', '󰲧 ', '󰲩 ', '󰲫 ' },
        signs = { '󰫎 ' },
        width = 'full',
        left_pad = 0,
        right_pad = 0,
        min_width = 0,
      },
      -- Bullet points
      bullet = {
        enabled = true,
        icons = { '●', '○', '◆', '◇' },
        left_pad = 0,
        right_pad = 0,
      },
      -- Checkboxes
      checkbox = {
        enabled = true,
        unchecked = { icon = '󰄱 ' },
        checked = { icon = '󰱒 ' },
        custom = {
          todo = { raw = '[-]', rendered = '󰥔 ', highlight = 'RenderMarkdownTodo' },
        },
      },
      -- Inline code
      code_inline = {
        enabled = true,
        highlight = 'RenderMarkdownCode',
      },
      -- Quote blocks
      quote = {
        enabled = true,
        icon = '▋',
        repeat_linebreak = false,
      },
      -- Tables
      pipe_table = {
        enabled = true,
        style = 'full',
        cell = 'padded',
        border = {
          '┌', '┬', '┐',
          '├', '┼', '┤',
          '└', '┴', '┘',
          '│', '─',
        },
      },
      -- Links
      link = {
        enabled = true,
        image = '󰥶 ',
        hyperlink = '󰌹 ',
      },
      -- Anti-conceal: show raw markdown when cursor is on the line
      anti_conceal = {
        enabled = true,
      },
      -- Window options
      win_options = {
        conceallevel = {
          default = vim.o.conceallevel,
          rendered = 3,
        },
        concealcursor = {
          default = vim.o.concealcursor,
          rendered = '',
        },
      },
    },
    config = function(_, opts)
      require('render-markdown').setup(opts)
      
    end,
  },

}
