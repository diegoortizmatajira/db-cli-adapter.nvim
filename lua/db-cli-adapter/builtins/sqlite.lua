local ConnectionChangedData = require("db-cli-adapter.types")
local AdapterConfig = require("db-cli-adapter.adapter_config")

--- @class DbCliAdapter.sqlite_params: DbCliAdapter.base_params
--- @field filename string The name of the database to connect to

--- @class DbCliAdapter.sqlite_adapter: DbCliAdapter.AdapterConfig
local adapter = AdapterConfig:new({
	name = "Sqlite (sqlite3)",
	command = "sqlite3",
	supports_backup_restore = true,
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

--- Execute a SQL command using sqlite3
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
		table.insert(args, ".headers on")
		table.insert(args, "-cmd")
		table.insert(args, string.format(".output %s", opts.csv_file))
		table.insert(args, "-cmd")
		table.insert(args, ".mode csv")
	else
		-- Default to table output mode
		table.insert(args, "-cmd")
		table.insert(args, ".mode table")
	end
	if params and params.timeout then
		table.insert(args, "-cmd")
		table.insert(args, string.format(".timeout %s", params.timeout * 1000)) -- timeout in milliseconds
	end
	table.insert(args, params.filename)
	table.insert(args, self:parse_command(command, params))
	local env = {}

	return self:run_command({
		cmd = self.command,
		args = args,
		env = env,
		callback = opts and opts.callback,
	})
end

--- Returns args for a `sqlite3` invocation that writes a plain-SQL dump to stdout.
--- @param params DbCliAdapter.sqlite_params Connection parameters
--- @return string[] args
function adapter:get_backup_args(params)
	return { params.filename, ".dump" }
end

--- Returns args for a `sqlite3` invocation that applies a SQL script from stdin.
--- @param params DbCliAdapter.sqlite_params Connection parameters
--- @return string[] args
function adapter:get_restore_args(params)
	return { params.filename }
end

--- Override to ignore schema (SQLite has no schemas) and only use the table name
function adapter:get_table_columns_query(schema, table_name)
	return string.format(self.table_columns_query, table_name)
end

--- Returns query to list PK columns for SQLite tables.
--- @param _ string|nil
--- @param table_name string
--- @return string
function adapter:get_primary_keys_query(_, table_name)
	if not table_name or table_name == "" then
		return ""
	end
	return string.format(
		[[SELECT name AS column_name
FROM pragma_table_info('%s')
WHERE pk > 0
ORDER BY pk;]],
		tostring(table_name):gsub("'", "''")
	)
end

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
