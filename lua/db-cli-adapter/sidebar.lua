local core = require("db-cli-adapter.core")
local config = require("db-cli-adapter.config").current

local Split = require("nui.split")
local NuiTree = require("nui.tree")
local NuiLine = require("nui.line")

local M = {
	split = nil,
	tree = nil,
}

local newDatabase = function(text, children)
	return NuiTree.Node({
		icon = config and config.icons.tree.database,
		icon_hl = config and config.highlight.tree.database,
		text = text,
	}, children)
end
local newFolderNode = function(text, children)
	return NuiTree.Node({
		icon = config and config.icons.tree.folder,
		icon_hl = config and config.highlight.tree.folder,
		text = text,
	}, children)
end

local newTableNode = function(text, children)
	return NuiTree.Node({
		icon = config and config.icons.tree.table,
		icon_hl = config and config.highlight.tree.table,
		text = text,
	}, children)
end

local newColumnNode = function(col_definition, children)
	local icon = config and ((col_definition[2] and config.icons.tree.key) or config.icons.tree.column)
	local icon_hl = config and ((col_definition[2] and config.highlight.tree.key) or config.highlight.tree.column)
	local node = NuiTree.Node({
		icon = icon,
		icon_hl = icon_hl,
		text = col_definition[1],
		description = col_definition[3],
	}, children)
	return node
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
	M.tree = NuiTree({
		bufnr = M.split.bufnr,
		nodes = {
			newDatabase("Database", {
				newFolderNode("Tables", {
					newTableNode("Table 1", {
						newColumnNode({ "Field 1", true, "uuid" }),
						newColumnNode({ "Field 2", false, "int" }),
						newColumnNode({ "Field 3", false, "varchar(255)" }),
						newColumnNode({ "Field 4", false, "boolean" }),
					}),
					newTableNode("Table 2", {
						newColumnNode({ "Field 1", true, "uuid" }),
						newColumnNode({ "Field 2", false, "int" }),
						newColumnNode({ "Field 3", false, "varchar(255)" }),
						newColumnNode({ "Field 4", false, "boolean" }),
					}),
				}),
			}),
		},
		prepare_node = function(node)
			local line = NuiLine()
			line:append(string.rep("  ", node:get_depth() - 1))
			line:append(node:has_children() and (node:is_expanded() and " " or " ") or "  ")
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
	-- Map keys for refreshing the sidebar
	vim.tbl_map(function(key)
		M.split:map("n", key, function()
			M.refresh()
		end)
	end, config.sidebar.keybindings.refresh)
	-- Map keys for quitting the sidebar
	vim.tbl_map(function(key)
		M.split:map("n", key, function()
			M.split:hide()
		end)
	end, config.sidebar.keybindings.quit)
end

function M.refresh()
	local adapter = core.get_buffer_db_adapter()
	if not adapter then
		vim.notify("DbCliAdapter: No selected adapter", vim.log.levels.WARN)
		return
	end
	core.run(adapter.schemasQuery, {
		callback = function(result)
			if not result then
				vim.notify("Could not refresh the sidebar", vim.log.levels.ERROR)
				return
			end
			local table_nodes = {}
			for _, row in ipairs(result.data.rows) do
				table.insert(table_nodes, NuiTree.Node({ text = row[1] }))
			end
			M.tree:set_nodes({
				NuiTree.Node({ text = "Tables" }, table_nodes),
			})
			M.tree:render()
			vim.notify("DbCliAdapter: Refreshing sidebar...", vim.log.levels.INFO)
		end,
	})
end

function M.toggle()
	if M.split then
		if M.split.winid and vim.api.nvim_win_is_valid(M.split.winid) then
			M.split:hide()
		else
			M.split:show()
			M.refresh()
		end
	else
		M.init()
		-- Ensure a database connection is selected
		if not core.buffer_has_db_connection() then
			core.select_connection(M.refresh)
			return
		end
		M.refresh()
	end
end
return M
