require("db-cli-adapter.types")
require("db-cli-adapter.adapter_config")

--- @class DbCliAdapter.usql_params: DbCliAdapter.base_params
--- @field url string The database connection URL

--- @class DbCliAdapter.usql_adapter: DbCliAdapter.AdapterConfig
local adapter = AdapterConfig:new({
	name = "Universal Sql (usql)",
	command = "usql",
})

--- Execute a SQL command using pgcli
--- @param command string The SQL command to execute
--- @param params DbCliAdapter.usql_params Connection parameters
--- @param callback fun(result: DbCliAdapter.Output) A callback function to handle the query result
function adapter:query(command, params, callback)
	local args = {
		params.url,
	}
	local env = {}

	--- Disable pager to avoid issues with output capturing
	table.insert(args, "-P")
	table.insert(args, "pager=off")
	table.insert(args, "-P")
	table.insert(args, "format=aligned")
	table.insert(args, "-P")
	table.insert(args, "border=2")
	table.insert(args, "-P")
	table.insert(args, "linestyle=old-ascii")
	--- Pass the command to execute
	table.insert(args, string.format([[--command=%s]], self:parse_command(command, params)))

	return self:run_command({
		cmd = self.command,
		args = args,
		env = env,
		callback = callback,
	})
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
