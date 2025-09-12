local core = require("db-cli-adapter.core")
local config = require("db-cli-adapter.config").current
local nodes = require("db-cli-adapter.sidebar.nodes")

local Split = require("nui.split")
local NuiTree = require("nui.tree")
local NuiLine = require("nui.line")

local M = {
	split = nil,
	tree = nil,
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
		core.select_connection(wrapper())
		return
	end
	wrapper()
end

local function try_refresh(node, silent)
	while node do
		if node.refresh then
			_try_refresh_with_adapter(node.refresh, silent)
			return
		end
		node = M.tree:get_node(node:get_parent_id())
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
			node:expand()
			return true
		end
	end
	return false
end

function M.init()
	if not config then
		vim.notify("DbCliAdapter: Configuration not found.", vim.log.levels.ERROR)
		return
	end
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
						and (node:is_expanded() and config.icons.tree.chevron_open or config.icons.tree.chevron_closed)
					or (node.expandable and config.icons.tree.chevron_closed or "  "),
				config.highlight.tree.chevron
			)
			if node.icon then
				line:append(node.icon, node.icon_hl or config.highlight.tree.default_icon)
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
	vim.tbl_map(function(key)
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
	end, config.sidebar.keybindings.toggle_expand)
	-- Map keys for expanding a tree node
	vim.tbl_map(function(key)
		M.split:map("n", key, function()
			local node = M.tree:get_node()
			if try_expand_node(node) then
				M.tree:render()
			end
		end)
	end, config.sidebar.keybindings.expand)
	-- Map keys for collapsing a tree node
	vim.tbl_map(function(key)
		M.split:map("n", key, function()
			local node = M.tree:get_node()
			if node and node:has_children() then
				node:collapse()
				M.tree:render()
			end
		end)
	end, config.sidebar.keybindings.collapse)
	-- Map keys for refreshing the selected node
	vim.tbl_map(function(key)
		M.split:map("n", key, function()
			-- Find the nearest ancestor node with a refresh function
			local node = M.tree:get_node()
			try_refresh(node)
		end)
	end, config.sidebar.keybindings.refresh)
	-- Map keys for refreshing the sidebar
	vim.tbl_map(function(key)
		M.split:map("n", key, function()
			M.refresh()
		end)
	end, config.sidebar.keybindings.refresh_all)
	-- Map keys for quitting the sidebar
	vim.tbl_map(function(key)
		M.split:map("n", key, function()
			M.split:hide()
		end)
	end, config.sidebar.keybindings.quit)
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
	_try_refresh_with_adapter(nodes.database_node.refresh)
end

function M.toggle()
	if M.split then
		if M.split.winid and vim.api.nvim_win_is_valid(M.split.winid) then
			M.split:hide()
		else
			M.split:show()
		end
	else
		M.init()
	end
end
return M
