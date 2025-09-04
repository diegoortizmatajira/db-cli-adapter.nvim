local M = {}

--- Displays the output.
--- @param output DbCliAdapter.Output The output to be displayed.
function M.display_output(output)
	vim.notify("Output:\n" .. output.message, vim.log.levels.INFO)
end

return M
