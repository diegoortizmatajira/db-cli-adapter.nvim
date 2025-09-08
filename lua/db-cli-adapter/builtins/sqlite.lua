require("db-cli-adapter.types")
require("db-cli-adapter.adapter_config")

--- @class DbCliAdapter.sqlite_params
--- @field filename string The name of the database to connect to

--- @class DbCliAdapter.sqlite_adapter: DbCliAdapter.AdapterConfig
local adapter = AdapterConfig:new({
	name = "Sqlite (sqlite3)",
	command = "sqlite3",
	schemasQuery = [[SELECT 'general' AS schema_name;]],
	tablesQuery = [[
        SELECT name AS table_name, 'general' AS table_schema
        FROM sqlite_master 
        WHERE type='table' 
        AND name NOT LIKE 'sqlite_%'
        ORDER BY name;
    ]],
	viewsQuery = [[
        SELECT name AS table_name, 'general' AS table_schema
        FROM sqlite_master 
        WHERE type='view' 
        AND name NOT LIKE 'sqlite_%'
        ORDER BY name;
    ]],
})

--- Execute a SQL command using pgcli
--- @param command string The SQL command to execute
--- @param params DbCliAdapter.sqlite_params Connection parameters
--- @param internal_execution boolean Whether this is an internal execution
function adapter:query(command, params, internal_execution)
	local args = {
		"-markdown",
		params.filename,
		string.format([["%s"]], command),
	}
	local env = {}

	return self:run_command({
		cmd = self.command,
		args = args,
		env = env,
		internal_execution = internal_execution,
	})
end

return adapter
