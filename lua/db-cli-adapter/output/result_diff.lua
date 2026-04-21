local M = {}

local function build_pk_key(row, pk_columns)
	local parts = {}
	local pk_values = {}
	for _, column in ipairs(pk_columns) do
		local value = row[column]
		if value == nil or value == "" then
			return nil, nil, string.format("Missing PK value for column '%s'", column)
		end
		pk_values[column] = value
		table.insert(parts, tostring(value))
	end
	return table.concat(parts, "\31"), pk_values, nil
end

local function index_rows(rows, pk_columns)
	local indexed = {}
	for i, row in ipairs(rows) do
		local key, pk_values, err = build_pk_key(row, pk_columns)
		if err then
			return nil, string.format("Row %d: %s", i, err)
		end
		if indexed[key] then
			return nil, string.format("Duplicate PK detected at row %d", i)
		end
		indexed[key] = {
			row = row,
			pk = pk_values,
		}
	end
	return indexed, nil
end

--- @param original_rows table[]
--- @param current_rows table[]
--- @param columns string[]
--- @param pk_columns string[]
--- @return table|nil changes
--- @return string|nil err
function M.diff(original_rows, current_rows, columns, pk_columns)
	if #pk_columns == 0 then
		return nil, "PK columns are required to diff result rows"
	end

	local original_index, original_err = index_rows(original_rows, pk_columns)
	if original_err then
		return nil, original_err
	end
	local current_index, current_err = index_rows(current_rows, pk_columns)
	if current_err then
		return nil, current_err
	end

	local changes = {
		inserts = {},
		updates = {},
		deletes = {},
	}

	for key, current in pairs(current_index) do
		local original = original_index[key]
		if not original then
			table.insert(changes.inserts, {
				pk = current.pk,
				row = current.row,
			})
		else
			local changed_columns = {}
			for _, column in ipairs(columns) do
				local old_value = original.row[column]
				local new_value = current.row[column]
				if old_value ~= new_value then
					changed_columns[column] = {
						old = old_value,
						new = new_value,
					}
				end
			end

			local has_non_pk_changes = false
			for column, _ in pairs(changed_columns) do
				local is_pk = vim.tbl_contains(pk_columns, column)
				if not is_pk then
					has_non_pk_changes = true
					break
				end
			end

			if has_non_pk_changes then
				table.insert(changes.updates, {
					pk = current.pk,
					row = current.row,
					original_row = original.row,
					changed_columns = changed_columns,
				})
			end
		end
	end

	for key, original in pairs(original_index) do
		if not current_index[key] then
			table.insert(changes.deletes, {
				pk = original.pk,
				row = original.row,
			})
		end
	end

	return changes, nil
end

return M
