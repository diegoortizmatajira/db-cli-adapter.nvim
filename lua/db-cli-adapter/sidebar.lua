local core = require("db-cli-adapter.core")
local config = require("db-cli-adapter.config").current

local Split = require("nui.split")
local NuiTree = require("nui.tree")
local NuiLine = require("nui.line")

local M = {
	split = nil,
	tree = nil,
	tables_node = nil,
	views_node = nil,
}

local newDatabase = function(text, children)
	return NuiTree.Node({
		icon = config and config.icons.tree.database,
		icon_hl = config and config.highlight.tree.database,
		text = text,
	}, children)
end

--- Create a new folder node
---@param id string The unique identifier for the folder node
---@param text string The display text for the folder node
---@param children? table A list of child nodes within the folder
---@return NuiTree.Node A new folder node
local newFolderNode = function(id, text, children)
	return NuiTree.Node({
		id = id,
		icon = config and config.icons.tree.folder,
		icon_hl = config and config.highlight.tree.folder,
		text = text,
	}, children)
end

--- Create a new table node
---@param table_row string[] A table with two elements: table name and schema name
---@param children? table A list of child nodes (columns)
---@return NuiTree.Node
local newTableNode = function(table_row, children)
	local table_name, schema = unpack(table_row)
	return NuiTree.Node({
		id = string.format("table_%s_%s", schema, table_name),
		icon = config and config.icons.tree.table,
		icon_hl = config and config.highlight.tree.table,
		text = table_name,
		table_name = table_name,
		schema = schema,
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
	M.tables_node = newFolderNode("tables_node", "Tables", {
		newTableNode({ "Table 1", "1" }, {
			newColumnNode({ "Field 1", true, "uuid" }),
			newColumnNode({ "Field 2", false, "int" }),
			newColumnNode({ "Field 3", false, "varchar(255)" }),
			newColumnNode({ "Field 4", false, "boolean" }),
		}),
		newTableNode({ "Table 2", "2" }, {
			newColumnNode({ "Field 1", true, "uuid" }),
			newColumnNode({ "Field 2", false, "int" }),
			newColumnNode({ "Field 3", false, "varchar(255)" }),
			newColumnNode({ "Field 4", false, "boolean" }),
		}),
	})
	M.views_node = newFolderNode("views_node", "Views", {
		newTableNode({ "View 1", "1" }, {
			newColumnNode({ "Field 1", true, "uuid" }),
			newColumnNode({ "Field 2", false, "int" }),
			newColumnNode({ "Field 3", false, "varchar(255)" }),
			newColumnNode({ "Field 4", false, "boolean" }),
		}),
		newTableNode({ "View 2", "2" }, {
			newColumnNode({ "Field 1", true, "uuid" }),
			newColumnNode({ "Field 2", false, "int" }),
			newColumnNode({ "Field 3", false, "varchar(255)" }),
			newColumnNode({ "Field 4", false, "boolean" }),
		}),
	})
	M.tree = NuiTree({
		bufnr = M.split.bufnr,
		nodes = {
			newDatabase("Database", {
				M.tables_node,
				M.views_node,
			}),
		},
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

--- Refresh the tables in the sidebar by querying the database and grouping them by schema
--- @param adapter DbCliAdapter.AdapterConfig The database adapter to use for querying tables
local function _refresh_tables(adapter)
	core.run(adapter.tablesQuery, {
		callback = function(result)
			if not result then
				vim.notify("Could not refresh the sidebar", vim.log.levels.ERROR)
				return
			end
			--- Create new table nodes from the query result
			local table_nodes_per_schema = {}
			vim.tbl_map(function(row)
				local schema_name = row[2]
				local schema_tables = table_nodes_per_schema[schema_name] or {}
				table.insert(schema_tables, newTableNode(row))
				table_nodes_per_schema[schema_name] = schema_tables
			end, result.data.rows)
			local schema_nodes = {}

			for schema, tables in pairs(table_nodes_per_schema) do
				table.insert(schema_nodes, newFolderNode("schema_" .. schema, schema, tables))
			end
			-- Replace the tables node children with the new nodes
			M.tree:set_nodes(schema_nodes, M.tables_node:get_id())

			M.tree:render()
			vim.notify("DbCliAdapter: Sidebar refreshed succesfully", vim.log.levels.INFO)
		end,
	})
end

function M.refresh()
	local adapter = core.get_buffer_db_adapter()
	if not adapter then
		vim.notify("DbCliAdapter: No selected adapter", vim.log.levels.WARN)
		return
	end
	_refresh_tables(adapter)
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
