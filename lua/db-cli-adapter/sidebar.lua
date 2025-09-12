local core = require("db-cli-adapter.core")
local config = require("db-cli-adapter.config").current

local Split = require("nui.split")
local NuiTree = require("nui.tree")
local NuiLine = require("nui.line")

local M = {
	split = nil,
	tree = nil,
	database_node = nil,
	schema_map = {},
}

--- @class DbCliAdapter.SidebarNodeData
--- @field id string The unique identifier for the node
--- @field icon? string The icon to display next to the node
--- @field icon_hl? string The highlight group for the icon
--- @field text string The display text for the node
--- @field description? string Additional description text for the node
--- @field refresh? fun(adapter: DbCliAdapter.AdapterConfig): nil A function to refresh the node's contents

local function get_schema_id(schema_name)
	return "schema_" .. schema_name
end

local function get_table_id(schema_name, table_name)
	return "table_" .. schema_name .. "_" .. table_name
end

--- Create a new SidebarNode
--- @param o DbCliAdapter.SidebarNodeData The properties of the node
--- @param children? table A list of child nodes
--- @return DbCliAdapter.SidebarNodeData|NuiTree.Node A new SidebarNode instance
local function new_node(o, children)
	o = vim.tbl_extend("force", {
		id = "",
		icon = "",
		icon_hl = "",
		text = "",
		description = nil,
		refresh = nil,
	}, o or {})
	o._id = o.id -- NuiTree expects _id field for unique identification
	return NuiTree.Node(o, children)
end

--- Create a new folder node
---@param id string The unique identifier for the folder node
---@param text string The display text for the folder node
---@param children? table A list of child nodes within the folder
---@param refresh? function A function to refresh the folder's contents
---@return DbCliAdapter.SidebarNodeData|NuiTree.Node A new SidebarNode instance
local newFolderNode = function(id, text, children, refresh)
	return new_node({
		id = id,
		icon = config and config.icons.tree.folder,
		icon_hl = config and config.highlight.tree.folder,
		text = text,
		refresh = refresh,
	}, children)
end

--- Create a new table node
---@param table_row string[] A table with two elements: table name and schema name
---@param children? table A list of child nodes (columns)
---@return DbCliAdapter.SidebarNodeData|NuiTree.Node A new SidebarNode instance
local newTableNode = function(table_row, children)
	local table_name, schema = unpack(table_row)
	return new_node({
		id = get_table_id(schema, table_name),
		icon = config and config.icons.tree.table,
		icon_hl = config and config.highlight.tree.table,
		text = table_name,
		table_name = table_name,
		schema = schema,
		refresh = function()
			vim.notify("Refreshing table: " .. table_name, vim.log.levels.INFO)
		end,
	}, children)
end

--- Create a new column node
--- @param col_definition table A table with three elements: column name, is_primary_key (boolean), data type
--- @param parent NuiTree.Node The parent node (table) to which this column belongs
---@return DbCliAdapter.SidebarNodeData|NuiTree.Node A new SidebarNode instance
local newColumnNode = function(col_definition, parent)
	local icon = config and ((col_definition[2] and config.icons.tree.key) or config.icons.tree.column)
	local icon_hl = config and ((col_definition[2] and config.highlight.tree.key) or config.highlight.tree.column)
	local node = new_node({
		id = parent.id .. "_col_" .. col_definition[1],
		icon = icon,
		icon_hl = icon_hl,
		text = col_definition[1],
		description = col_definition[3],
		refresh = function()
			if parent and parent.refresh then
				parent.refresh()
			end
		end,
	})
	return node
end

--- Create a new folder node
--- @param schema_name string The name of the schema
--- @return DbCliAdapter.SidebarNodeData|NuiTree.Node A new SidebarNode instance
local newSchemaNode = function(schema_name)
	local id = get_schema_id(schema_name)
	local tables_node = newFolderNode(id .. "tables_node", "Tables", {})
	local views_node = newFolderNode(id .. "views_node", "Views", {})
	return new_node({
		id = id,
		icon = config and config.icons.tree.schema,
		icon_hl = config and config.highlight.tree.schema,
		text = schema_name,
		tables_node = tables_node,
		views_node = views_node,
	}, { tables_node, views_node })
end

--- Create a new database node
--- @param text string The display text for the database node
--- @return DbCliAdapter.SidebarNodeData|NuiTree.Node A new SidebarNode instance
local newDatabaseNode = function(text)
	return new_node({
		id = "database_node",
		icon = config and config.icons.tree.database or "",
		icon_hl = config and config.highlight.tree.database or "",
		text = text,
		refresh = function(adapter)
			core.run(adapter.schemasQuery, {
				callback = function(result)
					if not result then
						vim.notify("Could not refresh the schemas", vim.log.levels.ERROR)
						return
					end
					M.schema_map = {}
					--- Create new table nodes from the query result
					local schema_nodes = {}
					vim.tbl_map(function(row)
						local node = newSchemaNode(row[1])
						M.schema_map[row[1]] = node
						table.insert(schema_nodes, node)
					end, result.data.rows)
					-- Replace the tables node children with the new nodes
					M.tree:set_nodes(schema_nodes, M.database_node:get_id())
					M.tree:render()
					M._refresh_tables(adapter)
					vim.notify("DbCliAdapter: Schemas refreshed succesfully", vim.log.levels.INFO)
				end,
			})
		end,
	})
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
	M.database_node = newDatabaseNode("Database")
	M.tree = NuiTree({
		bufnr = M.split.bufnr,
		nodes = { M.database_node },
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
function M._refresh_tables(adapter)
	core.run(adapter.tablesQuery, {
		callback = function(result)
			if not result then
				vim.notify("Could not refresh the sidebar", vim.log.levels.ERROR)
				return
			end
			vim.tbl_map(function(row)
				local schema_node = M.schema_map[row[2]]
				if not schema_node then
					vim.notify("Schema node not found for schema: " .. row[2], vim.log.levels.WARN)
				end
				M.tree:add_node(newTableNode(row), schema_node.tables_node:get_id())
			end, result.data.rows)

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
	M.database_node.refresh(adapter)
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
