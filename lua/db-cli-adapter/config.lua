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
				defautl = "󰪩 ",
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
			},
		},
		output = {
			csv = {
				after_query_callback = nil,
			},
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
	vim.lsp.stop_client(clients, true)
	local lsp_config = vim.lsp.config[server_name]
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

return C
