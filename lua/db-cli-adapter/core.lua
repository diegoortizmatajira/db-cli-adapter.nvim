local config = require("db-cli-adapter.config")
local M = {
	--- @type DbCliAdapter.base_params[]|nil
	_cached_connections = nil,
}

--- Retrieves a list of available database connections.
---
--- This function gathers all available connections based on the configured sources
--- in `config.current.sources`. If `cache_only` is set to `true`, it will return cached
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
--- @return table<string,DbCliAdapter.base_params> connections A table of available connections, where the keys are connection names
---   (formatted as "name (from source_key)") and the values are the connection details.
function M.get_available_connections(cache_only)
	if cache_only and M._cached_connections then
		return M._cached_connections
	end

	--- @type table<string,DbCliAdapter.base_params>
	local connections = {}
	for key, source_path in pairs(config.current.sources) do
		if type(source_path) == "function" then
			source_path = source_path()
		end
		if source_path and source_path ~= "" and vim.fn.filereadable(source_path) == 1 then
			local file_content = vim.fn.readfile(source_path)
			local decoded = vim.fn.json_decode(table.concat(file_content, "\n"))
			if decoded and type(decoded) == "table" then
				for name, conn in pairs(decoded) do
					local source_icon = config.current.icons.source[key] or key
					local adapter_icon = config.current.icons.adapter[conn.adapter]
						or config.current.icons.adapter.default
						or "󰪩"
					connections[string.format("%s%s %s", source_icon, adapter_icon, name)] = conn
				end
			end
		end
	end
	M._cached_connections = connections
	return connections
end

--- Sets a callback function to be executed when the database connection changes.
--- This function assigns the provided callback to a buffer-local variable
--- `vim.b.db_cli_adapter_connection_changed`, which can be triggered later when the connection changes.
--- @param callback fun(connection: string) A function to be called when the connection changes. The function should accept one argument
function M.set_connection_changed_callback(callback)
	vim.b.db_cli_adapter_connection_changed = callback
end

--- Triggers the callback function for when the database connection changes.
---
--- This function checks if a buffer-local callback function (`vim.b.db_cli_adapter_connection_changed`)
--- has been set. If such a callback exists and is a valid function, it will be invoked,
--- passing the current buffer-local connection (`vim.b.db_cli_adapter_connection`) as an argument.
---
--- The callback is expected to handle any logic related to connection changes, such as updating
--- UI components, refreshing data, or re-establishing the connection.
function M.trigger_connection_changed()
	if vim.b.db_cli_adapter_connection_changed and type(vim.b.db_cli_adapter_connection_changed) == "function" then
		vim.b.db_cli_adapter_connection_changed(vim.b.db_cli_adapter_connection)
	end
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
			M.trigger_connection_changed()
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
--- @param opts? DbCliAdapter.RunOptions Optional table of execution parameters:
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
	local adapter = config.current.adapters[connection.adapter]
	if not adapter then
		vim.notify("Adapter not found: " .. tostring(connection.adapter), vim.log.levels.ERROR)
		return
	end
	adapter:query(query, connection, opts.callback)
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
--- @param opts? DbCliAdapter.RunOptions Optional table of execution parameters:
function M.run(query, opts)
	opts = opts or {}
	if not opts.connection and not vim.b.db_cli_adapter_connection then
		M.select_connection(function()
			_run(query, opts)
		end)
		return
	end
	return _run(query, opts)
end

--- Opens the source file for editing connections associated with the given key.
---
--- This function locates the source file associated with the specified key from the configuration,
--- and opens it in an editor. If the source file path is dynamically provided via a function,
--- the function is evaluated to get the actual path. If the source file or directory does not exist,
--- the directory is created automatically.
---
--- @param key? string The key identifying the connections source in the configuration.
---                    The key must be present in `config.current.sources`.
function M.edit_connections_source(key)
	local function edit(selected_key)
		local source_path = config.current.sources[selected_key]
		if type(source_path) == "function" then
			source_path = source_path()
		end
		if not source_path or source_path == "" then
			vim.notify(
				string.format("No connections source file configured for key '%s'", selected_key),
				vim.log.levels.ERROR
			)
			return
		end
		local source_dir = vim.fn.fnamemodify(source_path, ":h")
		vim.fn.mkdir(source_dir, "p")
		vim.cmd("edit " .. source_path)
	end
	if key and key ~= "" then
		vim.notify("Editing connections source for key: " .. key)
		edit(key)
	else
		vim.notify("Select which connections source to edit")
		local source_names = vim.tbl_keys(config.current.sources)
		vim.ui.select(source_names, { prompt = "Select which connections to edit:" }, function(choice)
			if choice then
				edit(choice)
			else
				vim.notify("No source selected", vim.log.levels.WARN)
			end
		end)
	end
end

function M.get_buffer_db_connection()
	return vim.b.db_cli_adapter_connection
end

function M.buffer_has_db_connection()
	return M.get_buffer_db_connection() ~= nil
end

function M.get_buffer_db_adapter()
	local connection_name = M.get_buffer_db_connection()
	if not connection_name then
		return nil
	end
	local connections = M.get_available_connections(true)
	local connection = connections[connection_name]
	if not connection then
		return nil
	end
	local adapter = config.current.adapters[connection.adapter]
	return adapter
end

return M
