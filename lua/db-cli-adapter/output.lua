local Split = require("nui.split")

local M = {
	split = nil,
}

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
	vim.tbl_map(function(key)
		M.split:map("n", key, function()
			M.split:hide()
		end)
	end, config.sidebar.keybindings.quit)
end

function M.toggle()
	if not M.hide() then
		M.show()
	end
end

function M.show()
	if M.split then
		M.split:show()
	else
		M.init()
	end
end

function M.hide()
	if M.split and M.split.winid and vim.api.nvim_win_is_valid(M.split.winid) then
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
function M.show_csv_output(csv_file)
	local config = require("db-cli-adapter.config").current
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
		-- Delete all lines in the buffer
		vim.api.nvim_buf_set_lines(M.split.bufnr, 0, -1, false, output.discarded_lines)
		vim.bo.filetype = "db-cli-output.text"
	end)
end

--- Sets up a custom output handler for CSV format
--- This handler writes the CSV output to a temporary file and opens it in a new buffer
--- @param opts DbCliAdapter.RunOptions|nil Optional table of execution parameters:
function M.set_csv_output_handler(opts)
	opts = opts or {}
	-- Create a new temp file to store the CSV output
	opts.csv_file = os.tmpname() .. ".csv"
	opts.callback = function(output)
		vim.notify(vim.inspect(output), vim.log.levels.DEBUG)
		M.show_csv_output(opts.csv_file)
	end
	return opts
end

return M
