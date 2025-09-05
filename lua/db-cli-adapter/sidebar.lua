local core = require("db-cli-adapter.core")
local M = {
	sidebar = nil,
}
local function create_sidebar(position)
	local width = 30
	local buf = vim.api.nvim_create_buf(false, true) -- Create a new empty buffer

	-- Determine the split direction and position
	if position == "right" then
		vim.cmd(width .. "vsplit") -- Create a vertical split on the right
	else
		vim.cmd(width .. "vsplit") -- Create a vertical split; default to left
	end

	vim.api.nvim_win_set_buf(0, buf) -- Set the buffer to the current window

	-- Disable line numbers, gutter decorations, and make buffer read-only
	vim.api.nvim_set_option_value("number", false, { scope = "local" })
	vim.api.nvim_set_option_value("relativenumber", false, { scope = "local" })
	vim.api.nvim_set_option_value("signcolumn", "no", { scope = "local" })
	vim.api.nvim_set_option_value("modifiable", false, { scope = "local" })

	return { buf = buf, win = vim.api.nvim_get_current_win() }
end

function M.refresh() end

function M.toggle(position, on_display)
	position = position or "right" -- Default to right if no position is provided

	-- Close the sidebar if it exists
	if M.sidebar and vim.api.nvim_win_is_valid(M.sidebar.win) then
		vim.api.nvim_win_close(M.sidebar.win, true)
		M.sidebar = nil
		vim.notify("Sidebar closed", vim.log.levels.INFO)
		return
	end

	-- Create a new sidebar
	M.sidebar = create_sidebar(position)

	-- Set filetype to 'db-cli-sidebar' if sidebar buffer exists
	if M.sidebar and M.sidebar.buf then
		vim.api.nvim_set_option_value("filetype", "db-cli-sidebar", { scope = "local", buf = M.sidebar.buf })
	end

	local function local_on_display()
		-- Trigger the on_display callback if provided
		if on_display and type(on_display) == "function" then
			on_display()
		end
		M.refresh()
		vim.notify("Sidebar opened", vim.log.levels.INFO)
	end
	-- Ensure a database connection is selected
	if not core.buffer_has_db_connection() then
		core.select_connection(local_on_display)
		return
	end
	local_on_display()
end
return M
