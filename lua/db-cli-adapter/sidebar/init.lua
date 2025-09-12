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
					or "  ",
				config.highlight.tree.chevron
			)
			if node.icon then
				line:append(node.icon, node.icon_hl or config.highlight.tree.default_icon)
			end
			line:append(node.text)
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
			if node and node:has_children() then
				if node:is_expanded() then
					node:collapse()
				else
					node:expand()
				end
				M.tree:render()
			end
		end)
	end, config.sidebar.keybindings.toggle_expand)
	-- Map keys for expanding a tree node
	vim.tbl_map(function(key)
		M.split:map("n", key, function()
			local node = M.tree:get_node()
			if node and node:has_children() then
				node:expand()
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
			while node do
				if node.refresh then
					_try_refresh_with_adapter(node.refresh)
					return
				end
				node = M.tree:get_node(node:get_parent_id())
			end
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
