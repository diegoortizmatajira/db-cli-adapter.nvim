# db-cli-adapter.nvim

`db-cli-adapter.nvim` is a Neovim plugin designed to provide seamless
integration with various database CLI tools. It enhances developer productivity
by offering an easy-to-use interface for database operations directly within
Neovim.

It follows KISS principle, so instead of requiring a custom-built backend cli tool,
you can use the default tooling for each database provider.

## Features

- Support for multiple databases: PostgreSQL, MySQL, MariaDB, SQLite, and
  [usql](https://github.com/xo/usql) (universal SQL client).
- Execute SQL queries from visual selection, current statement (via TreeSitter),
  or entire buffer.
- Output results as formatted text tables or CSV files.
- Interactive sidebar to browse database schemas, tables, views, and columns.
- Per-buffer connection management — different buffers can use different connections.
- Global and workspace-scoped connection storage in JSON files.
- LSP integration with `sqlls` and `sqls` for autocompletion with the active connection.
- Health check module (`:checkhealth db-cli-adapter`).
- Lightweight and easy to configure.

## Prerequisites

- Neovim 0.5 or higher.
- [nui.nvim](https://github.com/MunifTanjim/nui.nvim) (required — used for
  sidebar and output panels).
- [overseer.nvim](https://github.com/stevearc/overseer.nvim) (optional —
  enables terminal-based output display; falls back to `jobstart` if not installed).
- TreeSitter with the `sql` parser installed (for automatic statement detection
  at cursor).
- At least one database CLI tool installed and available in your `PATH`:
  - `psql` — PostgreSQL
  - `mysql` — MySQL
  - `mariadb` — MariaDB
  - `sqlite3` — SQLite
  - `usql` — Universal SQL client

## Installation

### Using [Lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
    'diegoortizmatajira/db-cli-adapter.nvim',
    dependencies = {
        'MunifTanjim/nui.nvim',
    },
    opts = {}
}
```

### Using [Packer](https://github.com/wbthomason/packer.nvim)

```lua
use {
    'diegoortizmatajira/db-cli-adapter.nvim',
    requires = { 'MunifTanjim/nui.nvim' },
    config = function()
        require('db-cli-adapter').setup({})
    end
}
```

Run the `:PackerSync` command to install the plugin.

## Configuration

The plugin works out of the box with `setup({})`. All options below can be
overridden via `vim.tbl_deep_extend` merge:

```lua
require('db-cli-adapter').setup({
    -- Called when the active connection changes in a buffer.
    -- Use one of the built-in handlers for LSP integration:
    --   require('db-cli-adapter.config').sqlls_connection_change_handler
    --   require('db-cli-adapter.config').sqls_connection_change_handler
    connection_change_handler = nil,

    -- Built-in adapters (you can override individual adapter settings)
    adapters = {
        psql   = require('db-cli-adapter.builtins.psql'),
        sqlite = require('db-cli-adapter.builtins.sqlite'),
        mysql  = require('db-cli-adapter.builtins.mysql'),
        mariadb = require('db-cli-adapter.builtins.mariadb'),
        usql   = require('db-cli-adapter.builtins.usql'),
    },

    -- Paths to JSON files that store connections
    sources = {
        global    = vim.fn.stdpath('data') .. '/db-cli-adapter/global-connections.json',
        workspace = function() ... end, -- auto-generated per-project path
    },

    -- Sidebar behaviour
    sidebar = {
        keybindings = {
            toggle_expand = { 't', '<CR>' },
            expand        = { 'o' },
            collapse      = { 'c' },
            quit          = { 'q' },
            refresh       = { 'r' },
            refresh_all   = { 'R' },
        },
    },

    -- Output settings
    output = {
        csv = {
            after_query_callback = nil, -- function(csv_file_path) called after CSV export
        },
        editable = {
            format = 'csv', -- 'csv' (default) or 'tsv' for editable result buffers
        },
    },

    -- Icons used in the sidebar and connection picker
    icons = {
        tree = {
            chevron_open       = ' ',
            chevron_closed     = ' ',
            connected_database = '󰪩 ',
            folder             = ' ',
            database           = ' ',
            schema             = '󰲋 ',
            table              = ' ',
            column             = '󰭸 ',
            key                = '󰌆 ',
        },
        source = {
            global    = '🌐',
            workspace = ' ',
        },
        adapter = {
            psql    = ' ',
            sqlite  = ' ',
            mysql   = ' ',
            mariadb = ' ',
            default = '󰪩 ',
        },
    },

    -- Highlight groups for sidebar nodes
    highlight = {
        tree = {
            chevron            = '@constant',
            default_icon       = '@symbol',
            connected_database = '@function',
            folder             = '@symbol',
            database           = '@operator',
            schema             = '@macro',
            table              = '@number',
            column             = '@symbol',
            key                = '@type',
        },
    },
})
```

### LSP integration example

To restart `sqlls` automatically whenever you switch connections:

```lua
require('db-cli-adapter').setup({
    connection_change_handler = require('db-cli-adapter.config').sqlls_connection_change_handler,
})
```

A `sqls_connection_change_handler` is also available for
[sqls](https://github.com/lighttiger2505/sqls).

## Usage

### Commands

| Command                       | Description                                           |
| ----------------------------- | ----------------------------------------------------- |
| `:DbCliSelectConnection`      | Select the active database connection for this buffer |
| `:DbCliRunAtCursor`           | Run the visual selection or TreeSitter statement at the cursor |
| `:DbCliRunAtCursorCsv`        | Same as above but output as CSV                       |
| `:DbCliRunBuffer`             | Run the entire buffer as a query                      |
| `:DbCliRunAtCursorEditable`   | Run query at cursor and open editable result buffer when PK columns are present |
| `:DbCliRunBufferEditable`     | Run full buffer query and open editable result buffer when PK columns are present |
| `:DbCliResultPreviewChanges`  | Preview generated `INSERT`/`UPDATE`/`DELETE` statements from result buffer edits |
| `:DbCliResultCommitChanges`   | Commit pending result-buffer changes to the same connection |
| `:DbCliResultRefresh`         | Re-run the original query for the current result buffer |
| `:DbCliSidebarToggle`         | Toggle the database browser sidebar                   |
| `:DbCliOutputToggle`          | Toggle the output panel                               |
| `:DbCliEditConnection [key]`  | Edit a connection source file (`global` or `workspace`) |
| `:DbCliTest`                  | Test the current adapter by listing tables             |

### Suggested keymaps

The plugin does not set any global keymaps by default. Here is a suggested
configuration:

```lua
vim.keymap.set('n', '<leader>dc', '<cmd>DbCliSelectConnection<cr>', { desc = 'Select DB connection' })
vim.keymap.set({ 'n', 'v' }, '<leader>dr', '<cmd>DbCliRunAtCursor<cr>', { desc = 'Run query at cursor' })
vim.keymap.set({ 'n', 'v' }, '<leader>dR', '<cmd>DbCliRunAtCursorCsv<cr>', { desc = 'Run query (CSV)' })
vim.keymap.set('n', '<leader>da', '<cmd>DbCliRunBuffer<cr>', { desc = 'Run entire buffer' })
vim.keymap.set('n', '<leader>ds', '<cmd>DbCliSidebarToggle<cr>', { desc = 'Toggle DB sidebar' })
vim.keymap.set('n', '<leader>do', '<cmd>DbCliOutputToggle<cr>', { desc = 'Toggle DB output' })
vim.keymap.set('n', '<leader>de', '<cmd>DbCliEditConnection<cr>', { desc = 'Edit connections' })
```

### Sidebar keybindings

Once the sidebar is open, the following keys are available (configurable via
`sidebar.keybindings`):

| Key         | Action               |
| ----------- | -------------------- |
| `t` / `<CR>` | Toggle expand/collapse |
| `o`          | Expand node          |
| `c`          | Collapse node        |
| `q`          | Close sidebar        |
| `r`          | Refresh current node |
| `R`          | Refresh all nodes    |

### Connection files

Connections are stored as JSON. Use `:DbCliEditConnection global` or
`:DbCliEditConnection workspace` to open the corresponding file in your editor.

```json
{
  "my_postgres": {
    "adapter": "psql",
    "username": "user",
    "password": "secret",
    "host": "localhost",
    "port": 5432,
    "dbname": "mydb"
  },
  "local_sqlite": {
    "adapter": "sqlite",
    "filename": "/path/to/database.db"
  },
  "my_mysql": {
    "adapter": "mysql",
    "username": "root",
    "host": "127.0.0.1",
    "port": 3306,
    "dbname": "app"
  },
  "via_usql": {
    "adapter": "usql",
    "url": "postgres://user:pass@host:5432/dbname"
  }
}
```

**Global** connections are stored at
`~/.local/share/nvim/db-cli-adapter/global-connections.json` and are available
across all projects.

**Workspace** connections are stored in a project-specific path under
`~/.local/share/nvim/db-cli-adapter/` and are scoped to the current working
directory.

### Statusline

You can display the active connection in your statusline by calling:

```lua
require('db-cli-adapter').get_current_db_connection()
```

This returns a string like `"󰪩 my_postgres"` when a connection is active, or
an empty string otherwise.

### Editable result buffers

Use `:DbCliRunAtCursorEditable` or `:DbCliRunBufferEditable` to open query results in an editable buffer.

Editable buffer format is configurable:

```lua
require('db-cli-adapter').setup({
    output = {
        editable = {
            format = 'csv', -- or 'tsv'
        },
    },
})
```

Current V1 constraints:

- only single-table `SELECT` results are editable
- primary key columns must be part of the selected columns
- if a result set is not eligible, it opens in read-only mode with a warning

Inside an editable result buffer:

- modify cell values directly
- remove lines to mark rows for deletion
- add new lines for inserts (with PK values)
- run `:DbCliResultPreviewChanges` to inspect generated SQL
- run `:DbCliResultCommitChanges` to apply changes
- run `:DbCliResultRefresh` to reload from source query

### Health check

Run `:checkhealth db-cli-adapter` to verify that required dependencies and
database CLI tools are installed.

## Adapter connection parameters

Each adapter accepts different parameters in the connection JSON:

| Parameter  | psql | mysql | mariadb | sqlite | usql |
| ---------- | :--: | :---: | :-----: | :----: | :--: |
| `adapter`  |  x   |   x   |    x    |   x    |  x   |
| `username` |  x   |   x   |    x    |        |      |
| `password` |  x   |   x   |    x    |        |      |
| `host`     |  x   |   x   |    x    |        |      |
| `port`     |  x   |   x   |    x    |        |      |
| `dbname`   |  x   |   x   |    x    |        |      |
| `ssl`      |  x   |   x   |    x    |        |      |
| `skipssl`  |      |   x   |    x    |        |      |
| `timeout`  |  x   |   x   |    x    |        |      |
| `filename` |      |       |         |   x    |      |
| `url`      |      |       |         |        |  x   |

## Testing

Tests use [plenary.nvim](https://github.com/nvim-lua/plenary.nvim). Run them
with:

```bash
./tests/run_tests.sh            # run all tests
./tests/run_tests.sh types_spec # run a specific test file
```

## Contributing

Contributions are welcome! Please feel free to open issues or submit pull
requests.

## License

This plugin is licensed under the MIT License. See the [LICENSE](LICENSE) file
for more details.

---

Enjoy seamless database operations directly within Neovim!
