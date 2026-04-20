local M = {}

local function default_quote_identifier(identifier)
	return string.format('"%s"', tostring(identifier):gsub('"', '""'))
end

local function default_format_literal(value)
	if value == nil then
		return "NULL"
	end
	return string.format("'%s'", tostring(value):gsub("'", "''"))
end

local function table_fqn(table_meta, quote_identifier)
	if table_meta.schema and table_meta.schema ~= "" then
		return quote_identifier(table_meta.schema) .. "." .. quote_identifier(table_meta.table)
	end
	return quote_identifier(table_meta.table)
end

local function build_where_pk(pk_values, pk_columns, quote_identifier, format_literal)
	local predicates = {}
	for _, column in ipairs(pk_columns) do
		local value = pk_values[column]
		local quoted = quote_identifier(column)
		if value == nil then
			table.insert(predicates, string.format("%s IS NULL", quoted))
		else
			table.insert(predicates, string.format("%s = %s", quoted, format_literal(value)))
		end
	end
	return table.concat(predicates, " AND ")
end

--- @param changes table
--- @param table_meta table
--- @param adapter DbCliAdapter.AdapterConfig
--- @return string[] statements
function M.generate(changes, table_meta, adapter)
	local quote_identifier = adapter and adapter.quote_identifier or default_quote_identifier
	local format_literal = adapter and adapter.format_literal or default_format_literal
	local fqn = table_fqn(table_meta, quote_identifier)
	local pk_columns = table_meta.pk_columns or {}

	local statements = {}

	for _, insert_change in ipairs(changes.inserts or {}) do
		local columns = {}
		local values = {}
		for _, column in ipairs(table_meta.columns or {}) do
			table.insert(columns, quote_identifier(column))
			table.insert(values, format_literal(insert_change.row[column]))
		end
		table.insert(
			statements,
			string.format(
				"INSERT INTO %s (%s) VALUES (%s);",
				fqn,
				table.concat(columns, ", "),
				table.concat(values, ", ")
			)
		)
	end

	for _, update_change in ipairs(changes.updates or {}) do
		local assignments = {}
		for _, column in ipairs(table_meta.columns or {}) do
			if not vim.tbl_contains(pk_columns, column) then
				local changed = update_change.changed_columns[column]
				if changed then
					table.insert(assignments, string.format("%s = %s", quote_identifier(column), format_literal(changed.new)))
				end
			end
		end
		if #assignments > 0 then
			table.insert(
				statements,
				string.format(
					"UPDATE %s SET %s WHERE %s;",
					fqn,
					table.concat(assignments, ", "),
					build_where_pk(update_change.pk, pk_columns, quote_identifier, format_literal)
				)
			)
		end
	end

	for _, delete_change in ipairs(changes.deletes or {}) do
		table.insert(
			statements,
			string.format(
				"DELETE FROM %s WHERE %s;",
				fqn,
				build_where_pk(delete_change.pk, pk_columns, quote_identifier, format_literal)
			)
		)
	end

	return statements
end

return M
