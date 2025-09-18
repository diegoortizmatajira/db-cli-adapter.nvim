require("db-cli-adapter.types")
require("db-cli-adapter.adapter_config")

--- @class DbCliAdapter.usql_params: DbCliAdapter.base_params
--- @field url string The database connection URL

--- @class DbCliAdapter.usql_adapter: DbCliAdapter.AdapterConfig
--- @field icons table<string, string> A mapping of database types to their respective icons
local adapter = AdapterConfig:new({
	name = "Universal Sql (usql)",
	command = "usql",
	icons = {
		pg = "psql",
		postgres = "psql",
		pgsql = "psql",
		sq = "sqlite",
		sqlite = "sqlite",
		sqlite3 = "sqlite",
		["file"] = "sqlite",
		maria = "mariadb",
		mariadb = "mariadb",
		my = "mysql",
		mysql = "mysql",
		aurora = "mysql",
		percona = "mysql",
	},
})

--- Execute a SQL command using pgcli
--- @param command string The SQL command to execute
--- @param params DbCliAdapter.usql_params Connection parameters
--- @param opts? DbCliAdapter.RunOptions Optional table of execution parameters:
function adapter:query(command, params, opts)
	local args = {
		params.url,
	}
	local env = {}

	--- Disable pager to avoid issues with output capturing
	table.insert(args, "-P")
	table.insert(args, "pager=off")
	if opts and opts.csv_file then
		-- If CSV output is requested, set the appropriate commands
		table.insert(args, "--csv")
		table.insert(args, "--out")
		table.insert(args, opts.csv_file)
	else
		-- Default to table output mode
		table.insert(args, "-P")
		table.insert(args, "format=aligned")
		table.insert(args, "-P")
		table.insert(args, "border=2")
		table.insert(args, "-P")
		table.insert(args, "linestyle=old-ascii")
	end
	--- Pass the command to execute
	table.insert(args, string.format([[--command=%s]], self:parse_command(command, params)))

	return self:run_command({
		cmd = self.command,
		args = args,
		env = env,
		callback = opts and opts.callback,
	})
end

--- Return the icon for the adapter
--- @param params DbCliAdapter.usql_params Connection parameters
function adapter:get_icon(params)
	local config = require("db-cli-adapter.config").current
	for key, value in pairs(adapter.icons) do
		if params.url:match("^" .. key) then
			local icon = value or "default"
			return config and config.icons.adapter[icon] or AdapterConfig.get_icon(self, params)
		end
	end
	return AdapterConfig.get_icon(self, params)
end

function adapter:get_schemas_query()
	--- Return a SQL query to retrieve the list of schemas in the database
	--- @param params DbCliAdapter.usql_params Connection parameters
	return function(params)
		local query = AdapterConfig.get_schemas_query(self)
		--- Special handling for SQLite
		if params.url:match("^sqlite3") then
			query = require("db-cli-adapter.builtins.sqlite"):get_schemas_query()
		end
		return self:parse_command(query, params)
	end
end

function adapter:get_tables_query(schema)
	--- Return a SQL query to retrieve the list of tables in the specified schema
	--- @param params DbCliAdapter.usql_params Connection parameters
	return function(params)
		local query = AdapterConfig.get_tables_query(self, schema)
		--- Special handling for SQLite
		if params.url:match("^sqlite3") then
			query = require("db-cli-adapter.builtins.sqlite"):get_tables_query(schema)
		end
		return self:parse_command(query, params)
	end
end

function adapter:get_table_columns_query(schema, table)
	--- Return a SQL query to retrieve the list of columns in the specified table
	--- @param params DbCliAdapter.usql_params Connection parameters
	return function(params)
		local query = AdapterConfig.get_table_columns_query(self, schema, table)
		--- Special handling for SQLite
		if params.url:match("^sqlite3") then
			query = require("db-cli-adapter.builtins.sqlite"):get_table_columns_query(schema, table)
		end
		return self:parse_command(query, params)
	end
end

return adapter
