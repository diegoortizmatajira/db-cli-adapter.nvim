local config = require("db-cli-adapter.config")
local M = {
	--- @type DbCliAdapter.Config
	config = config.default,
}

--- Initialize the configuration for the db-cli-adapter plugin.
--- @param opts DbCliAdapter.Config|nil User-provided configuration options to override defaults
function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})
end

--- Retrieves a list of available database connections.
---
--- This function gathers all available connections based on the configured sources
--- in `M.config.sources`. If `cache_only` is set to `true`, it will return cached
--- connections if they are available, avoiding a re-fetch from the source files.
---
--- The sources can be file paths or functions returning file paths containing
--- JSON-encoded connection data. The function reads these files, decodes the
--- JSON data, and constructs a table of connections. Connections are identified
--- by their name and the source they come from.
---
--- If the source file or path is invalid or unreadable, it will be skipped.
---
--- @param cache_only boolean|nil If true, only return cached connections instead of re-fetching.
--- @return table A table of available connections, where the keys are connection names
---   (formatted as "name (from source_key)") and the values are the connection details.
function M.get_available_connections(cache_only)
	if cache_only and M._cached_connections then
		return M._cached_connections
	end

	local connections = {}
	for key, source_path in pairs(M.config.sources) do
		if type(source_path) == "function" then
			source_path = source_path()
		end
		if source_path and source_path ~= "" and vim.fn.filereadable(source_path) == 1 then
			local file_content = vim.fn.readfile(source_path)
			local decoded = vim.fn.json_decode(table.concat(file_content, "\n"))
			if decoded and type(decoded) == "table" then
				for name, conn in pairs(decoded) do
					connections[string.format("%s (from %s)", name, key)] = conn
				end
			end
		end
	end
	M._cached_connections = connections
	return connections
end

--- Prompts the user to select a database connection from the available connections.
--- The selected connection will be stored in the buffer-local variable `vim.b.db_cli_adapter_connection`.
--- If a callback is provided, it will be executed after the connection is selected.
---
--- @param callback function|nil A function to call after the connection is selected. The callback will be executed only if a connection is successfully chosen.
function M.select_connection(callback)
	local connections = M.get_available_connections()
	local connection_names = vim.tbl_keys(connections)
	if #connection_names == 0 then
		vim.notify("No connections available to select", vim.log.levels.WARN)
	end
	vim.ui.select(connection_names, { prompt = "Select a connection:" }, function(choice)
		if choice then
			vim.b.db_cli_adapter_connection = choice
			if callback then
				-- Execute the callback after setting the connection
				callback()
			end
		else
			vim.notify("No connection selected", vim.log.levels.WARN)
		end
	end)
end

--- Executes a database query using the selected connection.
--- If no connection is specified in the options and no buffer-local connection is set,
--- it will notify the user with an error message.
---
--- @param query string The query to be executed.
--- @param opts table|nil Optional execution parameters:
---   - connection (string|nil): The name of the connection to use. If not provided,
---     the buffer-local connection (`vim.b.db_cli_adapter_connection`) will be used.
--- If the connection is not found or the adapter for the connection is not configured,
--- it will notify the user with an error message.
local function _run(query, opts)
	opts = opts or {}
	if opts and not opts.connection then
		if vim.b.db_cli_adapter_connection then
			opts.connection = vim.b.db_cli_adapter_connection
		else
			vim.notify("No connection selected, cannot run query", vim.log.levels.ERROR)
			return
		end
	end
	local connections = M.get_available_connections(true)
	local connection = connections[opts.connection]
	if not connection then
		vim.notify("Connection not found: " .. opts.connection, vim.log.levels.ERROR)
		return
	end
	local adapter = M.config.adapters[connection.adapter]
	if not adapter then
		vim.notify("Adapter not found: " .. tostring(connection.adapter), vim.log.levels.ERROR)
		return
	end
	local result = adapter:query(query, connection)
	local output_module = require("db-cli-adapter.output")
	output_module.display_output(result)
end

--- Executes a database query.
---
--- This function allows you to run a database query using a pre-configured connection.
--- If no connection is specified in the provided options (`opts`), it will first
--- check for a buffer-local connection (`vim.b.db_cli_adapter_connection`). If none
--- is set, it will prompt the user to select a connection interactively.
---
--- If an interactive connection selection is required, the query execution will be
--- deferred until a connection is selected. After selecting a connection, the query
--- will proceed automatically.
---
--- @param query string The database query to execute.
--- @param opts table|nil Optional table of execution parameters:
---   - connection (string|nil): The name of the connection to use for query execution.
---     If not provided, the buffer-local connection will be used, or the user will
---     be prompted to select one.
function M.run(query, opts)
	opts = opts or {}
	if not opts.connection and not vim.b.db_cli_adapter_connection then
		M.select_connection(function()
			_run(query, opts)
		end)
		return
	end
	_run(query, opts)
end

--- Retrieves the visually selected text in the current buffer.
---
--- This function identifies the range of visually selected lines in the current
--- buffer and extracts the selected text. It adjusts the text boundaries to
--- ensure only the selected portion is included, considering both the start
--- and end columns of the selection.
---
--- The function is useful for scenarios where a specific portion of the text
--- needs to be processed, such as running a database query on a selected range
--- of lines.
---
--- @return string The text within the visually selected range, or an empty string if no text is selected.
local function get_visual_selection()
	local s_start = vim.fn.getpos("'<")
	local s_end = vim.fn.getpos("'>")

	local start_line = s_start[2]
	local start_col = s_start[3]
	local end_line = s_end[2]
	local end_col = s_end[3]

	local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)

	if #lines == 0 then
		return ""
	end

	-- Trim first and last lines to exact columns
	lines[1] = string.sub(lines[1], start_col, #lines[1])
	if #lines == 1 then
		lines[1] = string.sub(lines[1], 1, end_col - start_col + 1)
	else
		lines[#lines] = string.sub(lines[#lines], 1, end_col)
	end

	return table.concat(lines, "\n")
end

local function get_statement_at_cursor()
	--- @param node TSNode
	local function lookup(node, type)
		if node:type() == type then
			return node
		end
		local parent = node:parent()
		if parent then
			return lookup(parent, type)
		end
	end
	local bufnr = 0
	local current_node = vim.treesitter.get_node({ lang = "sql" })
	if current_node then
		local statement_node = lookup(current_node, "statement")
		if statement_node then
			return vim.treesitter.get_node_text(statement_node, bufnr)
		end
	end
	return ""
end

--- Executes a selected range of lines as a database query.
---
--- This function allows the user to execute a query based on a range of selected lines
--- within the current buffer. The lines are joined together to form the query, which
--- is then executed using the configured database connection.
---
--- If no connection is specified in the `opts` parameter and no buffer-local connection
--- is set, the user will be prompted to select a connection interactively before the
--- query is executed.
---
--- @param opts table|nil Optional table of execution parameters:
---   - connection (string|nil): The name of the connection to use for query execution.
---     If not provided, the buffer-local connection will be used, or the user will be
---     prompted to select one.
function M.run_at_cursor(opts)
	local command = get_visual_selection()
	if command == "" then
		command = get_statement_at_cursor()
		if command == "" then
			vim.notify("No text selected", vim.log.levels.WARN)
			return
		end
	end
	vim.notify(string.format("Executing query:\n%s", command), vim.log.levels.INFO)
	-- Execute the command or pass it to the database CLI
	M.run(command, opts)
end

--- Executes the entire content of a specified buffer as a database query.
---
--- This function retrieves all lines from the given buffer, combines them into a single
--- query string, and executes the query using the configured database connection.
---
--- If no connection is specified in the `opts` parameter and no buffer-local connection
--- is set, the user will be prompted to select a connection interactively before the
--- query is executed.
---
--- @param bufnr number|nil The buffer number to execute. If not provided, the current buffer is used.
--- @param opts table|nil Optional table of execution parameters:
---   - connection (string|nil): The name of the connection to use for query execution.
---     If not provided, the buffer-local connection will be used, or the user will
---     be prompted to select one.
function M.run_buffer(bufnr, opts)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local all_text = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
	M.run(all_text, opts)
end

--- Opens the source file for editing connections associated with the given key.
---
--- This function locates the source file associated with the specified key from the configuration,
--- and opens it in an editor. If the source file path is dynamically provided via a function,
--- the function is evaluated to get the actual path. If the source file or directory does not exist,
--- the directory is created automatically.
---
--- @param key string The key identifying the connections source in the configuration.
---                    The key must be present in `M.config.sources`.
function M.edit_connections_source(key)
	local source_path = M.config.sources[key]
	if type(source_path) == "function" then
		source_path = source_path()
	end
	if not source_path or source_path == "" then
		vim.notify(string.format("No connections source file configured for key '%s'", key), vim.log.levels.ERROR)
		return
	end
	local source_dir = vim.fn.fnamemodify(source_path, ":h")
	vim.fn.mkdir(source_dir, "p")
	vim.cmd("edit " .. source_path)
end

function M.get_current_db_connection()
	if vim.b.db_cli_adapter_connection then
		return string.format("󰪩 %s", vim.b.db_cli_adapter_connection)
	end
	return ""
end

return M
