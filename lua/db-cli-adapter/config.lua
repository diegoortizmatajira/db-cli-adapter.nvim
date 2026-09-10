local function get_workspace_source()
	local cwd = vim.fn.getcwd()
	-- Get the last folder name of the current working directory
	local last_folder = vim.fn.fnamemodify(vim.fn.getcwd(), ":t")
	-- Hash the current working directory to ensure uniqueness
	local hashed = vim.fn.sha256(cwd)
	-- Create a custom name using the last folder and the first 8 characters of the hash
	local custom_name = string.format("%s - %s", last_folder, string.sub(hashed, 1, 8))
	return vim.fn.stdpath("data") .. "/db-cli-adapter/" .. custom_name .. "/workspace-connections.json"
end

local C = {

	--- @type DbCliAdapter.Config
	default = {
		connection_change_handler = nil,
		-- Called whenever the plugin opens a new buffer without an associated file (a
		-- sidebar-generated SQL buffer, an editable result buffer, or a change-preview
		-- buffer). Receives the buffer number. See `C.attach_lsp_for_filetype_handler`
		-- for a ready-made implementation that attaches matching running LSP clients.
		new_buffer_handler = nil,
		adapters = {
			psql = require("db-cli-adapter.builtins.psql"),
			sqlite = require("db-cli-adapter.builtins.sqlite"),
			mysql = require("db-cli-adapter.builtins.mysql"),
			mariadb = require("db-cli-adapter.builtins.mariadb"),
			usql = require("db-cli-adapter.builtins.usql"),
		},
		sources = {
			global = vim.fn.stdpath("data") .. "/db-cli-adapter/global-connections.json",
			workspace = get_workspace_source,
		},
		highlight = {
			tree = {
				chevron = "@constant",
				default_icon = "@symbol",
				connected_database = "@function",
				folder = "@symbol",
				database = "@operator",
				schema = "@macro",
				table = "@number",
				view = "@keyword",
				column = "@symbol",
				key = "@type",
			},
		},
		icons = {
			tree = {
				chevron_open = " ",
				chevron_closed = " ",
				connected_database = "󰪩 ",
				folder = " ",
				database = " ",
				schema = "󰲋 ",
				table = " ",
				view = "󰈈 ",
				column = "󰭸 ",
				key = "󰌆 ",
			},
			source = {
				global = "🌐",
				workspace = " ",
			},
			adapter = {
				psql = " ",
				sqlite = " ",
				mysql = " ",
				mariadb = " ",
				default = "󰪩 ",
			},
		},
		sidebar = {
			keybindings = {
				toggle_expand = { "t", "<CR>" },
				expand = { "o" },
				collapse = { "c" },
				quit = { "q" },
				refresh = { "r" },
				refresh_all = { "R" },
				execute_query = { "x" },
				open_query = { "X" },
				generate_ddl = { "G" },
				generate_insert = { "I" },
				generate_update = { "U" },
				generate_delete = { "D" },
			},
			-- Maximum number of rows returned by the generated `SELECT` statements used by the
			-- execute_query/open_query sidebar actions. Set to nil or 0 to disable the limit.
			-- The LIMIT syntax itself is applied per-adapter (see AdapterConfig:build_select_query).
			query_row_limit = 200,
		},
		output = {
			csv = {
				after_query_callback = nil,
			},
			editable = {
				format = "csv",
			},
		},
		backup = {
			directory = vim.fn.stdpath("data") .. "/db-cli-adapter/backups",
			-- Optional custom container picker: fun(context, callback). If nil, falls
			-- back to vim.ui.input. See DbCliAdapter.ContainerPickerContext.
			container_picker = nil,
		},
	},
	--- @type DbCliAdapter.Config|nil
	current = nil,
}

--- Updates the current configuration with a new configuration.
--- If the provided configuration is not a table or is nil, the update is ignored.
---
--- @param new_config DbCliAdapter.Config The new configuration to set as the current configuration.
function C.update(new_config)
	if not new_config then
		return
	end
	C.current = new_config
end

local function lsp_restart(server_name, settings)
	--- Provides a default implementation for sqlls LSP restart on connection change
	local clients = vim.lsp.get_clients({ name = server_name })
	if #clients == 0 then
		return
	end
	for _, client in ipairs(clients) do
		client:stop(true)
	end
	local lsp_config = vim.lsp.config[server_name]
	if not lsp_config then
		return
	end
	-- Reconfigure and restart the LSP with the new connection settings
	lsp_config.settings = settings
	vim.lsp.start(lsp_config)
end

--- Default connection change handler that restarts the sqlls LSP with the new connection settings.
--- This function can be overridden by setting the `connection_change_handler` in the configuration.
--- @param _ number The buffer number where the connection change occurred (not used in this default implementation).
--- @param connection DbCliAdapter.ConnectionChangedData The new connection data.
function C.sqlls_connection_change_handler(_, connection)
	lsp_restart("sqlls", {
		sqlLanguageServer = {
			connections = { connection:as_sqlls_connection() },
		},
	})
end

--- Default connection change handler that restarts the sqls LSP with the new connection settings.
--- This function can be overridden by setting the `connection_change_handler` in the configuration.
--- @param _ number The buffer number where the connection change occurred (not used in this default implementation).
--- @param connection DbCliAdapter.ConnectionChangedData The new connection data.
function C.sqls_connection_change_handler(_, connection)
	lsp_restart("sqls", {
		sqls = {
			connections = { connection:as_sqls_connection() },
		},
	})
end

--- Default `new_buffer_handler`: starts (or attaches to an already-running instance of) every
--- enabled LSP config whose `filetypes` include the new buffer's filetype.
---
--- Buffers this plugin opens without a backing file (a sidebar-generated SQL buffer, an
--- editable result buffer, a change-preview buffer) have `buftype = "nofile"`, and Neovim's
--- own FileType-driven LSP autostart (`vim.lsp.enable`) explicitly only attaches to buffers
--- with an empty or `"help"` buftype -- it never fires for these. This calls `vim.lsp.start()`
--- directly instead, which transparently reuses a matching already-running client (by name and
--- root_dir, e.g. `sqlls` started for the buffer where the connection was originally selected)
--- or starts a new one if none is running yet. Requires Neovim 0.11+ (`vim.lsp.get_configs`).
--- This function can be overridden by setting `new_buffer_handler` in the configuration.
--- @param bufnr number The newly opened buffer.
function C.attach_lsp_for_filetype_handler(bufnr)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end
	local filetype = vim.bo[bufnr].filetype
	if not filetype or filetype == "" then
		return
	end
	for _, lsp_config in ipairs(vim.lsp.get_configs({ enabled = true, filetype = filetype })) do
		vim.lsp.start(lsp_config, { bufnr = bufnr, reuse_client = lsp_config.reuse_client })
	end
end

return C
