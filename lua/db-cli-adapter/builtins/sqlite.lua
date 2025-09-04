require("db-cli-adapter.types")
require("db-cli-adapter.adapter_config")

--- @class DbCliAdapter.sqlite_params
--- @field filename string The name of the database to connect to

--- @class DbCliAdapter.sqlite_adapter: DbCliAdapter.AdapterConfig
local adapter = AdapterConfig:new("Sqlite (sqlite3)", "sqlite3")

--- Execute a SQL command using pgcli
--- @param command string The SQL command to execute
--- @param params DbCliAdapter.sqlite_params Connection parameters
function adapter:query(command, params)
	local args = {
		"-markdown",
		params.filename,
		string.format([["%s"]], command),
	}
	local env = {}

	return self:run_command(self.command, args, env)
end

return adapter
