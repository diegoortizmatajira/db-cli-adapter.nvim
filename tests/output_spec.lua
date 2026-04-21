local config_mod = require("db-cli-adapter.config")

describe("output", function()
	local previous_config
	local previous_split_module
	local previous_output_module
	local created_buffers = {}

	local function new_split()
		local bufnr = vim.api.nvim_create_buf(false, true)
		table.insert(created_buffers, bufnr)
		return {
			bufnr = bufnr,
			winid = nil,
			mount_calls = 0,
			show_calls = 0,
			hide_calls = 0,
			map_calls = 0,
			mount = function(self)
				self.mount_calls = self.mount_calls + 1
				self.winid = vim.api.nvim_get_current_win()
			end,
			show = function(self)
				self.show_calls = self.show_calls + 1
				self.winid = vim.api.nvim_get_current_win()
			end,
			hide = function(self)
				self.hide_calls = self.hide_calls + 1
				self.winid = nil
			end,
			map = function(self)
				self.map_calls = self.map_calls + 1
			end,
		}
	end

	before_each(function()
		previous_config = config_mod.current
		previous_split_module = package.loaded["nui.split"]
		previous_output_module = package.loaded["db-cli-adapter.output"]

		config_mod.current = vim.tbl_deep_extend("force", config_mod.default, {})
		package.loaded["nui.split"] = function()
			return new_split()
		end
		package.loaded["db-cli-adapter.output"] = nil
	end)

	after_each(function()
		for _, bufnr in ipairs(created_buffers) do
			if vim.api.nvim_buf_is_valid(bufnr) then
				vim.api.nvim_buf_delete(bufnr, { force = true })
			end
		end
		created_buffers = {}
		config_mod.current = previous_config
		package.loaded["nui.split"] = previous_split_module
		package.loaded["db-cli-adapter.output"] = previous_output_module
	end)

	it("re-initializes split when window was closed externally", function()
		local output = require("db-cli-adapter.output")
		output.init()

		local old_split = output.split
		old_split.winid = -1

		output.show()

		assert.are_not.equal(old_split, output.split)
		assert.is_true(vim.api.nvim_buf_is_valid(output.split.bufnr))
	end)

	it("re-initializes split when previous buffer is invalid", function()
		local output = require("db-cli-adapter.output")
		output.init()

		local old_split = output.split
		vim.api.nvim_buf_delete(old_split.bufnr, { force = true })
		old_split.winid = -1

		output.show()

		assert.are_not.equal(old_split, output.split)
		assert.is_true(vim.api.nvim_buf_is_valid(output.split.bufnr))
	end)
end)
