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
--- @param opts? DbCliAdapter.RunOptions Optional table of execution parameters:
function adapter:query(command, params, opts)
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
	table.insert(args, string.format([[--execute=%s]], self:parse_command(command, params)))

	return self:run_command({
		cmd = self.command,
		args = args,
		env = env,
		callback = opts and opts.callback,
	})
end

---
--- Return the connection URL for the adapter
--- @param params DbCliAdapter.mariadb_params Connection parameters
--- @return DbCliAdapter.ConnectionChangedData
function adapter:get_url_connection(params)
	return ConnectionChangedData:new({
		name = "Db-Cli-Adapter connection",
		adapter = "mysql",
		host = params.host or "localhost",
		port = params.port or 3306,
		user = params.username or "user",
		password = params.password or "password",
		database = params.dbname or "database",
		-- Provides a default project path as the current working directory
		projectPaths = { vim.fn.getcwd() },
	})
end

return adapter
