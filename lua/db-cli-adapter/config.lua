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
		},
	},
}

return C
