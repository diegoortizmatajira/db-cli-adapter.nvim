local core = require("db-cli-adapter.core")
local config = require("db-cli-adapter.config")
local nodes = require("db-cli-adapter.sidebar.nodes")
local output = require("db-cli-adapter.output")

local Split = require("nui.split")
local NuiTree = require("nui.tree")
local NuiLine = require("nui.line")

local M = {
	split = nil,
	tree = nil,
	-- Window the sidebar was last opened from, so query buffers can be opened there
	-- instead of always splitting.
	previous_winid = nil,
}

--- Attempt to refresh the sidebar with the selected adapter.
--- This function ensures that a database adapter is available and connected before attempting the refresh.
--- If no adapter is selected, it prompts the user to select one.
--- @param callback fun(tree: NuiTree, adapter: DbCliAdapter.AdapterConfig) The function to execute once the adapter is retrieved and ready.
local function _try_refresh_with_adapter(callback, silent)
	if not callback then
		return
	end
	local wrapper = function()
		local adapter = core.get_buffer_db_adapter()
		if not adapter then
			if not silent then
				vim.notify("DbCliAdapter: No selected adapter", vim.log.levels.WARN)
			end
			return
		end
		callback(M.tree, adapter)
	end
	-- Ensure a database connection is selected
	if not core.buffer_has_db_connection() then
		core.select_connection(wrapper)
		return
	end
	wrapper()
end

--- Attempt to refresh the nearest ancestor node with a refresh function.
--- If the provided node has a refresh function, it will be called.
--- If not, the function will traverse up the tree to find the nearest ancestor with a refresh function and call it.
--- @param node? DbCliAdapter.SidebarNodeData|NuiTree.Node The tree node to start the search from.
--- @param silent? boolean Whether to suppress notifications if no adapter is found.
local function try_refresh(node, silent)
	while node do
		if node.refresh then
			_try_refresh_with_adapter(function(tree, adapter)
				node:refresh(tree, adapter)
			end, silent)
			return
		end
		node = M.tree:get_node(node:get_parent_id())
	end
end

--- Whether a node represents a table or view (i.e. carries schema/table identity fields).
--- @param node DbCliAdapter.SidebarNodeData|NuiTree.Node|nil
--- @return boolean
local function _is_relation_node(node)
	return node ~= nil and node.table_name ~= nil and node.schema ~= nil
end

--- Builds a `SELECT <columns> FROM <schema>.<table>` statement (capped by
--- `config.current.sidebar.query_row_limit`) for a table/view node. Reuses already-loaded
--- column child nodes when available, otherwise queries the adapter for the column list.
--- @param node DbCliAdapter.SidebarNodeData|NuiTree.Node A table/view node
--- @param adapter DbCliAdapter.AdapterConfig The adapter for the sidebar's connection
--- @param callback fun(query: string|nil) Called with the built statement, or nil on failure
local function _build_select_query(node, adapter, callback)
	local function from_column_names(column_names)
		if #column_names == 0 then
			vim.notify(string.format("No columns found for '%s'", node.table_name), vim.log.levels.ERROR)
			callback(nil)
			return
		end
		local quoted_columns = {}
		for _, column_name in ipairs(column_names) do
			table.insert(quoted_columns, adapter:quote_identifier(column_name))
		end
		callback(
			adapter:build_select_query(
				node.schema,
				node.table_name,
				quoted_columns,
				config.current.sidebar.query_row_limit
			)
		)
	end

	if node:has_children() then
		local column_names = {}
		for _, child_id in ipairs(node:get_child_ids()) do
			local child = M.tree:get_node(child_id)
			if child then
				table.insert(column_names, child.text)
			end
		end
		if #column_names > 0 then
			from_column_names(column_names)
			return
		end
	end

	core.run(adapter:get_table_columns_query(node.schema, node.table_name), {
		callback = function(result)
			if not result or not result.data then
				vim.notify(string.format("Could not resolve columns for '%s'", node.table_name), vim.log.levels.ERROR)
				callback(nil)
				return
			end
			local column_names = {}
			for _, row in ipairs(result.data.rows) do
				table.insert(column_names, row[1])
			end
			from_column_names(column_names)
		end,
	})
end

--- Switches to the window the sidebar was opened from and loads a new empty buffer there,
--- like a normal file open. Falls back to a new full-width split if that window is gone
--- (e.g. it was closed) so the buffer never ends up squeezed into the narrow sidebar column.
local function _open_query_buffer()
	if M.previous_winid and vim.api.nvim_win_is_valid(M.previous_winid) then
		vim.api.nvim_set_current_win(M.previous_winid)
		vim.cmd("enew")
	else
		vim.cmd("botright new")
	end
end

--- Attempt to expand a tree node if it is expandable and not already expanded.
--- If the node has a refresh function and is marked as expandable but has no children loaded,
--- it will call the refresh function to load its children before expanding.
--- @param node DbCliAdapter.SidebarNodeData|NuiTree.Node The tree node to attempt to expand.
--- @return boolean True if the node was expanded, false otherwise.
local function try_expand_node(node)
	if node and not node:is_expanded() then
		if node:has_children() then
			node:expand()
			return true
		elseif node.expandable and node.count == nil then
			try_refresh(node, true)
			return false
		end
	end
	return false
end

function M.init()
	if not config.current then
		vim.notify("DbCliAdapter: Configuration not found.", vim.log.levels.ERROR)
		return
	end
	M.previous_winid = vim.api.nvim_get_current_win()
	M.split = Split({
		relative = "editor",
		position = "right",
		size = "30%",
	})
	M.split:mount()
	nodes.database_node = nodes.newDatabaseNode("Database")
	M.tree = NuiTree({
		bufnr = M.split.bufnr,
		nodes = { nodes.database_node },
		prepare_node = function(node)
			local line = NuiLine()
			line:append(string.rep("  ", node:get_depth() - 1))
			line:append(
				node:has_children()
						and (node:is_expanded() and config.current.icons.tree.chevron_open or config.current.icons.tree.chevron_closed)
					or (node.expandable and config.current.icons.tree.chevron_closed or "  "),
				config.current.highlight.tree.chevron
			)
			if node.icon then
				line:append(node.icon, node.icon_hl or config.current.highlight.tree.default_icon)
			end
			line:append(node.text)
			if node.count then
				line:append(" (" .. node.count .. ")", "@comment")
			end
			if node.description then
				line:append(" " .. node.description, "@comment")
			end
			return line
		end,
		buf_options = {
			buftype = "nofile",
			filetype = "db-cli-sidebar",
			swapfile = false,
			bufhidden = "hide",
		},
		win_options = {},
	})
	M.tree:render()
	--- Map keys for toggling expand/collapse of a tree node
	for _, key in ipairs(config.current.sidebar.keybindings.toggle_expand) do
		M.split:map("n", key, function()
			local node = M.tree:get_node()
			if node then
				if node:is_expanded() then
					node:collapse()
				else
					try_expand_node(node)
				end
				M.tree:render()
			end
		end)
	end
	-- Map keys for expanding a tree node
	for _, key in ipairs(config.current.sidebar.keybindings.expand) do
		M.split:map("n", key, function()
			local node = M.tree:get_node()
			if node and try_expand_node(node) then
				M.tree:render()
			end
		end)
	end
	-- Map keys for collapsing a tree node
	for _, key in ipairs(config.current.sidebar.keybindings.collapse) do
		M.split:map("n", key, function()
			local node = M.tree:get_node()
			if node and node:has_children() then
				node:collapse()
				M.tree:render()
			end
		end)
	end
	-- Map keys for refreshing the selected node
	for _, key in ipairs(config.current.sidebar.keybindings.refresh) do
		M.split:map("n", key, function()
			local node = M.tree:get_node()
			if not node then
				return
			end
			try_refresh(node)
		end)
	end
	-- Map keys for refreshing the sidebar
	for _, key in ipairs(config.current.sidebar.keybindings.refresh_all) do
		M.split:map("n", key, function()
			M.refresh()
		end)
	end
	-- Map keys for executing an invisible SELECT query on a table/view node and opening the result panel
	for _, key in ipairs(config.current.sidebar.keybindings.execute_query) do
		M.split:map("n", key, function()
			local node = M.tree:get_node()
			if not _is_relation_node(node) then
				vim.notify("DbCliAdapter: Select a table or view node to execute a query", vim.log.levels.WARN)
				return
			end
			_try_refresh_with_adapter(function(_, adapter)
				_build_select_query(node, adapter, function(query)
					if not query then
						return
					end
					core.run(query, output.set_csv_output_handler({}))
				end)
			end)
		end)
	end
	-- Map keys for opening a new SQL buffer, bound to the sidebar's connection, pre-filled
	-- with a SELECT query for the table/view node under the cursor
	for _, key in ipairs(config.current.sidebar.keybindings.open_query) do
		M.split:map("n", key, function()
			local node = M.tree:get_node()
			if not _is_relation_node(node) then
				vim.notify("DbCliAdapter: Select a table or view node to open a query", vim.log.levels.WARN)
				return
			end
			_try_refresh_with_adapter(function(_, adapter)
				local connection_name = core.get_buffer_db_connection()
				_build_select_query(node, adapter, function(query)
					if not query then
						return
					end
					_open_query_buffer()
					local bufnr = vim.api.nvim_get_current_buf()
					vim.bo[bufnr].buftype = "nofile"
					vim.bo[bufnr].bufhidden = "hide"
					vim.bo[bufnr].swapfile = false
					vim.bo[bufnr].filetype = "sql"
					vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { query })
					vim.b[bufnr].db_cli_adapter_connection = connection_name
				end)
			end)
		end)
	end
	-- Map keys for quitting the sidebar
	for _, key in ipairs(config.current.sidebar.keybindings.quit) do
		M.split:map("n", key, function()
			M.split:hide()
		end)
	end
	-- Hides gutter and number columns
	vim.opt_local.number = false
	vim.opt_local.relativenumber = false
	vim.opt_local.signcolumn = "no"
	vim.opt_local.foldcolumn = "0"

	-- Automatically refresh the sidebar when the database connection changes
	core.set_connection_changed_callback(function()
		M.refresh()
	end)
	-- Select a connection if none is selected, then refresh the sidebar
	_try_refresh_with_adapter(function()
		--- Intentionally empty
	end, true)
end

function M.refresh()
	_try_refresh_with_adapter(function(tree, adapter)
		nodes.database_node:refresh(tree, adapter)
	end)
end

function M.toggle()
	if M.split then
		if M.split.winid and vim.api.nvim_win_is_valid(M.split.winid) then
			M.split:hide()
		else
			M.previous_winid = vim.api.nvim_get_current_win()
			M.split:show()
		end
	else
		M.init()
	end
end
return M
