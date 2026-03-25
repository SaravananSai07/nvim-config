# Neovim Configuration

Kickstart.nvim-based config using lazy.nvim as the plugin manager.

## Directory Structure

```
init.lua                          — Main config (options, keymaps, plugins)
lua/config/autocmds.lua           — LuaSnip cleanup autocommand
lua/custom/plugins/               — User plugins (auto-loaded by lazy.nvim)
  init.lua                        — takku, gitvu, crates.nvim, render-markdown
  codecompanion.lua               — Ollama AI chat
  copilot.lua                     — GitHub Copilot
  tiny-diagnostics.lua            — Inline diagnostics
lua/kickstart/plugins/            — Optional kickstart modules
  debug.lua                       — DAP (nvim-dap + dap-ui)
  autopairs.lua                   — nvim-autopairs
  gitsigns.lua                    — Git signs + blame
  indent_line.lua                 — indent-blankline (disabled)
  lint.lua                        — nvim-lint (disabled)
  neo-tree.lua                    — File browser (disabled)
```

## LSP

Managed via mason + nvim-lspconfig + mason-lspconfig + mason-tool-installer.

**Configured servers** (in `init.lua` `servers` table ~line 905):
- `gopls` — Go
- `pyright` — Python
- `rust_analyzer` — Rust (clippy check, inlay hints, proc macros, all features)
- `ts_ls` — TypeScript/JavaScript
- `lua_ls` — Lua

LSP keybindings are set up in the `LspAttach` autocmd. Leader key is `<Space>`.

## Formatting

conform.nvim with format-on-save (500ms timeout, LSP fallback):
- lua: `stylua`
- go: `gofmt`, `goimports`
- rust: `rustfmt`

Manual format: `<leader>f`

## Completion

blink.cmp with LuaSnip snippets. Enter to accept, `<C-space>` to toggle menu.

## Treesitter

Parsers: bash, c, diff, html, lua, luadoc, markdown, markdown_inline, query, vim, vimdoc, go, python, javascript, rust, toml, ron. Auto-install enabled.

## Debugging (DAP)

Enabled via `lua/kickstart/plugins/debug.lua`:
- Go: delve (via nvim-dap-go)
- Rust/C/C++: codelldb (Mason-installed)

Keybinds: `<F5>` continue, `<F1>` step-into, `<F2>` step-over, `<F3>` step-out, `<F7>` toggle UI, `<leader>b` breakpoint.

### Go Monorepo Debugging

For repos like `go-services/` with multiple services each having their own `go.mod`:

```
go-services/
  service-a/   (go.mod, main.go)
  service-b/   (go.mod, main.go)
```

A `find_go_module_root()` helper walks up from the current file to the nearest `go.mod`, so delve builds and runs from the correct service directory regardless of nvim's cwd.

**`<F5>` launch configs (picker):**
1. **Launch Service (nearest go.mod)** — auto-detects service root from current file
2. **Debug test** / **Debug test (go.test)** — default dap-go test runners
3. **Attach to running service** — pick from running Go processes

**Workflow:** Open a file in the target service → `<leader>b` to set breakpoints → `<F5>` → select "Launch Service (nearest go.mod)" → DAP UI opens automatically.

### Rust Debugging

Press `<F5>` in a `.rs` file, select "Launch", then provide the path to the compiled binary (defaults to `target/debug/`).

## Keybindings

Leader key: `<Space>`

### General

| Key | Mode | Action |
|-----|------|--------|
| `<Esc>` | n | Clear search highlights |
| `<Esc><Esc>` | t | Exit terminal mode |
| `<leader>q` | n | Open diagnostic quickfix list |
| `<leader>f` | n | Format buffer (conform) |
| `<C-h/j/k/l>` | n | Move focus between windows |

### Search (Telescope)

| Key | Mode | Action |
|-----|------|--------|
| `<leader>sh` | n | Search help tags |
| `<leader>sk` | n | Search keymaps |
| `<leader>sf` | n | Search files |
| `<leader>ss` | n | Search select Telescope builtin |
| `<leader>sw` | n | Search current word |
| `<leader>sg` | n | Search by grep (live) |
| `<leader>sd` | n | Search diagnostics |
| `<leader>sD` | n | Search diagnostics (current buffer) |
| `<leader>sr` | n | Resume last search |
| `<leader>s.` | n | Search recent files |
| `<leader>sF` | n | Search all files (hidden + ignored) |
| `<leader>sb` | n | Search buffers (unsaved marked) |
| `<leader>s/` | n | Search in open files (live grep) |
| `<leader>sc/` | n | Search in current buffer |
| `<leader>sn` | n | Search Neovim config files |
| `<leader>sa` | n | Search all files |
| `<leader><leader>` | n | Switch buffers |

### LSP (active in buffers with LSP attached)

| Key | Mode | Action |
|-----|------|--------|
| `rn` | n | Rename symbol (auto-saves) |
| `ga` | n, x | Code action |
| `gr` | n | Go to references |
| `gi` | n | Go to implementation |
| `gd` | n | Go to definition |
| `gD` | n | Go to declaration |
| `gO` | n | Document symbols |
| `gW` | n | Workspace symbols |
| `gt` | n | Go to type definition |
| `<leader>th` | n | Toggle inlay hints |

### Git Hunks (gitsigns)

| Key | Mode | Action |
|-----|------|--------|
| `]c` | n | Next hunk |
| `[c` | n | Previous hunk |
| `<leader>hs` | n, v | Stage hunk |
| `<leader>hr` | n, v | Reset hunk |
| `<leader>hS` | n | Stage buffer |
| `<leader>hu` | n | Undo stage hunk |
| `<leader>hR` | n | Reset buffer |
| `<leader>hp` | n | Preview hunk |
| `<leader>hD` | n | Diff against last commit |
| `<leader>hQ` | n | All hunks to quickfix |
| `<leader>hq` | n | Current hunks to quickfix |
| `<leader>htb` | n | Toggle line blame |
| `<leader>htd` | n | Toggle deleted |

### Git Utilities (gitvu)

| Key | Mode | Action |
|-----|------|--------|
| `<leader>ga` | n | Toggle blame lens |
| `<leader>gn` | n | Next conflict |
| `<leader>gp` | n | Previous conflict |
| `<leader>g1` | n | Keep current changes |
| `<leader>g2` | n | Keep incoming changes |
| `<leader>g3` | n | Keep both changes |

### Debugging (DAP)

| Key | Mode | Action |
|-----|------|--------|
| `<F5>` | n | Start/Continue |
| `<F1>` | n | Step into |
| `<F2>` | n | Step over |
| `<F3>` | n | Step out |
| `<F7>` | n | Toggle DAP UI |
| `<leader>b` | n | Toggle breakpoint |
| `<leader>B` | n | Set conditional breakpoint |

### Takku (file management)

| Key | Mode | Action |
|-----|------|--------|
| `<leader>tj` | n | Next file |
| `<leader>tk` | n | Previous file |
| `<leader>ta` | n | Add file |
| `<leader>td` | n | Delete file |
| `<leader>t` | n | Goto file |
| `<leader>tl` | n | Show list |

### Copilot (insert mode)

| Key | Mode | Action |
|-----|------|--------|
| `<C-y>` | i | Accept suggestion |
| `<C-l>` | i | Accept line |
| `<M-w>` | i | Accept word |
| `<M-]>` | i | Next suggestion |
| `<M-[>` | i | Previous suggestion |
| `<M-\>` | i | Dismiss suggestion |
| `<leader>tc` | n | Toggle Copilot |

### CodeCompanion (Ollama)

| Key | Mode | Action |
|-----|------|--------|
| `<leader>aq` | n | Open chat |
| `<leader>ai` | v | Add selection to chat |
| `<leader>ac` | n | Actions |

### Completion (blink.cmp)

| Key | Mode | Action |
|-----|------|--------|
| `<CR>` | i | Accept completion |
| `<C-space>` | i | Toggle completion menu |
| `<C-n>` | i | Select next item |
| `<C-p>` | i | Select previous item |
| `<C-e>` | i | Hide menu |
| `<C-k>` | i | Toggle signature help |
| `<Tab>` | i | Next snippet placeholder |
| `<S-Tab>` | i | Previous snippet placeholder |

## Custom Plugins (local dev)

- **takku.nvim** (`SaravananSai07/takku.nvim`) — File switching/tracking
- **gitvu** (`SaravananSai07/gitvu`) — Blame lens + merge conflict resolution

## Notable Patterns

- **Swap file handling**: Auto-deletes stale swaps (>1hr), recovery dialog for newer ones
- **Auto-reload on focus**: Detects external changes after git ops
- **Diagnostics**: Nerd Font icons, underline only on ERROR, tiny-inline-diagnostic for compact display
- **Folding**: Treesitter-based, starts open (`foldlevel=99`)
- **Colorscheme**: tokyonight-night

## Code Style

Lua files are formatted with stylua (CI enforced via GitHub Actions). No trailing semicolons, single quotes preferred.
