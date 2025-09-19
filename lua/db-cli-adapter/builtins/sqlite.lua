require("db-cli-adapter.types")
require("db-cli-adapter.adapter_config")

--- @class DbCliAdapter.sqlite_params: DbCliAdapter.base_params
--- @field filename string The name of the database to connect to

--- @class DbCliAdapter.sqlite_adapter: DbCliAdapter.AdapterConfig
local adapter = AdapterConfig:new({
	name = "Sqlite (sqlite3)",
	command = "sqlite3",
	schemas_query = [[SELECT 'public' AS schema_name;]],
	tables_query = [[
	       SELECT name AS table_name, 'public' AS table_schema
	       FROM sqlite_master 
	       WHERE type='table' 
	       AND name NOT LIKE 'sqlite_%%'
	       ORDER BY name;]],
	views_query = [[
        SELECT name AS table_name, 'public' AS table_schema
        FROM sqlite_master 
        WHERE type='view' 
        AND name NOT LIKE 'sqlite_%%'
        ORDER BY name;]],
	table_columns_query = [[SELECT name, type, pk  
	    FROM pragma_table_info('%s');]],
})

--- Execute a SQL command using pgcli
--- @param command string The SQL command to execute
--- @param params DbCliAdapter.sqlite_params Connection parameters
--- @param opts? DbCliAdapter.RunOptions Optional table of execution parameters:
function adapter:query(command, params, opts)
	local args = {
		"-markdown",
	}
	if opts and opts.csv_file then
		-- If CSV output is requested, set the appropriate commands
		table.insert(args, "-cmd")
		table.insert(args, '".headers on"')
		table.insert(args, "-cmd")
		table.insert(args, string.format([[".output %s"]], opts.csv_file))
		table.insert(args, "-cmd")
		table.insert(args, '".mode csv"')
	else
		-- Default to table output mode
		table.insert(args, "-cmd")
		table.insert(args, '".mode table"')
	end
	if params and params.timeout then
		table.insert(args, "-cmd")
		table.insert(args, string.format([[".timeout %s"]], params.timeout * 1000)) -- timeout in milliseconds
	end
	table.insert(args, params.filename)
	table.insert(args, string.format([["%s"]], self:parse_command(command, params)))
	local env = {}

	return self:run_command({
		cmd = self.command,
		args = args,
		env = env,
		callback = opts and opts.callback,
	})
end

---
--- Return the connection URL for the adapter
--- @param params DbCliAdapter.sqlite_params Connection parameters
--- @return DbCliAdapter.ConnectionChangedData
function adapter:get_url_connection(params)
	return ConnectionChangedData:new({
		name = "Db-Cli-Adapter connection",
		adapter = "sqlite3",
		filename = params.filename or "database.sqlite",
		-- Provides a default project path as the current working directory
		projectPaths = { vim.fn.getcwd() },
	})
end

return adapter
