local NuiTree = require("nui.tree")
local core = require("db-cli-adapter.core")
local config = require("db-cli-adapter.config").current

local M = {
	--- @type DbCliAdapter.SidebarNodeData|NuiTree.Node
	database_node = nil,
	schema_map = {},
}

--- @class DbCliAdapter.SidebarNodeData
--- @field id string The unique identifier for the node
--- @field icon? string The icon to display next to the node
--- @field icon_hl? string The highlight group for the icon
--- @field text string The display text for the node
--- @field description? string Additional description text for the node
--- @field refresh? fun(tree: NuiTree, adapter: DbCliAdapter.AdapterConfig): nil A function to refresh the node's contents

function M.get_schema_id(schema_name)
	return "schema_" .. schema_name
end

function M.get_table_id(schema_name, table_name)
	return "table_" .. schema_name .. "_" .. table_name
end

--- Create a new SidebarNode
--- @param o DbCliAdapter.SidebarNodeData The properties of the node
--- @param children? table A list of child nodes
--- @return DbCliAdapter.SidebarNodeData|NuiTree.Node A new SidebarNode instance
function M.new_node(o, children)
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
function M.newFolderNode(id, text, children, refresh)
	return M.new_node({
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
function M.newTableNode(table_row, children)
	local table_name, schema = unpack(table_row)
	return M.new_node({
		id = M.get_table_id(schema, table_name),
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
function M.newColumnNode(col_definition, parent)
	local icon = config and ((col_definition[2] and config.icons.tree.key) or config.icons.tree.column)
	local icon_hl = config and ((col_definition[2] and config.highlight.tree.key) or config.highlight.tree.column)
	local node = M.new_node({
		id = parent.id .. "_col_" .. col_definition[1],
		icon = icon,
		icon_hl = icon_hl,
		text = col_definition[1],
		description = col_definition[3],
		refresh = function(adapter)
			if parent and parent.refresh then
				parent.refresh(adapter)
			end
		end,
	})
	return node
end

--- Create a new folder node
--- @param schema_name string The name of the schema
--- @return DbCliAdapter.SidebarNodeData|NuiTree.Node A new SidebarNode instance
function M.newSchemaNode(schema_name)
	local id = M.get_schema_id(schema_name)
	local tables_node = M.newFolderNode(id .. "tables_node", "Tables", {})
	local views_node = M.newFolderNode(id .. "views_node", "Views", {})
	return M.new_node({
		id = id,
		icon = config and config.icons.tree.schema,
		icon_hl = config and config.highlight.tree.schema,
		text = schema_name,
		tables_node = tables_node,
		views_node = views_node,
		refresh = function(tree, adapter)
			vim.notify(string.format("'%s' schema branch refreshed succesfully", schema_name), vim.log.levels.INFO)
		end,
	}, { tables_node, views_node })
end

--- Create a new database node
--- @param text string The display text for the database node
--- @return DbCliAdapter.SidebarNodeData|NuiTree.Node A new SidebarNode instance
function M.newDatabaseNode(text)
	return M.new_node({
		id = "database_node",
		icon = config and config.icons.tree.database or "",
		icon_hl = config and config.highlight.tree.database or "",
		text = text,
		refresh = function(tree, adapter)
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
						local node = M.newSchemaNode(row[1])
						M.schema_map[row[1]] = node
						table.insert(schema_nodes, node)
					end, result.data.rows)
					-- Replace the tables node children with the new nodes
					tree:set_nodes(schema_nodes, M.database_node:get_id())
					tree:render()
					M._refresh_tables(tree, adapter)
					vim.notify("Entire database tree refreshed succesfully", vim.log.levels.INFO)
				end,
			})
		end,
	})
end

--- Refresh the tables in the sidebar by querying the database and grouping them by schema
--- @param adapter DbCliAdapter.AdapterConfig The database adapter to use for querying tables
function M._refresh_tables(tree, adapter)
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
				tree:add_node(M.newTableNode(row), schema_node.tables_node:get_id())
			end, result.data.rows)

			tree:render()
			vim.notify("DbCliAdapter: Sidebar refreshed succesfully", vim.log.levels.INFO)
		end,
	})
end
return M
