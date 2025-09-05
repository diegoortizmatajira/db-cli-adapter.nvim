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
		adapters = {
			psql = require("db-cli-adapter.builtins.psql"),
			sqlite = require("db-cli-adapter.builtins.sqlite"),
			mysql = require("db-cli-adapter.builtins.mysql"),
			mariadb = require("db-cli-adapter.builtins.mariadb"),
		},
		sources = {
			global = vim.fn.stdpath("data") .. "/db-cli-adapter/global-connections.json",
			workspace = get_workspace_source,
		},
		source_icons = {
			global = "🌐",
			workspace = " ",
		},
		adapter_icons = {
			psql = " ",
			sqlite = " ",
			mysql = " ",
			mariadb = " ",
			defautl = "󰪩 ",
		},
		sidebar = {
			keybindings = {
				toggle_expand = { "t", "<CR>" },
				expand = { "o" },
				collapse = { "c" },
				quit = { "q" },
				refresh = { "r" },
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

return C
