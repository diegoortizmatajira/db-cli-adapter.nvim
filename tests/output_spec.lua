local config_mod = require("db-cli-adapter.config")
local core = require("db-cli-adapter.core")

describe("output", function()
	local previous_config
	local previous_split_module
	local previous_output_module
	local previous_core_run
	local created_buffers = {}
	local created_files = {}

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
		previous_core_run = core.run

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
		for _, file in ipairs(created_files) do
			os.remove(file)
		end
		created_buffers = {}
		created_files = {}
		config_mod.current = previous_config
		package.loaded["nui.split"] = previous_split_module
		package.loaded["db-cli-adapter.output"] = previous_output_module
		core.run = previous_core_run
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

	it("stores CSV query context on the output buffer", function()
		local output = require("db-cli-adapter.output")
		output.init()
		local csv_file = os.tmpname() .. ".csv"
		table.insert(created_files, csv_file)
		vim.fn.writefile({ "id,name", "1,Alice" }, csv_file)

		output.show_csv_output(csv_file, {
			query = "select * from users",
			connection_name = "test-connection",
		})

		assert.are.same({
			query = "select * from users",
			connection = "test-connection",
		}, vim.b[output.split.bufnr].db_cli_csv_result_state)
	end)

	it("refreshes CSV results by re-running the stored query", function()
		local output = require("db-cli-adapter.output")
		output.init()
		local shown = nil
		output.show_csv_output = function(csv_file, context)
			shown = { csv_file = csv_file, context = context }
		end
		vim.b[output.split.bufnr].db_cli_csv_result_state = {
			query = "select * from users",
			connection = "test-connection",
		}
		local run_args = nil
		core.run = function(query, opts)
			run_args = { query = query, opts = opts }
			opts.callback({}, {
				query = query,
				connection_name = opts.connection,
			})
		end

		output.refresh(output.split.bufnr)

		assert.are.equal("select * from users", run_args.query)
		assert.are.equal("test-connection", run_args.opts.connection)
		assert.are.equal("select * from users", shown.context.query)
		assert.are.equal("test-connection", shown.context.connection_name)
	end)
end)
