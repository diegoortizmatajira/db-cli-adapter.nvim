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
	opts.callback = function(output)
		-- Createa new temp file to store the CSV output
		local temp_file = os.tmpname() .. ".csv"
		local file = io.open(temp_file, "w")
		if file then
			file:write(table.concat(output.data.column_names, ",") .. "\n")
			for _, row in ipairs(output.data.rows) do
				file:write(table.concat(row, ",") .. "\n")
			end
			file:close()
		else
			vim.notify("Failed to create temporary file for CSV output", vim.log.levels.ERROR)
			return
		end
		M.split:show()
		-- Focus the split window
		vim.api.nvim_set_current_win(M.split.winid)
		-- Open the CSV file in a new buffer
		vim.cmd("edit " .. temp_file)
	end
	return opts
end

return M
