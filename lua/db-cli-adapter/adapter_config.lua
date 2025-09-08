--- @class DbCliAdapter.AdapterConfig defines the configuration for an individual adapter
--- @field name string The name of the adapter
--- @field command string The command to invoke the database CLI
--- @field schemasQuery? string The query to list schemas in the database
--- @field tablesQuery? string The query to list tables in the database
--- @field viewsQuery? string The query to list views in the database
AdapterConfig = {
	name = "",
	command = "",
}

--- Creates a new instance of AdapterConfig
--- @param config DbCliAdapter.AdapterConfig
--- @return DbCliAdapter.AdapterConfig A new instance of AdapterConfig
function AdapterConfig:new(config)
	local data = vim.tbl_deep_extend("force", {
		schemasQuery = [[SELECT schema_name FROM information_schema.schemata;]],
		tablesQuery = [[SELECT table_name, table_schema
		FROM information_schema.tables 
		WHERE table_type='BASE TABLE' 
		AND table_schema NOT IN ('pg_catalog', 'information_schema')
		ORDER by table_name;]],
		viewsQuery = [[SELECT table_name, table_schema
        FROM information_schema.views 
        WHERE table_schema NOT IN ('pg_catalog', 'information_schema')
        ORDER by table_name;]],
	}, config)
	local o = setmetatable(data, self)
	self.__index = self
	return o
end

--- Validates the command is available in the system
function AdapterConfig:health_check()
	local utils = require("db-cli-adapter.utils")
	utils.check_executable(self.command)
end

--- Sends a query to the database, should be overridden by specific adapters
--- @param command string The SQL command to execute
--- @param params DbCliAdapter.base_params Connection parameters
--- @param internal_execution boolean|nil If true, the command is being executed internally and should not open a UI
--- @return DbCliAdapter.Output A structured representation of the query result
function AdapterConfig:query(command, params, internal_execution)
	vim.notify("Query method not implemented for adapter: " .. self.name, vim.log.levels.WARN)
	return {
		data = nil,
		row_count = 0,
		message = "Query method not implemented",
	}
end

--- Parses the output from the executed command and converts it into a structured format.
--- This method provides a default implementation that returns the output as-is,
--- with a minimal structure containing row count and a success message.
---
--- Specific adapters can override this method to implement custom parsing logic
--- based on the output format of their respective database CLI.
---
--- @param output string[] The raw output lines from the executed command
--- @return DbCliAdapter.Output A structured representation of the parsed output
function AdapterConfig:parse_output(output)
	--- Default implementation: return the output as-is
	vim.notify("Command executed: " .. table.concat(output, "\n"), vim.log.levels.DEBUG)
	--- @type DbCliAdapter.Output
	return {
		data = {
			column_names = { "SampleA", "SampleB", "SampleC" },
			rows = {
				{ "ValueA1", "ValueB1", "ValueC1" },
				{ "ValueA2", "ValueB2", "ValueC2" },
				{ "ValueA3", "ValueB3", "ValueC3" },
			},
		},
		row_count = 3,
		message = "Command executed successfully",
	}
end

--- Executes the database CLI command with the provided arguments
--- and captures its output.
--- @param opts DbCliAdapter.ExecutionOptions Execution options including command, args, env, and UI display preference
--- @return DbCliAdapter.Output A structured representation of the parsed output
function AdapterConfig:run_command(opts)
	if opts and opts.internal_execution then
		return {
			data = nil,
			row_count = 0,
			message = "Failed to execute command",
		}
	end
	-- Use overseer.nvim to run the command and show output in a terminal window
	local overseer = require("overseer")
	overseer
		.new_task({
			cmd = opts.cmd,
			args = opts.args,
			env = opts.env,
			name = "Database command",
			strategy = "terminal",
			components = {
				{
					"open_output",
					direction = "dock",
					focus = false,
					on_complete = "always",
				},
				"default",
			},
		})
		:start()

	return {
		data = nil,
		row_count = 0,
		message = "Command sent to UI",
	}
end
