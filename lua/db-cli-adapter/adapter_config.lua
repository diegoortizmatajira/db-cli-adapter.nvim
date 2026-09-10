--- Escapes a value for safe use inside a SQL single-quoted string literal.
--- Prevents SQL injection by doubling any embedded single quotes.
--- @param value string The raw value to escape
--- @return string The escaped value, safe to interpolate into '...' in SQL
local function escape_sql_literal(value)
	if type(value) ~= "string" then
		return tostring(value)
	end
	return (value:gsub("'", "''"))
end

--- @class DbCliAdapter.AdapterConfig defines the configuration for an individual adapter
--- @field name string The name of the adapter
--- @field command string The command to invoke the database CLI
--- @field dump_command? string The command used to produce a backup dump (defaults to `command` when unset)
--- @field supports_backup_restore boolean Whether this adapter implements get_backup_args/get_restore_args
--- @field schemas_query? string The query to list schemas in the database
--- @field tables_query? string The query to list tables in the database
--- @field table_columns_query? string The query to list fields/columns of a table
--- @field views_query? string The query to list views in the database
--- @field line_preprocessor? fun(line: string): string A function to preprocess each line of output before parsing
local AdapterConfig = {
	name = "",
	command = "",
	supports_backup_restore = false,
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
            WHERE c.table_schema = '%s'
                AND c.table_name = '%s';]],
		views_query = [[SELECT table_name, table_schema
		    FROM information_schema.views
		    WHERE table_schema = '%s'
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
	if self.dump_command and self.dump_command ~= self.command then
		utils.check_executable(self.dump_command)
	end
end

--- Sends a query to the database, should be overridden by specific adapters
--- @param command string The SQL command to execute
--- @param params DbCliAdapter.base_params Connection parameters
--- @param opts? DbCliAdapter.RunOptions Optional table of execution parameters:
function AdapterConfig:query(command, params, opts)
	vim.notify("Query method not implemented for adapter: " .. self.name, vim.log.levels.WARN)
end

--- Returns the argv/env for a command that writes a plain-SQL backup dump to stdout.
--- Should be overridden by adapters that set `supports_backup_restore = true`.
--- @param params DbCliAdapter.base_params Connection parameters
--- @return string[]|nil args, table<string,string>|nil env, string|nil err
function AdapterConfig:get_backup_args(params)
	return nil, nil, "Backup is not supported for adapter: " .. self.name
end

--- Returns the argv/env for a command that reads a plain-SQL dump from stdin and applies it.
--- Should be overridden by adapters that set `supports_backup_restore = true`.
--- @param params DbCliAdapter.base_params Connection parameters
--- @return string[]|nil args, table<string,string>|nil env, string|nil err
function AdapterConfig:get_restore_args(params)
	return nil, nil, "Restore is not supported for adapter: " .. self.name
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
	local full_cmd = vim.list_extend({ opts.cmd }, opts.args or {})
	local escaped = vim.tbl_map(vim.fn.shellescape, full_cmd)
	local command = table.concat(escaped, " ")
	-- Clear empty env to avoid issues with vim.fn.jobstart
	if opts and opts.env and next(opts.env) == nil then
		opts.env = nil
	end
	local output_lines = {}
	local error_lines = {}
	vim.fn.jobstart(command, {
		stdout_buffered = true,
		stderr_buffered = true,
		env = opts.env,
		on_stdout = function(_, data, _)
			if data then
				vim.list_extend(output_lines, data)
			end
		end,
		on_stderr = function(_, data, _)
			if data then
				vim.list_extend(error_lines, data)
			end
		end,
		on_exit = function()
			vim.schedule(function()
				if #error_lines > 0 then
					local msg = table.concat(error_lines, "\n")
					if msg ~= "" then
						vim.notify(msg, vim.log.levels.ERROR)
					end
				end
				local result = self:parse_output(output_lines)
				opts.callback(result)
			end)
		end,
	})
end

--- @class DbCliAdapter.RedirectOptions
--- @field mode ">"|"<" Redirection direction: ">" writes stdout to `path` (backup), "<" feeds `path` as stdin (restore)
--- @field path string The host filesystem path to redirect to/from

--- @class DbCliAdapter.RedirectedExecutionOptions
--- @field cmd string The command to execute
--- @field args string[] A list of arguments to pass to the command
--- @field env? table<string, string> Optional environment variables to set for the command
--- @field redirect DbCliAdapter.RedirectOptions Redirection to apply to the command
--- @field callback fun(ok: boolean) Called with true on a zero exit code, false otherwise

--- Executes a command with stdin/stdout redirected to a host file via the shell.
--- Used for backup/restore, where output must land on disk (or be fed in from disk)
--- without ever passing through a Lua callback that could mangle binary data.
--- @param opts DbCliAdapter.RedirectedExecutionOptions
function AdapterConfig:run_redirected(opts)
	local full_cmd = vim.list_extend({ opts.cmd }, opts.args or {})
	local escaped = vim.tbl_map(vim.fn.shellescape, full_cmd)
	table.insert(escaped, opts.redirect.mode)
	table.insert(escaped, vim.fn.shellescape(opts.redirect.path))
	local command = table.concat(escaped, " ")
	local env = opts.env
	if env and next(env) == nil then
		env = nil
	end
	local error_lines = {}
	vim.fn.jobstart(command, {
		stderr_buffered = true,
		env = env,
		on_stderr = function(_, data, _)
			if data then
				vim.list_extend(error_lines, data)
			end
		end,
		on_exit = function(_, exit_code, _)
			vim.schedule(function()
				local msg = table.concat(error_lines, "\n")
				if msg ~= "" then
					vim.notify(msg, exit_code == 0 and vim.log.levels.WARN or vim.log.levels.ERROR)
				end
				opts.callback(exit_code == 0)
			end)
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
	return string.format(self.tables_query, escape_sql_literal(schema))
end

--- Returns the query to list views in the database for a specific schema
--- @param schema string The schema name to filter views
--- @return string|fun(connection:DbCliAdapter.base_params): string result The literal query string or a function that returns the query string
function AdapterConfig:get_views_query(schema)
	if not self.views_query then
		vim.notify("Views query not defined for adapter: " .. self.name, vim.log.levels.WARN)
		return ""
	end
	return string.format(self.views_query, escape_sql_literal(schema))
end

--- Returns the query to list fields/columns of a specific table in a specific schema
--- @param schema string The schema name where the table resides
--- @param table string The table name to get columns for
--- @return string|fun(connection:DbCliAdapter.base_params): string result The literal query string or a function that returns the query string
function AdapterConfig:get_table_columns_query(schema, table)
	if not self.table_columns_query then
		vim.notify("Table columns query not defined for adapter: " .. self.name, vim.log.levels.WARN)
		return ""
	end
	return string.format(self.table_columns_query, escape_sql_literal(schema), escape_sql_literal(table))
end

--- Returns a query to list primary key columns for a table.
--- @param schema string|nil The schema name where the table resides
--- @param table_name string The table name
--- @return string result The query string
function AdapterConfig:get_primary_keys_query(schema, table_name)
	if not table_name or table_name == "" then
		return ""
	end
	local filters = {
		"tc.constraint_type = 'PRIMARY KEY'",
		string.format("kcu.table_name = '%s'", escape_sql_literal(table_name)),
	}
	if schema and schema ~= "" then
		table.insert(filters, string.format("kcu.table_schema = '%s'", escape_sql_literal(schema)))
	end
	return string.format(
		[[SELECT kcu.column_name
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
	ON tc.constraint_name = kcu.constraint_name
	AND tc.table_schema = kcu.table_schema
WHERE %s
ORDER BY kcu.ordinal_position;]],
		table.concat(filters, " AND ")
	)
end

--- Quotes an identifier for SQL statements.
--- @param identifier string
--- @return string
function AdapterConfig:quote_identifier(identifier)
	return string.format('"%s"', tostring(identifier):gsub('"', '""'))
end

--- Returns a fully-qualified, quoted reference to a table/view within a schema.
--- Adapters without real schema support (e.g. SQLite) should override this.
--- @param schema string|nil The schema name, if applicable for this adapter
--- @param table_name string The table/view name
--- @return string
function AdapterConfig:qualify_table_name(schema, table_name)
	if schema and schema ~= "" then
		return string.format("%s.%s", self:quote_identifier(schema), self:quote_identifier(table_name))
	end
	return self:quote_identifier(table_name)
end

--- Builds a `SELECT` statement listing explicit columns for a table/view, capped to at most
--- `limit` rows. The default implementation appends a standard `LIMIT` clause, which covers
--- every built-in adapter; adapters with a different row-limiting dialect (e.g. `TOP`,
--- `FETCH FIRST ... ROWS ONLY`) should override this method.
--- @param schema string|nil The schema name where the table/view resides
--- @param table_name string The table/view name to select from
--- @param columns string[] Already-quoted column identifiers to select
--- @param limit? number Maximum number of rows to return; nil or 0 disables the limit
--- @return string
function AdapterConfig:build_select_query(schema, table_name, columns, limit)
	local statement =
		string.format("SELECT %s FROM %s", table.concat(columns, ", "), self:qualify_table_name(schema, table_name))
	if limit and limit > 0 then
		statement = statement .. string.format(" LIMIT %d", limit)
	end
	return statement
end

--- Formats a value as an SQL literal.
--- @param value any
--- @return string
function AdapterConfig:format_literal(value)
	if value == nil then
		return "NULL"
	end
	return string.format("'%s'", escape_sql_literal(tostring(value)))
end

--- @class DbCliAdapter.ColumnDefinition
--- @field name string The column name
--- @field data_type string The column's reported data type
--- @field is_primary_key boolean Whether the column is (part of) the primary key

--- Returns a query whose result's single column already holds the full DDL statement for a
--- table/view, when the adapter has cheap, engine-native access to it (e.g. SQLite's
--- `sqlite_master.sql`, or a view's stored definition). Returns nil by default: the sidebar
--- falls back to reconstructing a `CREATE TABLE` from column metadata for tables, and reports
--- DDL generation as unsupported for views.
--- @param schema string|nil The schema name where the table/view resides
--- @param table_name string The table/view name
--- @param kind "table"|"view" Whether the target is a table or a view
--- @return string|fun(connection:DbCliAdapter.base_params): string|nil
function AdapterConfig:get_native_ddl_query(schema, table_name, kind)
	return nil
end

--- Extracts the DDL statement text from a `get_native_ddl_query` result. Assumes a single row
--- whose last column holds the full statement; adapters overriding `get_native_ddl_query` with
--- a different result shape should override this too.
--- @param result DbCliAdapter.Output
--- @return string|nil
function AdapterConfig:extract_native_ddl(result)
	local row = result and result.data and result.data.rows and result.data.rows[1]
	return row and row[#row] or nil
end

--- Builds a best-effort `CREATE TABLE` statement from column metadata (name, reported data
--- type, primary key membership). Used as a fallback when the adapter has no cheaper native
--- DDL query. Does not include defaults, indexes, foreign keys or check constraints.
--- @param schema string|nil The schema name where the table resides
--- @param table_name string The table name
--- @param columns DbCliAdapter.ColumnDefinition[] The table's columns
--- @return string
function AdapterConfig:build_create_table_query(schema, table_name, columns)
	local lines = {}
	local pk_columns = {}
	for _, column in ipairs(columns) do
		table.insert(lines, string.format("  %s %s", self:quote_identifier(column.name), column.data_type))
		if column.is_primary_key then
			table.insert(pk_columns, self:quote_identifier(column.name))
		end
	end
	if #pk_columns > 0 then
		table.insert(lines, string.format("  PRIMARY KEY (%s)", table.concat(pk_columns, ", ")))
	end
	return string.format(
		"CREATE TABLE %s (\n%s\n);",
		self:qualify_table_name(schema, table_name),
		table.concat(lines, ",\n")
	)
end

--- Builds a `WHERE` clause matching each primary key column to a `?` placeholder, joined with
--- `AND`. Returns a `<condition>` placeholder when no primary key columns are known.
--- @param pk_column_names string[]|nil
--- @return string
function AdapterConfig:_build_pk_placeholder_where(pk_column_names)
	if not pk_column_names or #pk_column_names == 0 then
		return "<condition>"
	end
	local predicates = {}
	for _, name in ipairs(pk_column_names) do
		table.insert(predicates, string.format("%s = ?", self:quote_identifier(name)))
	end
	return table.concat(predicates, " AND ")
end

--- Builds an `INSERT` scaffold with `?` value placeholders for every column.
--- @param schema string|nil The schema name where the table resides
--- @param table_name string The table name
--- @param column_names string[] The table's column names
--- @return string
function AdapterConfig:build_insert_query(schema, table_name, column_names)
	local quoted_columns = {}
	local placeholders = {}
	for _, name in ipairs(column_names) do
		table.insert(quoted_columns, self:quote_identifier(name))
		table.insert(placeholders, "?")
	end
	return string.format(
		"INSERT INTO %s (%s)\nVALUES (%s);",
		self:qualify_table_name(schema, table_name),
		table.concat(quoted_columns, ", "),
		table.concat(placeholders, ", ")
	)
end

--- Builds an `UPDATE` scaffold with `?` placeholders for every non-primary-key column and a
--- `WHERE` clause matching primary key columns to `?` placeholders.
--- @param schema string|nil The schema name where the table resides
--- @param table_name string The table name
--- @param column_names string[] The table's column names
--- @param pk_column_names string[]|nil The table's primary key column names
--- @return string
function AdapterConfig:build_update_query(schema, table_name, column_names, pk_column_names)
	local assignments = {}
	for _, name in ipairs(column_names) do
		if not vim.tbl_contains(pk_column_names or {}, name) then
			table.insert(assignments, string.format("%s = ?", self:quote_identifier(name)))
		end
	end
	return string.format(
		"UPDATE %s\nSET %s\nWHERE %s;",
		self:qualify_table_name(schema, table_name),
		table.concat(assignments, ",\n    "),
		self:_build_pk_placeholder_where(pk_column_names)
	)
end

--- Builds a `DELETE` scaffold with a `WHERE` clause matching primary key columns to `?`
--- placeholders.
--- @param schema string|nil The schema name where the table resides
--- @param table_name string The table name
--- @param pk_column_names string[]|nil The table's primary key column names
--- @return string
function AdapterConfig:build_delete_query(schema, table_name, pk_column_names)
	return string.format(
		"DELETE FROM %s\nWHERE %s;",
		self:qualify_table_name(schema, table_name),
		self:_build_pk_placeholder_where(pk_column_names)
	)
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

return AdapterConfig
