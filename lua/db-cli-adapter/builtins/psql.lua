local ConnectionChangedData = require("db-cli-adapter.types")
local AdapterConfig = require("db-cli-adapter.adapter_config")

--- @class DbCliAdapter.pgsql_params: DbCliAdapter.base_params
--- @field dbname string The name of the database to connect to
--- @field username string The username to connect as
--- @field host string The hostname of the database server
--- @field port number The port number of the database server
--- @field password string The password for the database user (if required)
--- @field ssl boolean Whether to use SSL for the connection

--- @class DbCliAdapter.psql_adapter: DbCliAdapter.AdapterConfig
local adapter = AdapterConfig:new({
	name = "PostgreSQL (psql)",
	command = "psql",
})

--- Execute a SQL command using psql
--- @param command string The SQL command to execute
--- @param params DbCliAdapter.pgsql_params Connection parameters
--- @param opts? DbCliAdapter.RunOptions Optional table of execution parameters:
function adapter:query(command, params, opts)
	local args = {}
	local env = {}

	if params and params.username then
		table.insert(args, string.format("--username=%s", params.username))
	end
	if params and params.password then
		env["PGPASSWORD"] = params.password
	end
	if params and params.timeout then
		env["PGCONNECT_TIMEOUT"] = params.timeout
	end
	if params and params.host then
		table.insert(args, string.format("--host=%s", params.host))
	end
	if params and params.port then
		table.insert(args, string.format("--port=%s", params.port))
	end
	if params and params.dbname then
		table.insert(args, string.format("--dbname=%s", params.dbname))
	end
	--- Disable pager to avoid issues with output capturing
	table.insert(args, "-P")
	table.insert(args, "pager=off")
	if opts and opts.csv_file then
		-- If CSV output is requested, set the appropriate commands
		table.insert(args, "--csv")
		table.insert(args, string.format("--output=%s", opts.csv_file))
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

--- Return the connection URL for the adapter
--- @param params DbCliAdapter.pgsql_params Connection parameters
--- @return DbCliAdapter.ConnectionChangedData
function adapter:get_url_connection(params)
	--- @type DbCliAdapter.ConnectionChangedData
	return ConnectionChangedData:new({
		name = "Db-Cli-Adapter connection",
		adapter = "postgres",
		host = params.host or "localhost",
		port = params.port or 5432,
		user = params.username or "user",
		password = params.password or "password",
		database = params.dbname or "database",
		-- Provides a default project path as the current working directory
		projectPaths = { vim.fn.getcwd() },
	})
end

--- Returns query to list PK columns for PostgreSQL tables.
--- @param schema string|nil
--- @param table_name string
--- @return string
function adapter:get_primary_keys_query(schema, table_name)
	if not table_name or table_name == "" then
		return ""
	end
	local schema_filter = schema and schema ~= ""
			and string.format("kcu.table_schema = '%s'", tostring(schema):gsub("'", "''"))
		or "kcu.table_schema = current_schema()"
	return string.format(
		[[SELECT kcu.column_name
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
	ON tc.constraint_name = kcu.constraint_name
	AND tc.table_schema = kcu.table_schema
WHERE tc.constraint_type = 'PRIMARY KEY'
	AND kcu.table_name = '%s'
	AND %s
ORDER BY kcu.ordinal_position;]],
		tostring(table_name):gsub("'", "''"),
		schema_filter
	)
end

return adapter
