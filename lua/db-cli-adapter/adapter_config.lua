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
--- @param callback fun(result: DbCliAdapter.Output) A callback function to handle the query result
function AdapterConfig:query(command, params, callback)
	vim.notify("Query method not implemented for adapter: " .. self.name, vim.log.levels.WARN)
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
	local rows = {}
	for _, line in ipairs(output) do
		table.insert(rows, { line })
	end
	--- @type DbCliAdapter.Output
	return {
		data = {
			column_names = { "Line" },
			rows = rows,
		},
		row_count = output and #output or 0,
		message = "Command executed successfully",
	}
end

--- @param opts DbCliAdapter.ExecutionOptions Execution options including command, args, env, and UI display preference
local function _run_with_plenary(opts)
	vim.notify("Running with plenary " .. vim.inspect(opts), vim.log.levels.INFO)
	local Job = require("plenary.job")
	local job_instance = Job:new({
		command = opts.cmd,
		args = opts.args,
		env = opts.env,
		on_exit = function(j, return_val)
			vim.schedule(function()
				if return_val ~= 0 then
					vim.notify("Command execution has failed", vim.log.levels.ERROR)
					return
				end
				local lines = j:result()
				vim.notify("Raw output: " .. table.concat(lines, "\n"), vim.log.levels.INFO)
				local result = AdapterConfig:parse_output(lines)
				opts.callback(result)
			end) -- Ensure we are in the main thread
		end,
	})
	job_instance:start()
end

--- Executes the database CLI command with the provided arguments
--- and displays output using overseer.nvim.
--- @param opts DbCliAdapter.ExecutionOptions Execution options including command, args, env, and UI display preference
local function _run_with_overseer(opts)
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
end

--- Executes the database CLI command with the provided arguments
--- and captures its output.
--- @param opts DbCliAdapter.ExecutionOptions Execution options including command, args, env, and UI display preference
function AdapterConfig:run_command(opts)
	if opts and opts.callback then
		_run_with_plenary(opts)
		return
	end
	_run_with_overseer(opts)
end
