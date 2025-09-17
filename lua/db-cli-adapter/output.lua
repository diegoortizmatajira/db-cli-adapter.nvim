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

function M.show_csv_output(csv_file)
	M.show()
	vim.api.nvim_buf_call(M.split.bufnr, function()
		-- Delete all lines in the buffer
		vim.api.nvim_buf_set_lines(M.split.bufnr, 0, -1, false, {})
		vim.bo.filetype = "db-cli-output.csv"
		-- Read the CSV file in a new buffer
		vim.cmd("0read " .. csv_file)
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
		vim.notify(vim.inspect(output), vim.log.levels.INFO)
		M.show_csv_output(opts.csv_file)
	end
	return opts
end

return M
