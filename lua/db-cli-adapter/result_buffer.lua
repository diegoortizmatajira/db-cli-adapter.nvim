local core = require("db-cli-adapter.core")
local config = require("db-cli-adapter.config")
local result_diff = require("db-cli-adapter.result_diff")
local mutation_sql = require("db-cli-adapter.mutation_sql")

local M = {}

local function split_tab_line(line)
	return vim.split(line, "\t", { plain = true, trimempty = false })
end

local function to_row_maps(columns, rows)
	local mapped = {}
	for _, row_values in ipairs(rows or {}) do
		local row = {}
		for i, column in ipairs(columns) do
			row[column] = row_values[i]
		end
		table.insert(mapped, row)
	end
	return mapped
end

local function parse_query_target(query)
	if not query or query == "" then
		return nil, "Missing query context"
	end
	local lowered = query:lower()
	if lowered:find(" join ", 1, true) or lowered:find(" union ", 1, true) then
		return nil, "Editable mode currently supports single-table SELECT statements without JOIN/UNION"
	end
	local table_ref = query:match("[Ff][Rr][Oo][Mm]%s+([%w_%.\"`]+)")
	if not table_ref or table_ref == "" or table_ref:find("%(") then
		return nil, "Could not determine target table from query"
	end
	table_ref = table_ref:gsub("[\"`]", "")
	local parts = vim.split(table_ref, ".", { plain = true, trimempty = true })
	if #parts == 1 then
		return { schema = nil, table = parts[1] }, nil
	end
	if #parts == 2 then
		return { schema = parts[1], table = parts[2] }, nil
	end
	return nil, "Could not determine target table from query"
end

local function open_or_reuse_buffer(target_bufnr)
	if target_bufnr and vim.api.nvim_buf_is_valid(target_bufnr) then
		return target_bufnr
	end
	vim.cmd("botright new")
	local bufnr = vim.api.nvim_get_current_buf()
	return bufnr
end

local function render_result_buffer(bufnr, columns, rows)
	local lines = { table.concat(columns, "\t") }
	for _, row in ipairs(rows or {}) do
		local values = {}
		for i = 1, #columns do
			table.insert(values, row[i] or "")
		end
		table.insert(lines, table.concat(values, "\t"))
	end
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
	vim.bo[bufnr].modifiable = true
	vim.bo[bufnr].readonly = false
	vim.bo[bufnr].buftype = "nofile"
	vim.bo[bufnr].bufhidden = "hide"
	vim.bo[bufnr].swapfile = false
	vim.bo[bufnr].filetype = "db-cli-result"
end

local function render_readonly_result(bufnr, readonly_reason)
	vim.b[bufnr].db_cli_result_readonly_reason = readonly_reason
	vim.bo[bufnr].readonly = true
	vim.bo[bufnr].modifiable = false
	vim.notify(readonly_reason, vim.log.levels.WARN)
end

local function get_state(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return nil, "Invalid buffer"
	end
	local state = vim.b[bufnr].db_cli_result_state
	if not state then
		return nil, "Current buffer is not a db-cli-adapter result buffer"
	end
	return state, nil
end

local function get_adapter_for_state(state)
	if not state or not state.adapter_name then
		return nil
	end
	return config.current and config.current.adapters[state.adapter_name] or nil
end

local function parse_current_rows(bufnr, columns)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	if #lines == 0 then
		return nil, "Result buffer is empty"
	end
	local current_header = split_tab_line(lines[1])
	if #current_header ~= #columns then
		return nil, "Header columns cannot be changed in editable result buffer"
	end
	for i, column in ipairs(columns) do
		if current_header[i] ~= column then
			return nil, "Header columns cannot be changed in editable result buffer"
		end
	end

	local rows = {}
	for i = 2, #lines do
		local line = lines[i]
		if line ~= "" then
			local values = split_tab_line(line)
			if #values ~= #columns then
				return nil, string.format("Line %d has %d values; expected %d", i, #values, #columns)
			end
			local row = {}
			for j, column in ipairs(columns) do
				row[column] = values[j]
			end
			table.insert(rows, row)
		end
	end

	return rows, nil
end

local function generate_changes_and_sql(state, bufnr)
	local current_rows, parse_err = parse_current_rows(bufnr, state.columns)
	if parse_err then
		return nil, nil, parse_err
	end
	local changes, diff_err = result_diff.diff(state.original_rows, current_rows, state.columns, state.pk_columns)
	if diff_err then
		return nil, nil, diff_err
	end
	local adapter = get_adapter_for_state(state)
	local statements = mutation_sql.generate(changes, {
		schema = state.schema,
		table = state.table,
		columns = state.columns,
		pk_columns = state.pk_columns,
	}, adapter)
	return changes, statements, nil
end

local function open_preview_buffer(lines)
	vim.cmd("botright new")
	local preview_bufnr = vim.api.nvim_get_current_buf()
	vim.bo[preview_bufnr].buftype = "nofile"
	vim.bo[preview_bufnr].bufhidden = "wipe"
	vim.bo[preview_bufnr].swapfile = false
	vim.bo[preview_bufnr].modifiable = true
	vim.api.nvim_buf_set_lines(preview_bufnr, 0, -1, false, lines)
	vim.bo[preview_bufnr].filetype = "sql"
	vim.bo[preview_bufnr].modifiable = false
	vim.bo[preview_bufnr].readonly = true
end

local function set_result_state(bufnr, state)
	vim.b[bufnr].db_cli_result_state = state
	vim.b[bufnr].db_cli_result_buffer = true
end

local function open_result(result, context, table_meta, pk_columns, opts)
	local columns = (result.data and result.data.column_names) or {}
	local rows = (result.data and result.data.rows) or {}
	local bufnr = open_or_reuse_buffer(opts.target_bufnr)
	render_result_buffer(bufnr, columns, rows)

	local state = {
		query = context.query,
		connection = context.connection_name,
		adapter_name = context.adapter_name,
		schema = table_meta and table_meta.schema or nil,
		table = table_meta and table_meta.table or nil,
		columns = columns,
		pk_columns = pk_columns or {},
		original_rows = to_row_maps(columns, rows),
		editable = #pk_columns > 0,
	}
	set_result_state(bufnr, state)
	if not state.editable then
		render_readonly_result(bufnr, opts.readonly_reason or "Result opened in readonly mode")
		return
	end
	vim.notify("Editable result buffer ready. Use :DbCliResultPreviewChanges before commit.", vim.log.levels.INFO)
end

--- Opens an editable result buffer from query output.
--- @param result DbCliAdapter.Output
--- @param context table
--- @param opts? table
function M.open_from_result(result, context, opts)
	opts = opts or {}
	if not result or not result.data or not result.data.column_names then
		vim.notify("No tabular result data available to open in editable mode", vim.log.levels.WARN)
		return
	end
	if not context or not context.query or not context.connection_name then
		vim.notify("Missing query context for editable result mode", vim.log.levels.ERROR)
		return
	end

	local table_meta, query_err = parse_query_target(context.query)
	if query_err then
		open_result(result, context, nil, {}, {
			target_bufnr = opts.target_bufnr,
			readonly_reason = query_err,
		})
		return
	end

	local adapter = context.adapter
	local pk_query = adapter and adapter.get_primary_keys_query and adapter:get_primary_keys_query(table_meta.schema, table_meta.table)
	if not pk_query or pk_query == "" then
		open_result(result, context, table_meta, {}, {
			target_bufnr = opts.target_bufnr,
			readonly_reason = "Adapter could not resolve primary keys for this table",
		})
		return
	end

	core.run(pk_query, {
		connection = context.connection_name,
		callback = function(pk_result)
			local pk_columns = {}
			for _, row in ipairs((pk_result.data and pk_result.data.rows) or {}) do
				if row[1] and row[1] ~= "" then
					table.insert(pk_columns, row[1])
				end
			end
			if #pk_columns == 0 then
				open_result(result, context, table_meta, {}, {
					target_bufnr = opts.target_bufnr,
					readonly_reason = "No primary key columns found for target table",
				})
				return
			end
			local result_columns = result.data.column_names
			for _, pk in ipairs(pk_columns) do
				if not vim.tbl_contains(result_columns, pk) then
					open_result(result, context, table_meta, {}, {
						target_bufnr = opts.target_bufnr,
						readonly_reason = string.format("Result does not include PK column '%s'", pk),
					})
					return
				end
			end
			open_result(result, context, table_meta, pk_columns, {
				target_bufnr = opts.target_bufnr,
			})
		end,
	})
end

--- Computes pending changes from the current result buffer.
--- @param bufnr? number
--- @return table|nil changes
--- @return string|nil err
function M.compute_changes(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local state, state_err = get_state(bufnr)
	if state_err then
		return nil, state_err
	end
	if not state.editable then
		return nil, vim.b[bufnr].db_cli_result_readonly_reason or "Result buffer is readonly"
	end
	local changes, _, err = generate_changes_and_sql(state, bufnr)
	if err then
		return nil, err
	end
	return changes, nil
end

--- Opens a preview buffer with generated SQL statements.
--- @param bufnr? number
function M.preview_changes(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local state, state_err = get_state(bufnr)
	if state_err then
		vim.notify(state_err, vim.log.levels.ERROR)
		return
	end
	local changes, statements, err = generate_changes_and_sql(state, bufnr)
	if err then
		vim.notify(err, vim.log.levels.ERROR)
		return
	end

	local lines = {
		string.format("-- Target table: %s%s", state.schema and (state.schema .. ".") or "", state.table or ""),
		string.format("-- Inserts: %d", #(changes.inserts or {})),
		string.format("-- Updates: %d", #(changes.updates or {})),
		string.format("-- Deletes: %d", #(changes.deletes or {})),
		"",
	}
	if #statements == 0 then
		table.insert(lines, "-- No pending row changes")
	else
		vim.list_extend(lines, statements)
	end
	open_preview_buffer(lines)
end

--- Commits pending changes in the result buffer to the original connection.
--- @param bufnr? number
function M.commit_changes(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local state, state_err = get_state(bufnr)
	if state_err then
		vim.notify(state_err, vim.log.levels.ERROR)
		return
	end
	local _, statements, err = generate_changes_and_sql(state, bufnr)
	if err then
		vim.notify(err, vim.log.levels.ERROR)
		return
	end
	if #statements == 0 then
		vim.notify("No pending row changes to commit", vim.log.levels.INFO)
		return
	end
	local sql_batch = table.concat(statements, "\n")
	core.run(sql_batch, {
		connection = state.connection,
		callback = function()
			vim.notify("Changes committed. Refreshing result set...", vim.log.levels.INFO)
			M.refresh(bufnr)
		end,
	})
end

--- Re-runs the original query and refreshes the current result buffer.
--- @param bufnr? number
function M.refresh(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local state, state_err = get_state(bufnr)
	if state_err then
		vim.notify(state_err, vim.log.levels.ERROR)
		return
	end
	core.run(state.query, {
		connection = state.connection,
		callback = function(result, context)
			M.open_from_result(result, context, { target_bufnr = bufnr })
		end,
	})
end

return M
