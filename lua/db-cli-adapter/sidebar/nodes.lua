local NuiTree = require("nui.tree")
local core = require("db-cli-adapter.core")
local config = require("db-cli-adapter.config").current

local M = {
	--- @type DbCliAdapter.SidebarNodeData|NuiTree.Node
	database_node = nil,
}

--- @class DbCliAdapter.SidebarNodeData
--- @field id string The unique identifier for the node
--- @field icon? string The icon to display next to the node
--- @field icon_hl? string The highlight group for the icon
--- @field text string The display text for the node
--- @field description? string Additional description text for the node
--- @field count? number The number of child nodes (e.g., number of tables in a schema)
--- @field expandable? boolean Whether the node can be expanded to show children
--- @field refresh? fun(self: DbCliAdapter.SidebarNodeData|NuiTree.Node, tree: NuiTree, adapter: DbCliAdapter.AdapterConfig): nil A function to refresh the node's contents

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
	--- @type DbCliAdapter.SidebarNodeData
	local default = {
		id = "",
		icon = "",
		icon_hl = "",
		text = "",
		description = nil,
		refresh = nil,
	}
	o = vim.tbl_extend("force", default, o or {})
	o._id = o.id -- NuiTree expects _id field for unique identification
	return NuiTree.Node(o, children)
end

--- Create a new folder node
---@param id string The unique identifier for the folder node
---@param text string The display text for the folder node
---@param children? table A list of child nodes within the folder
---@param refresh? fun(self: NuiTree.Node, tree: NuiTree, adapter: DbCliAdapter.AdapterConfig): nil A function to refresh the node's contents
---@return DbCliAdapter.SidebarNodeData|NuiTree.Node A new SidebarNode instance
function M.newFolderNode(id, text, children, refresh)
	return M.new_node({
		id = id,
		icon = config and config.icons.tree.folder,
		icon_hl = config and config.highlight.tree.folder,
		text = text,
		refresh = refresh,
		expandable = true,
	}, children)
end

--- Create a new table node
---@param table_row string[] A table with two elements: table name and schema name
---@param children? table A list of child nodes (columns)
---@return DbCliAdapter.SidebarNodeData|NuiTree.Node A new SidebarNode instance
function M.newTableNode(table_row)
	local table_name, schema = unpack(table_row)
	return M.new_node({
		id = M.get_table_id(schema, table_name),
		icon = config and config.icons.tree.table,
		icon_hl = config and config.highlight.tree.table,
		text = table_name,
		table_name = table_name,
		schema = schema,
		refresh = function(self, tree, adapter)
			core.run(adapter:get_table_columns_query(table_name, schema), {
				callback = function(result)
					if not result then
						vim.notify("Could not refresh the sidebar", vim.log.levels.ERROR)
						return
					end
					local column_nodes = {}
					vim.tbl_map(function(row)
						table.insert(column_nodes, M.newColumnNode(row, self))
					end, result.data.rows)
					tree:set_nodes(column_nodes, self:get_id())
					self.count = #column_nodes
					tree:render()
					vim.notify(string.format("'%s' table refreshed succesfully", table_name), vim.log.levels.INFO)
				end,
			})
		end,
		expandable = true,
	})
end

--- Create a new column node
--- @param col_definition table A table with three elements: column name, is_primary_key (boolean), data type
--- @param parent DbCliAdapter.SidebarNodeData|NuiTree.Node The parent node (table) to which this column belongs
---@return DbCliAdapter.SidebarNodeData|NuiTree.Node A new SidebarNode instance
function M.newColumnNode(col_definition, parent)
	local column_name, column_type, is_pk = unpack(col_definition)
	is_pk = is_pk == "1" or is_pk == "true" or is_pk == "YES"
	local icon = config and ((is_pk and config.icons.tree.key) or config.icons.tree.column)
	local icon_hl = config and ((is_pk and config.highlight.tree.key) or config.highlight.tree.column)
	local node = M.new_node({
		id = parent.id .. "_col_" .. column_name,
		icon = icon,
		icon_hl = icon_hl,
		text = column_name,
		description = column_type,
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
		refresh = function(self, tree, adapter)
			core.run(adapter:get_tables_query(schema_name), {
				callback = function(result)
					if not result then
						vim.notify("Could not refresh the sidebar", vim.log.levels.ERROR)
						return
					end
					local table_nodes = {}
					vim.tbl_map(function(row)
						table.insert(table_nodes, M.newTableNode(row))
					end, result.data.rows)
					tree:set_nodes(table_nodes, self.tables_node:get_id())
					self.tables_node.count = #table_nodes
					tree:render()
					vim.notify(
						string.format("'%s' schema branch refreshed succesfully", schema_name),
						vim.log.levels.INFO
					)
				end,
			})
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
		refresh = function(self, tree, adapter)
			core.run(adapter:get_schemas_query(), {
				callback = function(result)
					if not result then
						vim.notify("Could not refresh the schemas", vim.log.levels.ERROR)
						return
					end
					--- Create new table nodes from the query result
					local schema_nodes = {}
					vim.tbl_map(function(row)
						local node = M.newSchemaNode(row[1])
						table.insert(schema_nodes, node)
					end, result.data.rows)
					-- Replace the tables node children with the new nodes
					tree:set_nodes(schema_nodes, self:get_id())
					tree:render()
					vim.notify("Entire database tree refreshed succesfully", vim.log.levels.INFO)
				end,
			})
		end,
	})
end

return M
