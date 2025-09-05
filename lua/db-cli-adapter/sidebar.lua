local core = require("db-cli-adapter.core")
local config = require("db-cli-adapter.config").current

local Split = require("nui.split")
local NuiTree = require("nui.tree")
local NuiLine = require("nui.line")
local event = require("nui.utils.autocmd").event

local M = {
	split = nil,
	tree = nil,
}

function M.init()
	if not config then
		vim.notify("DbCliAdapter: Configuration not found.", vim.log.levels.ERROR)
		return
	end
	M.split = Split({
		relative = "editor",
		position = "right",
		size = "30%",
	})
	M.split:mount()
	M.tree = NuiTree({
		bufnr = M.split.bufnr,
		nodes = {
			NuiTree.Node({ text = "Root" }, {
				NuiTree.Node({ text = "Child 1" }),
				NuiTree.Node({ text = "Child 2" }, {
					NuiTree.Node({ text = "Grandchild 1" }),
				}),
			}),
		},
		prepare_node = function(node)
			local line = NuiLine()
			line:append(string.rep("  ", node:get_depth() - 1))
			line:append(node:has_children() and (node:is_expanded() and " " or " ") or "  ")
			line:append(node.text)
			return line
		end,
		buf_options = {
			buftype = "nofile",
			filetype = "db-cli-sidebar",
			swapfile = false,
			bufhidden = "hide",
		},
		win_options = {},
	})
	M.tree:render()
	--- Map keys for toggling expand/collapse of a tree node
	vim.tbl_map(function(key)
		M.split:map("n", key, function()
			local node = M.tree:get_node()
			if node and node:has_children() then
				if node:is_expanded() then
					node:collapse()
				else
					node:expand()
				end
				M.tree:render()
			end
		end)
	end, config.sidebar.keybindings.toggle_expand)
	-- Map keys for expanding a tree node
	vim.tbl_map(function(key)
		M.split:map("n", key, function()
			local node = M.tree:get_node()
			if node and node:has_children() then
				node:expand()
				M.tree:render()
			end
		end)
	end, config.sidebar.keybindings.expand)
	-- Map keys for collapsing a tree node
	vim.tbl_map(function(key)
		M.split:map("n", key, function()
			local node = M.tree:get_node()
			if node and node:has_children() then
				node:collapse()
				M.tree:render()
			end
		end)
	end, config.sidebar.keybindings.collapse)
	-- Map keys for refreshing the sidebar
	vim.tbl_map(function(key)
		M.split:map("n", key, function()
			M.refresh()
		end)
	end, config.sidebar.keybindings.refresh)
	-- Map keys for quitting the sidebar
	vim.tbl_map(function(key)
		M.split:map("n", key, function()
			M.split:hide()
		end)
	end, config.sidebar.keybindings.quit)
end

function M.refresh()
	vim.notify("DbCliAdapter: Refreshing sidebar...", vim.log.levels.INFO)
end

function M.toggle()
	if M.split then
		if M.split.winid and vim.api.nvim_win_is_valid(M.split.winid) then
			M.split:hide()
		else
			M.split:show()
			M.refresh()
		end
	else
		M.init()
		-- Ensure a database connection is selected
		if not core.buffer_has_db_connection() then
			core.select_connection(M.refresh)
			return
		end
		M.refresh()
	end
end
return M
