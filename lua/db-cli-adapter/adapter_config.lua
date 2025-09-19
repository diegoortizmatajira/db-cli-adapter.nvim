--- @class DbCliAdapter.AdapterConfig defines the configuration for an individual adapter
--- @field name string The name of the adapter
--- @field command string The command to invoke the database CLI
--- @field schemas_query? string The query to list schemas in the database
--- @field tables_query? string The query to list tables in the database
--- @field table_columns_query? string The query to list fields/columns of a table
--- @field views_query? string The query to list views in the database
--- @field line_preprocessor? fun(line: string): string A function to preprocess each line of output before parsing
AdapterConfig = {
	name = "",
	command = "",
}

--- Creates a new instance of AdapterConfig
--- @param config DbCliAdapter.AdapterConfig
--- @return DbCliAdapter.AdapterConfig A new instance of AdapterConfig
function AdapterConfig:new(config)
	local data = vim.tbl_deep_extend("force", {
		schemas_query = [[SELECT schema_name 
		    FROM information_schema.schemata
		    ORDER BY schema_name;]],
		tables_query = [[SELECT table_name, table_schema
		    FROM information_schema.tables
		    WHERE table_type='BASE TABLE' AND table_schema = '%s'
		    ORDER by table_name;]],
		table_columns_query = [[SELECT 
                c.column_name,
                c.data_type,
                CASE 
                    WHEN k.column_name IS NOT NULL THEN 1
                    ELSE 0
                END AS is_primary_key
            FROM information_schema.columns c
            LEFT JOIN information_schema.key_column_usage k
                ON c.table_name = k.table_name
                AND c.column_name = k.column_name
                AND k.constraint_name IN (
                    SELECT constraint_name
                    FROM information_schema.table_constraints
                    WHERE table_name = c.table_name
                    AND table_schema = c.table_schema
                    AND constraint_type = 'PRIMARY KEY'
                )
            WHERE c.table_name = '%s'
                AND c.table_schema = '%s';]],
		views_query = [[SELECT table_name, table_schema 
		    FROM information_schema.views 
		    WHERE table_schema NOT IN ('pg_catalog', 'information_schema') 
		    ORDER by table_name;]],
	}, config)
	local o = setmetatable(data, self)
	self.__index = self
	return o
end

--- @param params DbCliAdapter.base_params Connection parameters
function AdapterConfig:get_icon(params)
	local config = require("db-cli-adapter.config").current
	return config and (config.icons.adapter[params.adapter] or config.icons.adapter["default"]) or "󰪩 "
end

--- @param params DbCliAdapter.base_params Connection parameters
--- @return DbCliAdapter.ConnectionChangedData
function AdapterConfig:get_url_connection(params)
	return {
		name = "Empty connection",
		adapter = self.name,
	}
end

--- Validates the command is available in the system
function AdapterConfig:health_check()
	local utils = require("db-cli-adapter.utils")
	utils.check_executable(self.command)
end

--- Sends a query to the database, should be overridden by specific adapters
--- @param command string The SQL command to execute
--- @param params DbCliAdapter.base_params Connection parameters
--- @param opts? DbCliAdapter.RunOptions Optional table of execution parameters:
function AdapterConfig:query(command, params, opts)
	vim.notify("Query method not implemented for adapter: " .. self.name, vim.log.levels.WARN)
end

--- Parses the output from the executed command and converts it into a structured format.
--- This method provides a default implementation that returns the output as-is,
--- with a minimal structure containing row count and a success message.
--- This default implementation assumes the output is in a table-like format with pipes ("|")
---
--- Specific adapters can override this method to implement custom parsing logic
--- based on the output format of their respective database CLI.
---
--- @param output string[] The raw output lines from the executed command
--- @return DbCliAdapter.Output A structured representation of the parsed output
function AdapterConfig:parse_output(output)
	local function get_values(line)
		local values = vim.split(line, "|")
		-- Remove the first and last empty strings caused by leading and trailing |
		table.remove(values, 1)
		table.remove(values, #values)
		-- Trim whitespace from each value
		for i, v in ipairs(values) do
			values[i] = vim.trim(v)
		end
		return values
	end
	local headers = nil
	local rows = {}
	local discarded_lines = {}
	for _, line in ipairs(output) do
		if self.line_preprocessor then
			line = self.line_preprocessor(line)
		end
		if string.match(line, "^|%-") or not string.match(line, "^|") then
			if line ~= "" then
				table.insert(discarded_lines, line)
			end
			goto continue
		end
		if not headers then
			headers = get_values(line)
			goto continue
		end
		local values = get_values(line)
		table.insert(rows, values)

		::continue::
	end
	return {
		data = {
			column_names = headers,
			rows = rows,
		},
		row_count = rows and #rows or 0,
		message = "Command executed successfully",
		discarded_lines = discarded_lines,
	}
end

--- @param opts DbCliAdapter.ExecutionOptions Execution options including command, args, env, and UI display preference
function AdapterConfig:_run_with_system(opts)
	local shell = require("overseer.shell")
	local full_cmd = vim.list_extend({ opts.cmd }, opts.args or {})
	local command = shell.escape_cmd(full_cmd)
	-- Clear empty env to avoid issues with vim.fn.jobstart
	if opts and opts.env and next(opts.env) == nil then
		opts.env = nil
	end
	local output_lines = {}
	vim.fn.jobstart(command, {
		stdout_buffered = true,
		env = opts.env,
		on_stdout = function(_, data, _)
			if data then
				vim.list_extend(output_lines, data)
			end
		end,
		on_exit = function()
			local result = self:parse_output(output_lines)
			opts.callback(result)
		end,
	})
end

--- Executes the database CLI command with the provided arguments
--- and displays output using overseer.nvim.
--- @param opts DbCliAdapter.ExecutionOptions Execution options including command, args, env, and UI display preference
function AdapterConfig:_run_with_overseer(opts)
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
		self:_run_with_system(opts)
		return
	end
	self:_run_with_overseer(opts)
end

--- Returns the query to list schemas in the database
--- @return string|fun(connection:DbCliAdapter.base_params): string result The literal query string or a function that returns the query string
function AdapterConfig:get_schemas_query()
	if not self.schemas_query then
		vim.notify("Schemas query not defined for adapter: " .. self.name, vim.log.levels.WARN)
		return ""
	end
	return self.schemas_query
end

--- Returns the query to list tables in the database for a specific schema
--- @param schema string The schema name to filter tables
--- @return string|fun(connection:DbCliAdapter.base_params): string result The literal query string or a function that returns the query string
function AdapterConfig:get_tables_query(schema)
	if not self.tables_query then
		vim.notify("Tables query not defined for adapter: " .. self.name, vim.log.levels.WARN)
		return ""
	end
	return string.format(self.tables_query, schema)
end

--- Returns the query to list fields/columns of a specific table in a specific schema
--- @param table string The table name to get columns for
--- @param schema string The schema name where the table resides
--- @return string|fun(connection:DbCliAdapter.base_params): string result The literal query string or a function that returns the query string
function AdapterConfig:get_table_columns_query(table, schema)
	if not self.table_columns_query then
		vim.notify("Table columns query not defined for adapter: " .. self.name, vim.log.levels.WARN)
		return ""
	end
	return string.format(self.table_columns_query, table, schema)
end

--- Returns the query string to be executed
--- @param command string|fun(connection:DbCliAdapter.base_params): string The command string or a function that returns the command string
--- @param connection DbCliAdapter.base_params The connection parameters
--- @return string The resolved command string
function AdapterConfig:parse_command(command, connection)
	if type(command) == "function" then
		command = command(connection)
	end
	return command
end
