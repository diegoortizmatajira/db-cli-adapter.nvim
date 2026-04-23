local Split = require("nui.split")
local core = require("db-cli-adapter.core")

local M = {
	split = nil,
}

local function has_valid_buffer(split)
	return split and split.bufnr and vim.api.nvim_buf_is_valid(split.bufnr)
end

local function has_valid_window(split)
	return split and split.winid and vim.api.nvim_win_is_valid(split.winid)
end

function M.init()
	local config = require("db-cli-adapter.config").current
	if not config then
		vim.notify("DbCliAdapter: Configuration not found.", vim.log.levels.ERROR)
		return
	end
	M.split = Split({
		relative = "editor",
		position = "bottom",
		size = "30%",
	})
	M.split:mount()
	-- Map keys for quitting the sidebar
	for _, key in ipairs(config.sidebar.keybindings.quit) do
		M.split:map("n", key, function()
			M.split:hide()
		end)
	end
end

function M.toggle()
	if not M.hide() then
		M.show()
	end
end

function M.show()
	if has_valid_window(M.split) then
		M.split:show()
		return
	end
	if M.split and M.split.unmount then
		pcall(function()
			M.split:unmount()
		end)
	end
	if not has_valid_buffer(M.split) then
		M.split = nil
	end
	M.init()
end

function M.hide()
	if has_valid_window(M.split) then
		M.split:hide()
		return true
	end
	return false
end

--- Displays the content of a CSV file in the split buffer
--- This function will clear the current buffer content, set the filetype to "db-cli-output.csv",
--- and read the provided CSV file into the buffer. An optional callback from the configuration
--- can be invoked after the file is loaded.
--- @param csv_file string The path to the CSV file to display
--- @param context? table Query context containing `query` and `connection_name`
function M.show_csv_output(csv_file, context)
	local config = require("db-cli-adapter.config").current
	if vim.fn.filereadable(csv_file) == 0 then
		vim.notify("DbCliAdapter: CSV output file not found: " .. csv_file, vim.log.levels.ERROR)
		return
	end
	M.show()
	vim.api.nvim_buf_call(M.split.bufnr, function()
		-- Set the buffer to be modifiable
		vim.bo.modifiable = true
		vim.bo.readonly = false

		-- Delete all lines in the buffer
		vim.api.nvim_buf_set_lines(M.split.bufnr, 0, -1, false, {})
		vim.bo.filetype = "db-cli-output.csv"
		-- Read the CSV file in a new buffer
		vim.cmd("0read " .. csv_file)
		if context and context.query and context.connection_name then
			vim.b[M.split.bufnr].db_cli_csv_result_state = {
				query = context.query,
				connection = context.connection_name,
			}
		else
			vim.b[M.split.bufnr].db_cli_csv_result_state = nil
		end

		-- Set the buffer to be readonly again
		vim.bo.modifiable = false
		vim.bo.readonly = true
		if config and config.output and config.output.csv and config.output.csv.after_query_callback then
			config.output.csv.after_query_callback(M.split.bufnr, csv_file)
		end
	end)
end

--- Displays the given text output in the split buffer
--- @param output DbCliAdapter.Output The text output to display
function M.show_text_output(output)
	M.show()
	vim.api.nvim_buf_call(M.split.bufnr, function()
		vim.bo.modifiable = true
		vim.bo.readonly = false
		vim.api.nvim_buf_set_lines(M.split.bufnr, 0, -1, false, output.discarded_lines)
		vim.bo.filetype = "db-cli-output.text"
		vim.bo.modifiable = false
		vim.bo.readonly = true
	end)
end

--- Sets up a custom output handler for CSV format
--- This handler writes the CSV output to a temporary file and opens it in a new buffer
--- @param opts DbCliAdapter.RunOptions|nil Optional table of execution parameters:
function M.set_csv_output_handler(opts)
	opts = opts or {}
	-- Clean up the previous temp file before creating a new one
	if M._last_csv_file then
		os.remove(M._last_csv_file)
	end
	-- Create a new temp file to store the CSV output
	opts.csv_file = os.tmpname() .. ".csv"
	M._last_csv_file = opts.csv_file
	opts.callback = function(output, context)
		vim.notify(vim.inspect(output), vim.log.levels.DEBUG)
		M.show_csv_output(opts.csv_file, context)
	end
	return opts
end

--- Re-runs the original query for a CSV output buffer.
--- @param bufnr? number
function M.refresh(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if not vim.api.nvim_buf_is_valid(bufnr) then
		vim.notify("Invalid buffer", vim.log.levels.ERROR)
		return
	end
	local state = vim.b[bufnr].db_cli_csv_result_state
	if not state or not state.query or not state.connection then
		vim.notify("Current buffer is not a CSV result buffer", vim.log.levels.ERROR)
		return
	end
	local opts = M.set_csv_output_handler({
		connection = state.connection,
	})
	core.run(state.query, opts)
end

return M
