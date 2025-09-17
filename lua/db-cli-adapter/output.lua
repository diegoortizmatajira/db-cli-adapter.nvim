local config = require("db-cli-adapter.config").current
local Split = require("nui.split")

local M = {
	split = nil,
}

function M.init()
	M.split = Split({
		relative = "editor",
		position = "bottom",
		size = "30%",
	})
	if config then
		-- Map keys for quitting the sidebar
		vim.tbl_map(function(key)
			M.split:map("n", key, function()
				M.split:hide()
			end)
		end, config.sidebar.keybindings.quit)
	end
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
		-- Focus the split window
		if not (M.split.winid and vim.api.nvim_win_is_valid(M.split.winid)) then
			M.split:mount()
		end
		M.split:show()
		vim.api.nvim_set_current_win(M.split.winid)
		-- Open the CSV file in a new buffer
		vim.cmd("edit " .. opts.csv_file)
		vim.bo.filetype = "db-cli-output.csv"
	end
	return opts
end

return M
