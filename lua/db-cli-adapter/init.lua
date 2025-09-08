local config = require("db-cli-adapter.config")
local core = require("db-cli-adapter.core")
local M = {}

--- Initialize the configuration for the db-cli-adapter plugin.
--- @param opts DbCliAdapter.Config|nil User-provided configuration options to override defaults
function M.setup(opts)
	local new_config = vim.tbl_deep_extend("force", config.current or config.default, opts or {})
	config.update(new_config)

	-- Create user commands
	vim.api.nvim_create_user_command("DbCliRunAtCursor", M.run_at_cursor, { range = true, nargs = 0 })
	vim.api.nvim_create_user_command("DbCliRunBuffer", M.run_buffer, { nargs = 0 })
	vim.api.nvim_create_user_command("DbCliSelectConnection", M.select_connection, { nargs = 0 })
	vim.api.nvim_create_user_command("DbCliSidebarToggle", M.toggle_sidebar, { nargs = 0 })
	vim.api.nvim_create_user_command("DbCliEditConnection", function(o)
		M.edit_connections_source(o.args)
	end, { nargs = "?" })
end

--- Prompts the user to select a database connection from the available connections.
function M.select_connection()
	core.select_connection()
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
	local mode = vim.api.nvim_get_mode().mode
	if mode ~= "v" and mode ~= "V" and mode ~= "\22" then
		return "" -- Not in visual mode
	end
	local bufnr = vim.api.nvim_get_current_buf()
	local start = vim.fn.getpos("v")
	local end_ = vim.fn.getpos(".")
	local start_row = start[2] - 1
	local start_col = start[3] - 1
	local end_row = end_[2] - 1
	local end_col = end_[3] - 1

	-- A user can start visual selection at the end and move backwards
	-- Normalize the range to start < end
	if start_row == end_row and end_col < start_col then
		end_col, start_col = start_col, end_col
	elseif end_row < start_row then
		start_row, end_row = end_row, start_row
		start_col, end_col = end_col, start_col
	end
	if mode == "V" then
		start_col = 0
		local lines = vim.api.nvim_buf_get_lines(bufnr, end_row, end_row + 1, true)
		end_col = #lines[1]
	end
	local lines = vim.api.nvim_buf_get_text(bufnr, start_row, start_col, end_row, end_col + 1, {})
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
	core.run(command, opts)
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
	core.run(all_text, opts)
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
	core.edit_connections_source(key)
end

function M.get_current_db_connection()
	if core.buffer_has_db_connection() then
		return string.format("󰪩 %s", core.get_buffer_db_connection())
	end
	return ""
end

function M.toggle_sidebar()
	local sidebar = require("db-cli-adapter.sidebar")
	sidebar.toggle()
end

return M
