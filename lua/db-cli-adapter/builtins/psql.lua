require("db-cli-adapter.types")
require("db-cli-adapter.adapter_config")

--- @class DbCliAdapter.pgsql_params
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

	--- Use pipe characters to format output as a table when a line contains a pipe (to complete the table)
	line_preprocessor = function(line)
		if line:match("|") then
			return "|" .. line .. "|"
		end
		return line
	end,
})

--- Execute a SQL command using pgcli
--- @param command string The SQL command to execute
--- @param params DbCliAdapter.pgsql_params Connection parameters
--- @param callback fun(result: DbCliAdapter.Output) A callback function to handle the query result
function adapter:query(command, params, callback)
	local args = {}
	local env = {}

	if params and params.username then
		table.insert(args, string.format("--username=%s", params.username))
	end
	if params and params.password then
		env["PGPASSWORD"] = params.password
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
	--- Pass the command to execute
	table.insert(args, string.format("--command=%s", command))

	return self:run_command({
		cmd = self.command,
		args = args,
		env = env,
		callback = callback,
	})
end

return adapter
