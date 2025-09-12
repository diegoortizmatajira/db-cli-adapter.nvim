require("db-cli-adapter.types")
require("db-cli-adapter.adapter_config")

--- @class DbCliAdapter.mariadb_params: DbCliAdapter.base_params
--- @field dbname string The name of the database to connect to
--- @field username string The username to connect as
--- @field host string The hostname of the database server
--- @field port number The port number of the database server
--- @field password string The password for the database user (if required)
--- @field ssl boolean Whether to use SSL for the connection
--- @field skipssl boolean Whether to skip SSL verification

--- @class DbCliAdapter.mariadb_adapter: DbCliAdapter.AdapterConfig
local adapter = AdapterConfig:new({
	name = "MariaDb (mariadb)",
	command = "/usr/bin/mariadb",
	--- Use pipe characters to format output as a table when a line contains a pipe (to complete the table)
	line_preprocessor = function(line)
		if line:match("\t") then
			-- Convert tabs to pipes for table formatting
			line = line:gsub("\t", "|")
			return "|" .. line .. "|"
		end
		return line
	end,
})

--- Execute a SQL command using pgcli
--- @param command string The SQL command to execute
--- @param params DbCliAdapter.mariadb_params Connection parameters
--- @param callback fun(result: DbCliAdapter.Output) A callback function to handle the query result
function adapter:query(command, params, callback)
	local args = {}
	local env = {}

	if params and params.username then
		table.insert(args, string.format("--user=%s", params.username))
	end
	if params and params.password then
		table.insert(args, string.format("--password=%s", params.password))
	end
	if params and params.host then
		table.insert(args, string.format("--host=%s", params.host))
	end
	if params and params.timeout then
		table.insert(args, string.format("--connect-timeout=%s", params.timeout))
	end
	if params and params.port then
		table.insert(args, string.format("--port=%s", params.port))
	end
	if params and params.dbname then
		table.insert(args, string.format("--database=%s", params.dbname))
	end
	if params and params.ssl then
		table.insert(args, "--ssl")
	end
	if params and params.skipssl then
		table.insert(args, "--skip-ssl")
	end
	table.insert(args, "--table")
	table.insert(args, string.format([[--execute=%s]], command))

	return self:run_command({
		cmd = self.command,
		args = args,
		env = env,
		callback = callback,
	})
end

return adapter
